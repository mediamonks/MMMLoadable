//
// MMMLoadable. Part of MMMTemple.
// Copyright (C) 2016-2025 Monks. All rights reserved.
//

#import "MMMLoadable.h"
#import "MMMLoadable+Subclasses.h"

#if SWIFT_PACKAGE
@import MMMCommonCoreObjC;
#else
@import MMMCommonCore;
#endif

#if __has_include(<UIKit/UIKit.h>)
#import <UIKit/UIKit.h>
#define __HAS_UI_KIT__
#endif

#pragma mark - MMMLoadable

NSString *NSStringFromMMMLoadableState(MMMLoadableState state) {
	MMM_ENUM_NAME_BEGIN(MMMLoadableState, state)
		MMM_ENUM_CASE(MMMLoadableStateIdle)
		MMM_ENUM_CASE(MMMLoadableStateSyncing)
		MMM_ENUM_CASE(MMMLoadableStateDidSyncSuccessfully)
		MMM_ENUM_CASE(MMMLoadableStateDidFailToSync)
	MMM_ENUM_NAME_END()
}

// MMMLoadable and friends were never meant to be thread-safe, however it's still easy to touch them from different
// threads accidentally (especially now with async/await), so let's try to detect incorrect usage with this macro.

#ifdef DEBUG
	/// Asserts about the current thread being "main" unless +concurrency
	#define MMM_CHECK_THREAD() \
		switch ([self.class concurrency]) { \
		case MMMLoadableConcurrencyMainThread: case MMMLoadableConcurrencyMainThreadExceptInit: \
			NSCAssert( \
				[NSThread isMainThread], \
				@"%@#%s is accessed from a non-main thread; fix that or override +concurrency method.", \
				NSStringFromClass(self.class), sel_getName(_cmd) \
			); \
			break; \
		case MMMLoadableConcurrencyCustom: \
			break; \
		}
#else
	#define MMM_CHECK_THREAD()
#endif

// Another issue with async/await in Swift is that it's too easy for a reference to be captured in one of the task
// closures and then released calling `dealloc` on a random thread.
//
// Before we used to assert in `dealloc` too, but this is not practical, because objects can be captured outside
// of our control. For example, Datadog makes snapshots of SwiftUI views to process them in the background. When it
// releases a snapshot that happens to reference a loadable, then our `dealloc` will be performed on a non-main thread.
//
// Instead of asserting, we are now trying to ensure that the stuff we do in `dealloc` (mainly unsubscribing from
// other loadables) is safe.
static void DispatchOnMainThread(void (^block)(void)) {
	if ([NSThread isMainThread]) {
		block();
	} else {
		dispatch_async(dispatch_get_main_queue(), block);
	}
}

//
//
//
@interface MMMLoadable ()
@property (nonatomic, readwrite) MMMLoadableState loadableState;
@property (nonatomic, readwrite) NSError *error;
@end

@implementation MMMLoadable {
	MMMObserverHub<id<MMMLoadableObserver>> *_observerHub;
}

+ (MMMLoadableConcurrency)concurrency {
	return MMMLoadableConcurrencyMainThread;
}

- (id)init {
	if (self = [super init]) {
		_observerHub = [[MMMObserverHub alloc] initWithObservable:self];
	}
	return self;
}

- (void)setLoadableState:(MMMLoadableState)loadableState {
	MMM_CHECK_THREAD();
	// Note that we do not check if the state is the same and notify the observers anyway.
	// This is handy when we are already in 'did load' state and want to communicate changes in the contents
	// happening without transitions between loadable states.
	_loadableState = loadableState;
	[self notifyDidChange];
}

- (void)setSyncing {
	MMM_CHECK_THREAD();
	self.loadableState = MMMLoadableStateSyncing;
}

- (void)setFailedToSyncWithError:(NSError *)error {
	MMM_CHECK_THREAD();
	if (_loadableState != MMMLoadableStateDidFailToSync) {
		_error = error;
		self.loadableState = MMMLoadableStateDidFailToSync;
	}
}

- (void)setDidSyncSuccessfully {
	MMM_CHECK_THREAD();
	_error = nil;
	self.loadableState = MMMLoadableStateDidSyncSuccessfully;
}

- (void)syncIfNeeded {
	MMM_CHECK_THREAD();
	if (self.needsSync)
		[self sync];
}

