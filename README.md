# MMMLoadable

[![Build](https://github.com/mediamonks/MMMLoadable/workflows/Build/badge.svg)](https://github.com/mediamonks/MMMLoadable/actions?query=workflow%3ABuild)
[![Test](https://github.com/mediamonks/MMMLoadable/workflows/Test/badge.svg)](https://github.com/mediamonks/MMMLoadable/actions?query=workflow%3ATest)

A simple promise-like model of async calculations.

(This is a part of `MMMTemple` suite of iOS libraries we use at [MediaMonks](https://www.mediamonks.com/).)

## Installation

Podfile:

```ruby
source 'https://github.com/mediamonks/MMMSpecs.git'
source 'https://github.com/CocoaPods/Specs.git'
...
pod 'MMMLoadable'
```

(Use 'MMMLoadable/ObjC' when Swift wrappers are not needed.)

SPM:

```swift
.package(url: "https://github.com/mediamonks/MMMLoadable", .upToNextMajor(from: "1.7.0"))
```

## Usage

**TL;DR:** It's an object that can be tracked, like a Promise, but keeps it's data available
to the consumer. So if a reload of the data fails, you can still show the old data.

This is yet another implementation of a "promise" pattern (aka "deferred", "future", etc).
Unlike the implementation in jQuery and similar, state transitions backwards (like from 'resolved'
to 'in progress') are allowed here and therefore the resolved value can be available no matter
the current state.

This is convenient to pair with view models when a typical pattern is to display a loading
indicator of some sort while the contents is being fetched and then to either display the
downloaded data or indicate an error with some means to retry the load (i.e. 'sync' the
loadable again). The contents, if available in a loadable, is not changed until the next
successful sync, which again fits the usual UI patterns where data is displayed even during
a refresh.

A loadable can be in 4 states:
 - `idle` Nothing is happening with the object now. It's been never synced or the result of the last sync is not known or important. (Promises — 'not ready'.)
 - `syncing` The object is being synced now (e.g. the contents are being downloaded or saved somewhere). (Promises — 'in-progress'.)
 - `didSyncSuccessfully` The object has been successfully synced and its contents (promises — value) are available now. (Promises — 'resolved'.) The name is a bit longer than just 'synced' here so it's easier to differentiate from 'syncing'.
 - `didFailToSync` The object has not been able to sync for some reason. (Promises — 'rejected'.)

## Example

One of the most straight-forward use cases for `MMMLoadable` is downloading something, let's
say a list of photos, from a REST API. You can use the pattern for any async (and even sync)
operation you can think of.

> 💡 If you're looking for a iOS 13+ `async` / `await` implementation, have a look at
> [MMMAsyncLoadable](https://github.com/mediamonks/MMMAsyncLoadable). This allows
> you to harness the power of `async` / `await` in Swift 5.5 whilst still providing
> the statefulness of a `MMMLoadable`.

### At the call site

```swift
// MARK: - Call site

private var photosLoadable: PhotosLoadable?
private var observer: MMMLoadableObserver?

func doWork() {

    let photos = PhotosLoadable()

    // Let's store the loadable for future reference.
    photosLoadable = photos

    // We can observe the loadable in multiple ways, one of the simplest
    // being to attach a `MMMLoadableObserver` via the `sink` call.
    //
    // You can add as many observers to a single loadable as you like.
    //
    // This returns an MMMLoadableObserver, it's critical to store this
    // somewhere, since the observer will stop listening for changes when
    // it's deallocated (in this scope that would be immediately).
    observer = photos.sink { [weak self] photosLoadable in
        switch photosLoadable.loadableState {
        case .idle:
            // The loadable hasn't started syncing yet.
            break
        case .syncing:
            // Probably should show a loading state of some sort,
            // for instance a 'full page' loader when `isContentsAvailable`
            // is `false` and a smaller loader when `true`, since
            // we have content to show in that case.

            if photosLoadable.isContentsAvailable {
                // Show a small loader since we have content.
                self?.view.showSmallLoader()
            } else {
                self?.view.showFullPageLoader()
            }
        case .didSyncSuccessfully:
            // All ready, `isContentsAvailable` should be `true` here. Use the
            // content of the loadable to populate your UI for instance.

            self?.view.hideLoaders()

        case .didFailToSync:
            // Oops, we can show the photosLoadable.error.
            if photosLoadable.isContentsAvailable {
                // Show a small error since we have content.
                self?.view.showSmallError(photosLoadable.error)
            } else {
                self?.view.showFullPageError(photosLoadable.error)
            }

            self?.view.hideLoaders()
        }

        // We always check if we have content, so we can populate no matter the state.
        if photosLoadable.isContentsAvailable, let content = photosLoadable.photos {
            self?.view.updatePhotos(content)
        }

        // Please note that we usually just have a single updateUI() call that
        // handles all these cases, and is safe to call as much as you want.
    }

    ...

    // This is similar to attaching a MMMLoadableObserver with an observer
    // block:
    observer2 = MMMLoadableObserver(loadable: photos) { [weak self] loadable in
        // The downside here is that the loadable is of
        // type `MMMPureLoadableProtocol`. This is usually no problem
        // if you store the loadable and use it in a different method
        // anyway. E.g. in a `updateUI` call.
        self?.updateUI()
    }

    ...

    // Or we can attach an observer by passing a target:
    observer3 = MMMLoadableObserver(loadable: photos, target: self, selector: #selector(updateUI))

    ...

    // Or we can attach ourself as an observer, in this case it's critical
    // that we remove the observer as well, usually inside a `deinit` call.
    photos.addObserver(self) // `self` should confirm to `MMMLoadableObserverProtocol`

    // Now we can actually start loading, we can do this in 2 ways,
    // either call `sync()` or call `syncIfNeeded()`. The latter will
    // only sync the loadable if `needsSync()` returns `true`, this method
    // can be overridden by your implementation, but by default it will only
    // need sync if no content is available, or the state is `idle` or
    // `didFailToSync`.
    //
    // The sync call also checks if we're not syncing already, so it's
    // safe to call many times in a row.
    //
    // This forces a sync, so it doesn't check `needsSync()`.
    // It will set the loadable from `idle` to `syncing` and reset the
    // error (if any), after this it will call the `doSync()` method inside
    // your implementation.
    photos.sync()

    // Alternatively, if we only want to make sure we have content to
    // display to the user, we can call:
    photos.syncIfNeeded()
    // This a shorthand for:
    if photos.needsSync() { photos.sync() }
}

```

### Implementation

```swift
public final class PhotosLoadable: MMMLoadable {

    // The `contents` property of this loadable.
    public private(set) var contents: [MyPhoto]?

    // The flag to determine if the content is available, in simple
    // cases it's usually just a nil check, but when loading data in
    // chunks or other cases where your 'content' can be non-nil, but
    // it's just not available yet.
    //
    // Note that unlike promises the contents can be available even
    // when the state says that the last sync has failed. (It can be the
    // value fetched on a previous sync or the one fetched initially
    // from a cache, etc; it might be not fresh perhaps, but still
    // be available to be displayed in the UI, for example).
    //
    // Note that if the state of the loadable is `didSyncSuccessfully`
    // then `isContentsAvailable` must be `true`, the reverse is not true.
    //
    // This property can change only together with `loadableState`.
    public override var isContentsAvailable: Bool { contents != nil }

    private let client: API.Client

    public init(client: API.Client) {

        self.client = client

        super.init()
    }

    private var clientRequest: API.Client.Request?

    // This is where you do your work. It get's called after a `sync()` call
    // so the loadableState here is (usually) `syncing`.
    public override func doSync() {

        // We don't call super.doSync() here since that will assert, since
        // it's required that this method is overriden.

        // Let's load some photos for instance, this is done in the API layer
        // so we get a response of Result<[API.Photo], APIError> here.

        clientRequest = client.loadPhotos { [weak self] result in

            guard let self = self else { return }

            switch result {
            case .success(let photos):
                // Nice, all good. We now got an array of API.Photo, our
                // own Photo class takes an API model, so let's populate
                // the content.

                self.contents = photos.map(MyPhoto.init)
                self.setDidSyncSuccessfully()
            case .failure(let error):
                // The request failed, let's forward this to our loadable.
                // Calling setFailedToSyncWithError will set the `loadableState`
                // to `didFailToSync` and it will populate the `error` property
                // of the loadable with the passed error.
                self.setFailedToSyncWithError(error)
            }
        }
    }

    public override func needsSync() -> Bool {
        // Here we can override if we need a sync, in most use cases the default
        // implementation is fine, but you can attach a custom condition.
        //
        // By default it will only need sync if no content is available, or the
        // state is `idle` or `didFailToSync`.
        //
        // For instance:
        return super.needsSync() && myCondition
    }
}
```

## Advanced

Aside from simple `MMMLoadable`s and observers there are a lot of classes
to help you with a variety of problems you might come across while dealing with
asynchronous operations.

### MMMPureLoadable & MMMPureLoadableProtocol

A class / protocol for a "read only" view on a loadable object which allows "the consumer"
of the loadable to observe the state but does not allow to sync the contents. It's similar
to the difference between "Promise" and "Deferred" in jQuery. `MMMLoadable` conforms to
`MMMPureLoadable`, so you can use it as access-control as well.

This can also be useful in cases where data comes in, but doesn't allow you to sync
it. Like with WebSockets / Firebase Firestore etc. In these cases you can call `setSyncing()`
to transform the state to `syncing`, if appropriate.

### MMMPureLoadableProxy & MMMLoadableProxy

Sometimes an API expects a promise but you don't have a reference to it until some time later,
i.e. you need a promise for a promise.

This proxy pretends its contents is unavailable and the state is idle until the actual promise
is set. After this all the properties are taken and the calls are forwarded from/to the actual
object. This can also be used to map a loadable to a different type of content.

You can inherit this and forward "contents" properties for your kind of loadable.

A good example of this is usage in a ViewModel:

```swift
// Inside your view you can listen to the ViewModel by attaching an observer, so you can
// show loaders etc. when the user hits the 'login' button.
public final class LoginViewModel: MMMLoadableProxy {

    public func login(username: String, password: String) {
        // When we set `self.loadable` the ViewModel (now also a Loadable) will
        // proxy all state changes.
        self.loadable = client.login(username: username, password: password)
    }

    public override func proxyDidChange() {
        // This get's called before the observers of the ViewModel are notified,
        // so we can some custom state as well, for example:
        if loadable.loadableState == .didFailToSync {
            self.errorMessage = "Some user-friendly error message"
        } else {
            self.errorMessage = nil
        }
    }
}
```

### MMMPureLoadableGroup & MMMLoadableGroup

Allows to treat several loadables as one.

Can be used standalone or subclassed (see `MMMLoadable+Subclasses.h` in this case.)

Its `loadableState` in case of a "strict" failure policy (default) is:

 - `didSyncSuccessfully`, when all the loadables in the group are synced successfully,
 - `didFailToSync`, when at least one of the loadables in the group has failed to sync;
 - `syncing`, when at least one of the loadables in the group is still syncing and none has failed yet.

The `loadableState` in case of a "never" failure policy is:

 - `syncing`, when at least one of the loadables in the group is still syncing;
 - `didSyncSuccessfully` otherwise.

Please note that using `never` as a failure policy is generally discouraged.

Regardless of the failure policy `isContentsAvailable` is `true` when it is `true` for all the
objects in the group.

The group only notifies the observers when the `loadableState` changes. If the `loadableState` is
already `didSyncSuccessfully` we notify the changes of each loadable in the group.

`MMMLoadableGroup` contains in addition to the behaviour of `MMMPureLoadableGroup`:

 - `needsSync` is `true`, if the same property is `true` for at least one object in the group;
 - `sync` and `syncIfNeeded` methods call the corresponding methods of every object in the group, as long as they support them (you can mix `MMMLoadable` and `MMMPureLoadable` in a `MMMLoadableGroup`).

### MMMLoadableImage (UIKit only)

`MMMLoadableImage` is a `MMMLoadable` that always contains the `image` property as contents.

`MMMNamedLoadableImage` Wrapper that loads an image from the app's bundle asynchronously
(accessible via the `+imageNamed:` method of UIImage).

`MMMImmediateLoadableImage` Wrapper for images that are immediately available.

`MMMPublicLoadableImage` Wrapper that loads an image that is publicly accessible via a
URL. This is very basic, using the shared instance of NSURLSession, so any caching will
happen there.

`MMMTestLoadableImage` This is used in unit tests when we want to manipulate the state
of a `MMMLoadableImage` to verify it produces the needed effects on the views being tested.

`MMMLoadableImageProxy` Sometimes an object implementing `MMMLoadableImage` is created much
later than when it would be convenient to have one.

A proxy can be used in this case, so the users still have a reference to `MMMLoadableImage`
and can begin observing it or request a sync asap. Later when the actual reference is finally
available it is supplied to the proxy which begins mirroring its state.

As always, this is meant to be used only in the implementation, with only `MMMLoadableImage`
visible publicly.

### MMMLoadableSyncer

Syncs a loadable periodically using backoff timeouts in case of failures.

Note that it holds a weak reference to the target loadable, which makes it easier to compose
it into the implementation of the loadable if needed.

Also note, that when a non-zero period is used, then an extra sync is performed every
time the app enters foreground.

Have a look at the doc-blocks for `MMMLoadableSyncer` and `MMMTimeoutPolicy` for more info.

### MMMAutosyncLoadable (UIKit only)

> We advise to use a `MMMLoadableSyncer` instead of letting the loadable itself
> re-sync.

A `MMMLoadable` with simple autorefresh logic. Override the `autosyncInterval` to determine
how often autorefresh for the object should be triggered while the app is active. You
can specify a separate interval to determine how often the loadable should refresh while
your App is in the background using `autosyncIntervalWhileInBackground`, return 0 or a
negative value to disable syncing while in background.

### MMMLoadableWaiter

Allows for multiple parties to wait for a loadable to have its contents available or
synced successfully.

This is made for scenarios when a loadable has something that other objects might want
to grab if it's available immediately but don't mind to wait a bit while it's not there
yet. For example (and initial use case as well), the target loadable might be refreshing
an access token while multiple API calls need to grab a fresh one just before they can
proceed.

The user code calls `wait()` and then is notified via a completion block about the target
loadable reaching the corresponding condition or the timeout expiring.

### MMMSimpleLoadableWaiter

Waits for the given loadable to be done with syncing before passing control to your
completion handler.

This is a more lightweight version of `MMMLoadableWaiter` that does not support timeouts,
multiple pending requests, or re-syncing the target in case of failures.

Use it when you want to try syncing another loadable before you can proceed, but you are
one of a few of its users and fully trust this loadable on the timeouts and handling of
any possible retries. This is often the case when the implementation of a loadable depends
both on other loadables and something extra for which `MMMLoadableProxy` would not work well.

### MMMTestLoadable

Can be used as a base for unit test (view) models conforming to MMMLoadable. It allows
you to override properties of a loadable from the outside (i.e. from a unit test).

## Ready for liftoff? 🚀

We're always looking for talent. Join one of the fastest-growing rocket ships in
the business. Head over to our [careers page](https://media.monks.com/careers)
for more info!
