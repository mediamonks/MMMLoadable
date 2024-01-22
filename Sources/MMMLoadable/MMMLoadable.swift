//
// MMMLoadable. Part of MMMTemple.
// Copyright (C) 2016-2023 MediaMonks. All rights reserved.
//

import Foundation
import MMMCommonCore

#if SWIFT_PACKAGE
@_exported import MMMLoadableObjC
#endif

extension MMMLoadableState: CustomStringConvertible {
	public var description: String { NSStringFromMMMLoadableState(self) }
}

extension MMMPureLoadableProtocol {
    
    /// Observe changes in this loadable. Will stop listening to changes when
    /// ``MMMLoadableObserver/remove()`` is called or the observer deallocates.
    /// 
    /// - Parameter block: Get's called every time the loadable changes.
    /// - Returns: The observer, you usually want to store this outside of the scope, e.g.
    ///            in a private property so it doesn't deallocate right away.
    public func sink(_ block: @escaping (Self) -> Void) -> MMMLoadableObserver? {
        return MMMLoadableObserver(loadable: self) { [weak self] _ in
            guard let self = self else {
                assertionFailure("\(MMMTypeName(Self.self)) was lost inside the observer callback?")
                return
            }
            block(self)
        }
    }

	/// Waits for the receiver to stop syncing and continues if `isContentsAvailable`; throws otherwise.
	public func doneSyncing() async throws {
		try await contentsAfterDoneSyncing { _ in }
	}

	/// Waits for the receiver to stop syncing; then, if `isContentsAvailable`, returns the result of the given closure;
	/// throws otherwise.
	public func contentsAfterDoneSyncing<T>(_ grabContents: @escaping (Self) throws -> T) async throws -> T {
		try await withCheckedThrowingContinuation { continuation in
			DispatchQueue.main.async {
				var waiter: MMMSimpleLoadableWaiter?
				waiter = MMMSimpleLoadableWaiter.whenDoneSyncing(self) {
					do {
						if self.isContentsAvailable {
							continuation.resume(returning: try grabContents(self))
						} else {
							throw self.error ?? NSError(domain: self, message: "Unspecified error")
						}
					} catch {
						continuation.resume(throwing: error)
					}
					// We need to keep the waiter around while waiting.
					_ = waiter
				}
			}
		}
	}
}

/// Forwards all calls in `MMMPureLoadableProtocol` to another object.
/// ("Type-erases" objects conforming `MMMPureLoadableProtocol`, if you want to be fancy.)
///
/// This is used as a base for public models where we want to hide internal methods that, although being public
/// technically, are only meant to be called internally, mostly by the superclass (e.g. `doSync`).
///
/// The actual implementation can inherit from all those base classes with exposed overridable methods but then it
/// is embedded into another wrapper that uses this "box" as its base to forward only the calls of public protocols.
open class AnyPureLoadable: NSObject, MMMPureLoadableProtocol {

	private let object: MMMPureLoadableProtocol
	
	public init(_ original: MMMPureLoadableProtocol) {
		self.object = original
	}

	public var loadableState: MMMLoadableState { object.loadableState }
	public var error: Error? { object.error }
	public var isContentsAvailable: Bool { object.isContentsAvailable }
	public func addObserver(_ observer: MMMLoadableObserverProtocol) { object.addObserver(observer) }
	public func removeObserver(_ observer: MMMLoadableObserverProtocol) { object.removeObserver(observer) }
}

/// Forwards all calls in `MMMLoadableProtocol` to another object.
/// ("Type-erases" objects conforming `MMMLoadableProtocol`, if you want to be fancy.)
///
/// See `AnyPureLoadable`.
open class AnyLoadable: NSObject, MMMLoadableProtocol {

	private let object: MMMLoadableProtocol
	
	public init(_ original: MMMLoadableProtocol) {
		self.object = original
	}

	// Don't want to inherit from the "pure" version of this helper to simplify the hierarchy.
	
	public var loadableState: MMMLoadableState { object.loadableState }
	public var error: Error? { object.error }
	public var isContentsAvailable: Bool { object.isContentsAvailable }
	public func addObserver(_ observer: MMMLoadableObserverProtocol) { object.addObserver(observer) }
	public func removeObserver(_ observer: MMMLoadableObserverProtocol) { object.removeObserver(observer) }

	public func sync() { object.sync() }
	public var needsSync: Bool { object.needsSync }
	public func syncIfNeeded() { object.syncIfNeeded() }
}