- (void)sync {

	MMM_CHECK_THREAD();

	if (self.loadableState == MMMLoadableStateSyncing) {
		// Syncing is in progress already, ignoring the new request
		return;
	}

	// It makes sense to reset the error to ensure it won't remain from the previous failure especially
	// in case the subclass touches `loadableState` directly instead of using `setFailedToSyncWithError:`
	// or `setDidSyncSuccessfully:`.
	_error = nil;

	self.loadableState = MMMLoadableStateSyncing;

	[self doSync];
}

#pragma mark - Overridables

- (BOOL)isContentsAvailable {
	MMM_CHECK_THREAD();
	return NO;
}

- (BOOL)needsSync {
	MMM_CHECK_THREAD();
	return !self.contentsAvailable
		|| (self.loadableState == MMMLoadableStateDidFailToSync)
		|| (self.loadableState == MMMLoadableStateIdle);
}

- (void)doSync {
	MMM_MUST_BE_IMPLEMENTED();
}

#pragma mark -

- (MMMObserverHub *)observerHub {
	MMM_CHECK_THREAD();
	return _observerHub;
}

- (BOOL)hasObservers {
	MMM_CHECK_THREAD();
	return !_observerHub.empty;
}

- (void)didAddFirstObserver {
	// Nothing to do here, but subclasses can override.
}

- (void)didRemoveLastObserver {
	// Nothing to do here, but subclasses can override.
}

- (void)addObserver:(id<MMMLoadableObserver>)observer {

	MMM_CHECK_THREAD();
	BOOL wasEmpty = [_observerHub isEmpty];

	[_observerHub addObserver:observer];

	if (wasEmpty) {
		NSAssert(![_observerHub isEmpty], @"");
		[self didAddFirstObserver];
	}
}

- (void)removeObserver:(id<MMMLoadableObserver>)observer {
	MMM_CHECK_THREAD();
	if ([_observerHub removeObserver:observer] && [_observerHub isEmpty])
		[self didRemoveLastObserver];
}

- (void)notifyDidChange {
	MMM_CHECK_THREAD();
	[_observerHub forEachObserver:^(id<MMMLoadableObserver> observer) {
		[observer loadableDidChange:self];
	}];
}

- (NSString *)debugDescription {
	MMM_CHECK_THREAD();
	return [NSString stringWithFormat:@"<%@: %p; %@, contents available: %d, needs sync: %d>",
		self.class,
		self,
		NSStringFromMMMLoadableState(self.loadableState),
		self.contentsAvailable,
		self.needsSync
	];
}

- (NSString *)description {
	MMM_CHECK_THREAD();
	return [NSString stringWithFormat:@"<%@: %@, contents available: %d, needs sync: %d>",
		self.class,
		NSStringFromMMMLoadableState(self.loadableState),
		self.contentsAvailable,
		self.needsSync
	];
}

@end

//
// Note that I don't want to inherit MMMLoadable from this class, so the implementation is duplicated.
//
@interface MMMPureLoadable ()
@property (nonatomic, readwrite) MMMLoadableState loadableState;
@property (nonatomic, readwrite) NSError *error;
@end

@implementation MMMPureLoadable {
	MMMObserverHub<id<MMMLoadableObserver>> *_observerHub;
}

+ (MMMLoadableConcurrency)concurrency {
	return MMMLoadableConcurrencyMainThread;
}

- (id)init {
	if (self = [super init]) {
		_observerHub = [[MMMObserverHub alloc] initWithObservable:self];
	}
	return self;
}

- (void)setLoadableState:(MMMLoadableState)loadableState {
	MMM_CHECK_THREAD();
	// Note that we do not check if the state is the same and notify the observers anyway.
	// This is handy when we are already in 'did load' state and want to communicate changes in the contents
	// happening without transitions between loadable states.
	_loadableState = loadableState;
	[self notifyDidChange];
}

- (void)setSyncing {
	self.loadableState = MMMLoadableStateSyncing;
}

- (void)setFailedToSyncWithError:(NSError *)error {
	MMM_CHECK_THREAD();
	if (_loadableState != MMMLoadableStateDidFailToSync) {
		_error = error;
		self.loadableState = MMMLoadableStateDidFailToSync;
	}
}

- (void)setDidSyncSuccessfully {
	MMM_CHECK_THREAD();
	_error = nil;
	self.loadableState = MMMLoadableStateDidSyncSuccessfully;
}

