//
// MMMLoadable. Part of MMMTemple.
// Copyright (C) 2023 MediaMonks. All rights reserved.
//

import Foundation

/// Helps to sync a bunch of loadables one-by-one, allowing to optionally set up each next loadable based on the data
/// available in the previously synced ones. (Compare to ``MMMLoadableGroup`` syncing its elements in parallel.)
///
/// Objects in the chain are synced (via `syncIfNeeded()`) one by one starting from the first one.
/// Only the "current" object is observed at a time until it's not syncing anymore.
///
/// - When the current object is done syncing but **has no contents**, then the chain stops with an error
/// (i.e. chain's own `loadableState` becomes `.didFailToSync` and `isContentsAvailable` is `false`.).
///
/// - When the current object is done syncing and **does have contents**, then (depending on the value returned
/// by the associated callback) the chain can either:
///   - stop without trying to sync the remaining objects (either with an error or successfully);
///   - or proceed to the next object, if any.
///
/// Once all objects are successfully synced the chain itself becomes synced successfully, i.e. its `loadableState`
/// becomes `.didSyncSuccessfully` and `isContentsAvailable` transitions to `true`.
public final class MMMLoadableChain: MMMLoadable {

	private let chain: [Item]

	public init(_ chain: [Item]) {
		self.chain = chain
	}

	public convenience init(_ chain: Item...) {
		self.init(chain)
	}

	public convenience init(_ chain: [MMMLoadableProtocol]) {
		self.init(chain.map { Item($0) })
	}

	public struct Item {

		fileprivate var loadable: any MMMLoadableProtocol
		fileprivate var whenContentsAvailable: (() -> NextAction)?

		/// - Parameters:
		///   - whenContentsAvailable: An optional callback invoked after the `loadable` is done syncing
		///     and has contents available. The callback can, for example, prepare the next objects in the chain
		///     or interrupt syncing of the whole chain if there is enough information already let say.
		public init(
			_ loadable: any MMMLoadableProtocol,
			whenContentsAvailable: (() -> NextAction)? = nil
		) {
			self.loadable = loadable
			self.whenContentsAvailable = whenContentsAvailable
		}
	}

	/// The value returned by a callback that can be optionally associated with each of the loadables in the chain.
	/// The value controls the behavior of the chain after the corresponding object is **successfully** synced.
	public enum NextAction {
		/// The chain should proceed syncing the remaining objects, if any.
		/// This is the default used in case an object in the chain has no associated callback.
		case proceed
		/// The chain should fail with the given error without trying to sync the remaining objects, if any.
		case fail(Error)
		/// The chain should stop successfully without trying to sync the remaining objects, if any.
		case completeSuccessfully
	}

	public override func needsSync() -> Bool {
		chain.contains { $0.loadable.needsSync }
	}

	public override var isContentsAvailable: Bool {
		loadableState == .didSyncSuccessfully
	}

	public override func doSync() {
		currentIndex = chain.startIndex
		syncNextLater()
	}

	private var currentIndex: Int = 0
	private var waiter: MMMSimpleLoadableWaiter?

	private func syncNextLater() {
		DispatchQueue.main.async { [weak self] in
			self?.syncNext()
		}
	}

	private func syncNext() {

		let item = chain[currentIndex]

		let loadable = item.loadable
		loadable.syncIfNeeded()
		waiter = .whenDoneSyncing(loadable) { [weak self, weak loadable] in

			guard let self, let loadable else { return }
			self.waiter = nil

			if loadable.isContentsAvailable {
				switch item.whenContentsAvailable?() ?? .proceed {
				case .completeSuccessfully:
					self.setDidSyncSuccessfully()
				case .fail(let error):
					self.setFailedToSyncWithError(error)
				case .proceed:
					self.currentIndex += 1
					if self.currentIndex < self.chain.endIndex {
						self.syncNextLater()
					} else {
						self.setDidSyncSuccessfully()
					}
				}
			} else {
				self.setFailedToSyncWithError(NSError(
					domain: self,
					message: "Could not sync element #\(self.currentIndex)",
					underlyingError: loadable.error
				))
			}
		}
	}
}
