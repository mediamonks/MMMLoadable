//
// MMMLoadable. Part of MMMTemple.
// Copyright (C) 2016-2020 MediaMonks. All rights reserved.
//

import Foundation

#if SWIFT_PACKAGE
import MMMLoadableObjC
#endif

/// Waits for the given loadable to be done with syncing before passing control to your completion handler.
///
/// This is a more lightweight version of `MMMLoadableWaiter` that does not support timeouts, multiple pending
/// requests, or re-syncing the target in case of failures.
///
/// Use it when you want to try syncing another loadable before you can proceed, but you are one of a few
/// of its users and fully trust this loadable on the timeouts and handling of any possible retries.
/// This is often the case when the implementation of a loadable depends both on other loadables
/// and something extra for which `MMMLoadableProxy` would not work well.
public final class MMMSimpleLoadableWaiter {

	/// Calls the completion handler only once when the given loadable is not syncing anymore.
	///
	/// The user code is responsible for causing the target to begin syncing.
	///
	/// Important: keep the returned value while waiting for the callback.
	public static func whenDoneSyncing(
		_ loadable: MMMPureLoadableProtocol,
		_ completion: @escaping () -> Void
	) -> MMMSimpleLoadableWaiter {
		Self.init(
			loadable: loadable,
			predicate: { $0.loadableState != .syncing },
			completion: completion
		)
	}

	private var loadable: MMMPureLoadableProtocol?
	private var observer: MMMLoadableObserver?
	private var predicate: ((MMMPureLoadableProtocol) -> Bool)?
	private var callback: (() -> Void)?

	private init(
		loadable: MMMPureLoadableProtocol,
		predicate: @escaping (MMMPureLoadableProtocol) -> Bool,
		completion: @escaping () -> Void
	) {
		self.loadable = loadable
		self.predicate = predicate
		self.callback = completion

		self.observer = MMMLoadableObserver(loadable: loadable) { [weak self] _ in
			self?.check()
		}
		// Let's defer our check just in case, so the caller can at least store the reference to us.
		DispatchQueue.main.async { [weak self] in
			self?.check()
		}
	}

	/// Explicitly cancels waiting as if the receiver was deallocated. Safe to call multiple times.
	public func cancel() {
		loadable = nil
		observer = nil
		callback = nil
		predicate = nil
	}

	private func check() {

		// Done with this whole waiting already but received a delayed callback or our own call from init()?
		guard let loadable = loadable, let predicate = predicate else { return }

		// Waiting for the target to settle even if its contents is available by now.
		guard predicate(loadable) else { return }

		// OK, our mission is done regardless of the outcome (which is something for the user code to analyze).
		let callback = self.callback
		self.cancel()
		callback?()
	}
}