#pragma mark - Overridables

- (BOOL)isContentsAvailable {
	MMM_CHECK_THREAD();
	return NO;
}

#pragma mark -

- (MMMObserverHub<id<MMMLoadableObserver>> *)observerHub {
	MMM_CHECK_THREAD();
	return _observerHub;
}

- (BOOL)hasObservers {
	MMM_CHECK_THREAD();
	return !_observerHub.empty;
}

- (void)didAddFirstObserver {
	// Nothing to do here, but subclasses can override.
}

- (void)didRemoveLastObserver {
	// Nothing to do here, but subclasses can override.
}

- (void)addObserver:(id<MMMLoadableObserver>)observer {

	MMM_CHECK_THREAD();

	BOOL wasEmpty = [_observerHub isEmpty];

	[_observerHub addObserver:observer];

	if (wasEmpty) {
		NSAssert(![_observerHub isEmpty], @"");
		[self didAddFirstObserver];
	}
}

- (void)removeObserver:(id<MMMLoadableObserver>)observer {
	MMM_CHECK_THREAD();
	if ([_observerHub removeObserver:observer] && [_observerHub isEmpty])
		[self didRemoveLastObserver];
}

- (void)notifyDidChange {
	MMM_CHECK_THREAD();
	[_observerHub forEachObserver:^(id<MMMLoadableObserver> observer) {
		[observer loadableDidChange:self];
	}];
}

- (NSString *)debugDescription {
	MMM_CHECK_THREAD();
	return [NSString stringWithFormat:@"<%@: %p; %@, contents available: %d>",
		self.class,
		self,
		NSStringFromMMMLoadableState(self.loadableState),
		self.contentsAvailable
	];
}

- (NSString *)description {
	MMM_CHECK_THREAD();
	return [NSString stringWithFormat:@"<%@: %@, contents available: %d>",
		self.class,
		NSStringFromMMMLoadableState(self.loadableState),
		self.contentsAvailable
	];
}

@end

//
//
//

#ifdef __HAS_UI_KIT__

@implementation MMMAutosyncLoadable {
	MMMWeakProxy *_autosyncTimerProxy;
	NSTimer *_autosyncTimer;
}

- (id)init {

	if (self = [super init]) {

		#if !TARGET_OS_WATCH
		[[NSNotificationCenter defaultCenter]
			addObserver:self
			selector:@selector(applicationDidEnterBackground:)
			name:UIApplicationDidEnterBackgroundNotification
			object:nil
		];
		[[NSNotificationCenter defaultCenter]
			addObserver:self
			selector:@selector(applicationDidBecomeActive:)
			name:UIApplicationDidBecomeActiveNotification
			object:nil
		];
		#endif
	}

	return self;
}

- (void)dealloc {

	#if !TARGET_OS_WATCH
	[[NSNotificationCenter defaultCenter]
		removeObserver:self
		name:UIApplicationDidBecomeActiveNotification
		object:nil
	];

	[[NSNotificationCenter defaultCenter]
		removeObserver:self
		name:UIApplicationDidEnterBackgroundNotification
		object:nil
	];
	#endif

	[self clearAutosyncTimer];
}

#pragma mark - Autosync timer

- (NSTimeInterval)autosyncInterval {
	return 60;
}

- (NSTimeInterval)autosyncIntervalWhileInBackground {
	return -1;
}

- (void)clearAutosyncTimer {
	[_autosyncTimer invalidate];
	_autosyncTimer = nil;
	_autosyncTimerProxy = nil;
}

- (void)setupAutosyncTimer {

	[self clearAutosyncTimer];

	if (!self.hasObservers)
		return;

	#if !TARGET_OS_WATCH
	NSTimeInterval timeout;
	if ([UIApplication sharedApplication].applicationState == UIApplicationStateBackground)
		timeout = [self autosyncIntervalWhileInBackground];
	else
		timeout = [self autosyncInterval];
	#else
	NSTimeInterval timeout = [self autosyncInterval];
	#endif

	if (timeout <= 0)
		return;

	_autosyncTimerProxy = [[MMMWeakProxy alloc] initWithTarget:self];
	_autosyncTimer = [NSTimer
		scheduledTimerWithTimeInterval:timeout
		target:_autosyncTimerProxy
		selector:@selector(autosyncTimer)
		userInfo:nil
		repeats:NO
	];
}

