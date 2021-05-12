//
// MMMLoadable. Part of MMMTemple.
// Copyright (C) 2016-2020 MediaMonks. All rights reserved.
//

import Foundation
import MMMCommonCore
import MMMObservables

#if SWIFT_PACKAGE
import MMMLoadableObjC
#endif

/// Allows for multiple parties to wait for a loadable to have its contents available or synced successfully.
///
/// This is made for scenarios when a loadable has something that other objects might want to grab if it's available
/// immediately but don't mind to wait a bit while it's not there yet. For example (and initial use case as well),
/// the target loadable might be refreshing an access token while multiple API calls need to grab a fresh one just
/// before they can proceed.
///
/// The user code calls `wait()` and then is notified via a completion block about the target loadable reaching
/// the corresponding condition or the timeout expiring.
public final class MMMLoadableWaiter {

	private let loadable: MMMPureLoadableProtocol

	/// Possible conditions to wait for on the target loadable.
	public enum Condition {
		case isContentsAvailable
		case didSyncSuccessfully
	}

	private let condition: Condition

	private let timeout: TimeInterval
	private var observer: MMMLoadableObserver?
	private let queue: DispatchQueue
	private let timeSource: MMMTimeSource

	private var syncCount: Int = 0

	/// - Parameter shouldSyncIfPossible: When `true`, then the target loadable will be synced while somebody is waiting
	///   (provided allows syncing as well, i.e. supports `MMMLoadableProtocol`).
	public init(
		loadable: MMMPureLoadableProtocol,
		condition: Condition,
		timeout: TimeInterval,
		shouldSyncIfPossible: Bool,
		queue: DispatchQueue? = nil,
		timeSource: MMMTimeSource? = nil
	) {
		self.loadable = loadable
		self.condition = condition
		self.timeout = timeout
		self.queue = queue ?? DispatchQueue.main
		self.timeSource = timeSource ?? MMMDefaultTimeSource()

		self.observer = MMMLoadableObserver(loadable: loadable) { [weak self] _ in
			guard let self = self else { return }
			// Attempts are counted every time it transitions via "syncing".
			if self.loadable.loadableState == .syncing {
				// Increments are atomic, but "read and zero out" would not be.
				self.queue.async { self.syncCount += 1 }
			}
			self.callback.schedule()
		}
	}

	deinit {
    	cancelTimer()
	}

	private lazy var callback = CoalescingCallback(queue: self.queue) { [weak self] in
		self?.update()
	}

	public typealias Completion = (Result<MMMPureLoadableProtocol, Error>) -> Void

	public func wait(_ completion: @escaping Completion) {
		let r = WaitRequest(completion: completion, expiresAt: timeSource.now.addingTimeInterval(timeout))
		queue.async { [weak self] in
			guard let self = self else { return }
			self.requests.append(r)
			self.update()
		}
	}

	private func hasReachedCondition() -> Bool {
		switch condition {
		case .isContentsAvailable:
			return loadable.isContentsAvailable
		case .didSyncSuccessfully:
			return loadable.loadableState == .didSyncSuccessfully
		}
	}

	private var timer: Timer?

	private func setUpTimer(_ timeInterval: TimeInterval) {
		let t = timeSource.realTimeIntervalFrom(max(timeInterval, 0))
		timer?.invalidate()
		timer = Timer.scheduledTimer(withTimeInterval: t, repeats: false) { [weak self] _ in
			self?.queue.async {
				self?.update()
			}
		}
	}

	private func cancelTimer() {
		timer?.invalidate()
		timer = nil
	}

	// Trying to refresh the target while there is at least somebody waiting.
	public var syncer: MMMLoadableSyncer?

	private func cleanUpAfterAllRequestsAreGone() {
		// Let's don't try to refresh when nobody is interested anyway.
		self.syncer = nil
	}

	private func update() {

		cancelTimer()

		guard !requests.isEmpty else {
			// Nobody needs anything yet, nothing to do.
			return
		}

		guard !hasReachedCondition() else {

			// Alright, all pending requests are done.
			let toComplete = requests
			requests.removeAll()
			toComplete.forEach { $0.completion(.success(loadable)) }

			cleanUpAfterAllRequestsAreGone()

			return
		}

		// Make sure there is somebody driving refreshes in case the target is failing.
		if self.syncer == nil, let loadable = self.loadable as? MMMLoadableProtocol {
			// This is going to try refreshing us in case of failures only.
			self.syncer = MMMLoadableSyncer(
				loadable: loadable,
				syncPolicy: .syncIfNeeded,
				period: 0,
				backoff: (min: 1, max: timeout / 2, multiplier: 2.squareRoot())
			)
			// Needs an initial kick.
			loadable.syncIfNeeded()
		}

		// Not yet, let's remove the expired ones.

		let syncCount = self.syncCount
		self.syncCount = 0
		for r in requests {
			r.retryCount += syncCount
		}

		let now = timeSource.now
		var toExpire: [WaitRequest] = []
		var valid: [WaitRequest] = []
		for r in requests {
			if now < r.expiresAt {
				valid.append(r)
			} else {
				toExpire.append(r)
			}
		}

		self.requests = valid
		toExpire.forEach {
			$0.completion(.failure(MMMLoadableWaiterError.timedOut))
		}

		var updateIn: TimeInterval?
		for r in requests {
			let left = r.expiresAt.timeIntervalSince(now)
			updateIn = min(left, updateIn ?? left)
		}
		if let updateIn = updateIn {
			setUpTimer(updateIn)
		} else {
			cleanUpAfterAllRequestsAreGone()
		}
	}

	private var requests: [WaitRequest] = []

	private class WaitRequest {

		public let completion: Completion
		public let expiresAt: Date
		public var retryCount: Int = 0

		public init(completion: @escaping Completion, expiresAt: Date) {
			self.completion = completion
			self.expiresAt = expiresAt
		}
	}
}

public enum MMMLoadableWaiterError: Error {

	case timedOut

	/// NSError compatibility.
	public var _userInfo: AnyObject? {
		return NSDictionary(dictionary: [
			NSLocalizedDescriptionKey: message
		])
	}

	public var message: String {
		switch self {
		case .timedOut:
			return "Timed out"
		}
	}
}