- (void)autosyncTimer {
	if (self.needsSync)
		[self sync];
	else
		[self setupAutosyncTimer];
}

- (void)setLoadableState:(MMMLoadableState)loadableState {
	[super setLoadableState:loadableState];
	[self setupAutosyncTimer];
}

- (void)didAddFirstObserver {
	[self syncIfNeeded];
}

- (void)didRemoveLastObserver {
	[self setupAutosyncTimer];
}

- (void)applicationDidEnterBackground:(NSNotification *)n {
	[self clearAutosyncTimer];
}

- (void)applicationDidBecomeActive:(NSNotification *)n {
	[self syncIfNeeded];
}

@end

#endif

#pragma mark - MMMLoadableObserver

//
//
//
@interface MMMLoadableObserverBlockProxy : NSObject <MMMLoadableObserver>
@end

@implementation MMMLoadableObserverBlockProxy {
	MMMLoadableObserverDidChangeBlock _block;
}

- (NSString *)description {
	return [NSString stringWithFormat:@"<%@: %@>", self.class, _block];
}

- (id)initWithBlock:(MMMLoadableObserverDidChangeBlock)block {
	if (self = [super init]) {
		_block = block;
	}
	return self;
}

- (void)loadableDidChange:(id<MMMLoadable>)loadable {
	_block(loadable);
}

@end

//
//
//
@interface MMMLoadableObserverSelectorProxy : NSObject <MMMLoadableObserver>
@end

@implementation MMMLoadableObserverSelectorProxy {
	id<NSObject> __weak _target;
	SEL _selector;
}

- (NSString *)description {
	return [NSString stringWithFormat:@"<%@: %@#%@>", self.class, _target.class, NSStringFromSelector(_selector)];
}

- (id)initWithTarget:(id<NSObject>)target selector:(SEL)selector {

	if (self = [super init]) {
		_target = target;
		_selector = selector;
	}

	return self;
}

- (void)loadableDidChange:(id<MMMLoadable>)loadable {

	id target = _target;
	if (!target)
		return;

	#pragma clang diagnostic push
	#pragma clang diagnostic ignored "-Warc-performSelector-leaks"
	[target performSelector:_selector withObject:loadable];
	#pragma clang diagnostic pop
}

@end

//
//
//
@implementation MMMLoadableObserver {
	id<MMMPureLoadable> __weak _loadable;
	id<MMMLoadableObserver> _proxy;
}

- (id)initWithLoadable:(id<MMMPureLoadable>)loadable proxy:(id<MMMLoadableObserver>)proxy {

	// Short-circuit to nil in case the client tries to subscribe to already nil loadable.
	if (!loadable)
		return nil;

	if (self = [super init]) {

		_loadable = loadable;
		_proxy = proxy;

		[_loadable addObserver:_proxy];
	}

	return self;
}

- (nullable id)initWithLoadable:(nullable id<MMMPureLoadable>)loadable block:(MMMLoadableObserverDidChangeBlock)block {
	
	if (loadable) {
		return [self
			initWithLoadable:loadable
			proxy:[[MMMLoadableObserverBlockProxy alloc] initWithBlock:block]
		];
	}
	
	return nil;
}

- (nullable id)initWithLoadable:(nullable id<MMMPureLoadable>)loadable target:(id<NSObject>)target selector:(SEL)selector {
	
	if (loadable) {
		return [self
			initWithLoadable:loadable
			proxy:[[MMMLoadableObserverSelectorProxy alloc] initWithTarget:target selector:selector]
		];
	}
	
	return nil;
}

- (id)initWithLoadable:(id<MMMLoadable>)loadable observer:(id<MMMLoadableObserver>)observer {
	return [self initWithLoadable:loadable proxy:observer];
}

- (void)dealloc {
	// Note that when the observer is deallocated the target of the proxy should be gone as well, because normally
	// it's the one holding a reference to the observer. Therefore, in case `dealloc` happens to be called from
	// a non-main thread, there is no risk of the original object receiving a notification while the removal
	// is being dispatched.
	id<MMMPureLoadable> loadable = _loadable;
	id<MMMLoadableObserver> proxy = _proxy;
	DispatchOnMainThread(^{
		[loadable removeObserver:proxy];
	});
}

- (void)remove {
	if (_loadable) {
		[_loadable removeObserver:_proxy];
		_loadable = nil;
	}
}

@end

//
//
//
@interface MMMPureLoadableGroup ()
@property (nonatomic, readwrite) NSArray<id<MMMPureLoadable>> *loadables;
@end

@implementation MMMPureLoadableGroup {
	MMMObserverHub<id<MMMLoadableObserver>> *_observerHub;
	MMMLoadableObserverSelectorProxy *_observerProxy;
	MMMLoadableGroupFailurePolicy _failurePolicy;
	MMMLoadableGroupMode _mode;
}

@synthesize loadables = _loadables;
@synthesize contentsAvailable = _contentsAvailable;
@synthesize loadableState = _loadableState;

+ (MMMLoadableConcurrency)concurrency {
	return MMMLoadableConcurrencyMainThread;
}

// For some reason Swift overrides the designated initializer and we cannot call it from our convenience methods,
// thus this "common initializer".

- (id)_initWithLoadables:(nullable NSArray<id<MMMPureLoadable>> *)loadables mode:(MMMLoadableGroupMode)mode {

	if (self = [super init]) {

		_mode = mode;

		// We don't want our subclasses to override our `loadableDidChange:` so we don't subscribe directly.
		_observerProxy = [[MMMLoadableObserverSelectorProxy alloc]
			initWithTarget:self
			selector:@selector(MMMPureLoadableGroup_loadableDidChange:)
		];

		_observerHub = [[MMMObserverHub alloc] initWithObservable:self];

		[self setLoadables:loadables];
	}

	return self;
}

- (id)initWithLoadables:(nullable NSArray<id<MMMPureLoadable>> *)loadables mode:(MMMLoadableGroupMode)mode {
	return [self _initWithLoadables:loadables mode:mode];
}

- (id)initWithLoadables:(NSArray *)loadables failurePolicy:(MMMLoadableGroupFailurePolicy)failurePolicy {
	MMMLoadableGroupMode mode;
	switch (failurePolicy) {
	case MMMLoadableGroupFailurePolicyStrict:
		mode = MMMLoadableGroupModeAll;
		break;
	case MMMLoadableGroupFailurePolicyNever:
		mode = MMMLoadableGroupModeDeprecated;
		break;
	}
	return [self _initWithLoadables:loadables mode:mode];
}

- (id)initWithLoadables:(nullable NSArray<id<MMMPureLoadable>> *)loadables {
	return [self _initWithLoadables:loadables mode:MMMLoadableGroupModeAll];
}

- (void)dealloc {
	NSArray *loadables = _loadables;
	MMMLoadableObserverSelectorProxy *observerProxy = _observerProxy;
	DispatchOnMainThread(^{
		// It is tempting to call setLoadables:nil, but this can trigger 'did change' when we don't really want it.
		for (id<MMMLoadable> loadable in loadables) {
			[loadable removeObserver:observerProxy];
		}
	});
}

- (void)setLoadables:(NSArray *)loadables {

	MMM_CHECK_THREAD();

	for (id<MMMLoadable> loadable in _loadables) {
		[loadable removeObserver:_observerProxy];
	}

	_loadables = loadables;
	for (id<MMMLoadable> loadable in _loadables) {
		[loadable addObserver:_observerProxy];
	}

	[self updateState];
}

- (NSError *)error {

	MMM_CHECK_THREAD();

	// OK, let's use the error of the first failed object.
	for (id<MMMLoadable> l in _loadables) {
		if (l.loadableState == MMMLoadableStateDidFailToSync && l.error != nil) {
			return [NSError
				mmm_errorWithDomain:NSStringFromClass(self.class)
				message:[NSString stringWithFormat:@"Could not sync %@", l]
				underlyingError:l.error
			];
		}
	}

	return nil;
}

- (void)MMMPureLoadableGroup_loadableDidChange:(id<MMMPureLoadable>)loadable {
	MMM_CHECK_THREAD();
	[self updateState];
}

- (void)updateState {

	MMM_CHECK_THREAD();

	NSInteger failedCount = 0;
	NSInteger syncedCount = 0;
	NSInteger syncingCount = 0;
	for (id<MMMLoadable> loadable in _loadables) {
		switch (_mode) {
			case MMMLoadableGroupModeAll:
			case MMMLoadableGroupModeAny:
				if (loadable.loadableState == MMMLoadableStateDidFailToSync) {
					failedCount++;
				} else if (loadable.loadableState == MMMLoadableStateDidSyncSuccessfully) {
					syncedCount++;
				} else if (loadable.loadableState == MMMLoadableStateSyncing) {
					syncingCount++;
				}
				break;
								
			case MMMLoadableGroupModeDeprecated:
				if (loadable.loadableState == MMMLoadableStateDidFailToSync
					|| loadable.loadableState == MMMLoadableStateDidSyncSuccessfully
				) {
					syncedCount++;
				} else if (loadable.loadableState == MMMLoadableStateSyncing) {
					syncingCount++;
				}
				break;
		}
	}

	BOOL newContentsAvailable;
	if (_loadables.count == 0) {
		// Assuming no contents in case the group is empty. This way initializing the group with an empty array
		// (something we do for convenience before setting the actual array) won't lead to a 'did change' notification.
		newContentsAvailable = NO;
	} else {
		switch (_mode) {
			case MMMLoadableGroupModeAll:
			case MMMLoadableGroupModeDeprecated:
				// All should have contents available. (Yes, that was the rule in "never" mode as well.)
				newContentsAvailable = YES;
				for (id<MMMLoadable> loadable in _loadables) {
					if (![loadable isContentsAvailable]) {
						newContentsAvailable = NO;
						break;
					}
				}
				break;
			case MMMLoadableGroupModeAny:
				// At least one should have contents available.
				newContentsAvailable = NO;
				for (id<MMMLoadable> loadable in _loadables) {
					if ([loadable isContentsAvailable]) {
						newContentsAvailable = YES;
						break;
					}
				}
				break;
		}
	}
	
	MMMLoadableState newLoadableState;
	switch (_mode) {
		case MMMLoadableGroupModeAll:
		case MMMLoadableGroupModeDeprecated:
			if (failedCount > 0) {
				newLoadableState = MMMLoadableStateDidFailToSync;
			} else if (syncingCount > 0) {
				newLoadableState = MMMLoadableStateSyncing;
			} else if (syncedCount > 0 && syncedCount == _loadables.count) {
				newLoadableState = MMMLoadableStateDidSyncSuccessfully;
			} else {
				// Again, avoiding 'did sync' for empty groups, preferring 'idle'.
				// Same reason as for 'contentsAvailable' in the above.
				newLoadableState = MMMLoadableStateIdle;
			}
			break;
		case MMMLoadableGroupModeAny:
			if (syncingCount > 0) {
				newLoadableState = MMMLoadableStateSyncing;
			} else if (syncedCount > 0) {
				newLoadableState = MMMLoadableStateDidSyncSuccessfully;
			} else if (failedCount > 0 && failedCount == _loadables.count) {
				newLoadableState = MMMLoadableStateDidFailToSync;
			} else {
				newLoadableState = MMMLoadableStateIdle;
			}
			break;
	}

	if (
		// By our initial contract (which needs to be reviewed, see below) `contentsAvailable` changes only together
		// with `loadableState`, thus not looking for the change in `contentsAvailable` here.
		newLoadableState != _loadableState
		// In 'did sync successfully' we need to propagate change notifications, because they are also used when
		// the content properties (the value of the promise) change.
		|| newLoadableState == MMMLoadableStateDidSyncSuccessfully
		// It's convenient to be notified as soon as one of the objects gets something, the user then has more choice:
		// either grab what's available or wait for all objects to finish loading.
		|| (newLoadableState == MMMLoadableStateSyncing || newContentsAvailable != _contentsAvailable)
	) {
		_contentsAvailable = newContentsAvailable;
		_loadableState = newLoadableState;

		[self groupDidChange];

		[self notifyDidChange];
	}
}

- (void)addObserver:(id<MMMLoadableObserver>)observer {
	MMM_CHECK_THREAD();
	[_observerHub addObserver:observer];
}

- (void)removeObserver:(id<MMMLoadableObserver>)observer {
	MMM_CHECK_THREAD();
	[_observerHub removeObserver:observer];
}

- (void)groupDidChange {
	// This can be overridden in the subclasses of the group.
}

- (void)notifyDidChange {
	MMM_CHECK_THREAD();
	[_observerHub forEachObserver:^(id<MMMLoadableObserver> observer) {
		[observer loadableDidChange:self];
	}];
}

- (NSString *)description {
	MMM_CHECK_THREAD();
	return [NSString stringWithFormat:@"<%@: %@, contents available: %d>",
		self.class,
		NSStringFromMMMLoadableState(self.loadableState),
		self.contentsAvailable
	];
}

@end

//
//
//
@implementation MMMLoadableGroup

- (void)setLoadables:(NSArray<id<MMMLoadable>> *)loadables {

	[super setLoadables:loadables];

	for (id<MMMLoadable> loadable in self.loadables) {
		NSAssert(
			[loadable conformsToProtocol:@protocol(MMMPureLoadable)],
			@"All objects in %@ must conform at least to %@", self.class, @protocol(MMMLoadable)
		);
	}
}

- (BOOL)needsSync {

	MMM_CHECK_THREAD();

	for (id<MMMLoadable> loadable in self.loadables) {
		if ([loadable conformsToProtocol:@protocol(MMMLoadable)] && [loadable needsSync]) {
			return YES;
		}
	}

	return NO;
}

- (void)sync {
	MMM_CHECK_THREAD();
	for (id<MMMLoadable> loadable in self.loadables) {
		if ([loadable conformsToProtocol:@protocol(MMMLoadable)]) {
			[loadable sync];
		}
	}
}

- (void)syncIfNeeded {
	MMM_CHECK_THREAD();
	for (id<MMMLoadable> loadable in self.loadables) {
		if ([loadable conformsToProtocol:@protocol(MMMLoadable)]) {
			[loadable syncIfNeeded];
		}
	}
}

@end

//
//
//
@interface MMMPureLoadableProxy () <MMMLoadableObserver>
@end

@implementation MMMPureLoadableProxy {
	MMMLoadableObserver *_observer;
}

- (BOOL)isContentsAvailable {
	MMM_CHECK_THREAD();
	return _loadable ? _loadable.contentsAvailable : NO;
}

- (MMMLoadableState)loadableState {
	MMM_CHECK_THREAD();
	return _loadable ? _loadable.loadableState : super.loadableState;
}

- (NSError *)error {
	MMM_CHECK_THREAD();
	return _loadable ? _loadable.error : nil;
}

- (void)setLoadable:(id<MMMLoadable>)l {

	MMM_CHECK_THREAD();

	_loadable = l;
	_observer = [[MMMLoadableObserver alloc] initWithLoadable:l target:self selector:@selector(notifyDidChange)];

	// We need to reset our loadable state only when the proxied object is removed (not sure if it's the actual use case).
	// But resetting it also triggers a notification and that's what we need in any case.
	super.loadableState = MMMLoadableStateIdle;
}

- (void)proxyDidChange {}

- (void)notifyDidChange {
	MMM_CHECK_THREAD();
	[self proxyDidChange];
	[super notifyDidChange];
}

@end

//
// Note that I did not want to bother with inheritance from MMMPureLoadableProxy in this case.
//
@interface MMMLoadableProxy ()
@end

@implementation MMMLoadableProxy {
	MMMLoadableObserver *_observer;
}

- (BOOL)isContentsAvailable {
	MMM_CHECK_THREAD();
	return _loadable ? _loadable.contentsAvailable : NO;
}

- (MMMLoadableState)loadableState {
	MMM_CHECK_THREAD();
	return _loadable ? _loadable.loadableState : super.loadableState;
}

- (NSError *)error {
	MMM_CHECK_THREAD();
	return _loadable ? _loadable.error : nil;
}

- (void)setLoadable:(id<MMMLoadable>)l {

	MMM_CHECK_THREAD();

	_loadable = l;

	// If the user has asked as to sync before the actual object was set, then we need make the actual object syncing too.
	if (super.loadableState == MMMLoadableStateSyncing) {
		[self.loadable syncIfNeeded];
	}

	// And adding our observer after requesting sync, so we skip the first notification if any.
	_observer = [[MMMLoadableObserver alloc] initWithLoadable:l target:self selector:@selector(notifyDidChange)];

	// We need to reset our loadable state only when the proxied object is removed (not sure if it's the actual use case).
	// But resetting it also triggers a notification and that's what we need in any case.
	super.loadableState = MMMLoadableStateIdle;
}

- (void)proxyDidChange {}

- (void)notifyDidChange {
	MMM_CHECK_THREAD();
	[self proxyDidChange];
	[super notifyDidChange];
}

- (BOOL)needsSync {
	MMM_CHECK_THREAD();
	return self.loadable ? self.loadable.needsSync : YES;
}

- (void)sync {
	MMM_CHECK_THREAD();
	// We cannot use the logic of the base class here, i.e. ignore `sync` request when we are already `syncing`.
	// For example, if the proxied object is a group where one object is syncing already, but another is not (and thus
	// the whole group is `syncing`), then eating this request is going to prevent this other object from refreshing.
	//
	// Therefore we simply forward this to the proxied object, if any; or mark it as 'syncing' if nothing is set yet
	// (this way, we are going to sync the proxied object, if needed, once it's assigned).
	if (self.loadable) {
		[self.loadable sync];
	} else {
		self.loadableState = MMMLoadableStateSyncing;
	}
}

- (void)syncIfNeeded {
	MMM_CHECK_THREAD();
	// See the comment in sync, it's similar here.
	if (self.loadable) {
		[self.loadable syncIfNeeded];
	} else {
		self.loadableState = MMMLoadableStateSyncing;
	}
}

@end

//
//
//
@implementation MMMTestLoadable {
	MMMObserverHub<id<MMMLoadableObserver>> *_observerHub;
}

+ (MMMLoadableConcurrency)concurrency {
	return MMMLoadableConcurrencyMainThread;
}

@synthesize loadableState = _loadableState;

- (id)init {
	if (self = [super init]) {
		_observerHub = [[MMMObserverHub alloc] initWithObservable:self];
	}
	return self;
}

- (BOOL)needsSync {
	MMM_CHECK_THREAD();
	// Let's have the default implementation the same as in the base MMMLoadable.
	// TODO: should we allow to override this from the outside?
	return !self.contentsAvailable || (self.loadableState == MMMLoadableStateDidFailToSync) || (self.loadableState == MMMLoadableStateIdle);
}

- (void)syncIfNeeded {

	MMM_CHECK_THREAD();

	_syncIfNeededCounter++;

	if ([self needsSync]) {
		[self sync];
	}
}

- (void)doSync {
	// Don't have to do anything here, subclasses might override this.
}

- (void)sync {

	MMM_CHECK_THREAD();

	_syncCounter++;

	if (self.loadableState == MMMLoadableStateSyncing)
		return;

	[self setSyncing];

	[self doSync];
}

- (BOOL)isContentsAvailable {
	MMM_CHECK_THREAD();
	_isContentsAvailableCounter++;
	return _contentsAvailable;
}

- (void)resetAllCallCounters {
	MMM_CHECK_THREAD();
	_syncIfNeededCounter = 0;
	_syncCounter = 0;
	_isContentsAvailableCounter = 0;
}

- (void)setLoadableState:(MMMLoadableState)loadableState {
	MMM_CHECK_THREAD();
	_loadableState = loadableState;
	[self notifyDidChange];
}

- (void)setIdle {
	MMM_CHECK_THREAD();
	self.loadableState = MMMLoadableStateIdle;
}

- (void)setSyncing {
	MMM_CHECK_THREAD();
	self.loadableState = MMMLoadableStateSyncing;
}

- (void)setDidSyncSuccessfully {
	MMM_CHECK_THREAD();
	_contentsAvailable = YES;
	self.loadableState = MMMLoadableStateDidSyncSuccessfully;
}

- (void)setDidFailToSyncWithError:(NSError *)error {
	MMM_CHECK_THREAD();
	self.error = error;
	self.loadableState = MMMLoadableStateDidFailToSync;
}

#pragma mark -

- (BOOL)hasObservers {
	MMM_CHECK_THREAD();
	return !_observerHub.empty;
}

- (void)notifyDidChange {
	MMM_CHECK_THREAD();
	[_observerHub forEachObserver:^(id<MMMLoadableObserver> observer) {
		[observer loadableDidChange:self];
	}];
}

- (void)addObserver:(id<MMMLoadableObserver>)observer {
	MMM_CHECK_THREAD();
	_addObserverCounter++;
	[_observerHub addObserver:observer];
}

- (void)removeObserver:(id<MMMLoadableObserver>)observer {
	MMM_CHECK_THREAD();
	_removeObserverCounter--;
	[_observerHub removeObserver:observer];
}

@end
