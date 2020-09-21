//
// MMMLoadable. Part of MMMTemple.
// Copyright (C) 2016-2020 MediaMonks. All rights reserved.
//

import Foundation
import MMMLog

/// Syncs a loadable periodically using backoff timeouts in case of failures.
///
/// Note that it holds a weak reference to the target loadable, which makes it easier to compose it into
/// the implementation of the loadable if needed.
public final class MMMLoadableSyncer {

	private weak var loadable: MMMLoadableProtocol?
	private var loadableObserver: MMMLoadableObserver?
	private let timeoutPolicy: MMMTimeoutPolicy

	/// Should the sync be triggered in any case ("hard" sync by calling `sync`) or only wnen needed (`syncIfNeeded`).
	public enum SyncPolicy {
		case sync
		case syncIfNeeded
	}
	private let syncPolicy: SyncPolicy

	/// Designated initializer allowing to customize the timeout policy, something that can be useful at least for testing.
	public init(loadable: MMMLoadableProtocol, syncPolicy: SyncPolicy = .sync, timeoutPolicy: MMMTimeoutPolicy) {
		self.loadable = loadable
		self.syncPolicy = syncPolicy
		self.timeoutPolicy = timeoutPolicy
		self.loadableObserver = MMMLoadableObserver(loadable: loadable) { [weak self] _ in
			self?.reschedule()
		}
		reschedule()
	}

	/// Describes how often to retry syncing the target after a failure and how this timeout should grow after each attempt.
	public typealias BackoffSettings = (min: TimeInterval, max: TimeInterval, multiplier: Double)

	/// Sets up to sync a loadable at regular intervals using a simple back off policy in case of failures.
	///
	/// - Parameter period: How often to sync the target after it has been synced successfully. 0 to disable.
	/// - Parameter backoff: Describes how often to retry syncing the target after a failure and how this timeout
	///   should grow after each attempt.
	public convenience init(
		loadable: MMMLoadableProtocol,
		syncPolicy: SyncPolicy = .sync,
		period: TimeInterval,
		backoff: BackoffSettings
	) {
		self.init(
			loadable: loadable,
			syncPolicy: syncPolicy,
			timeoutPolicy: MMMBackoffTimeoutPolicy(
				period: period,
				min: backoff.min,
				max: backoff.max,
				multiplier: backoff.multiplier
			)
		)
	}

	deinit {
    	cancelTimer()
	}

	private var timer: Timer?

	private func cancelTimer() {
		timer?.invalidate()
		timer = nil
	}

	private func setTimer(timeout: TimeInterval) {

		let t = max(timeout, 0)
		timer?.invalidate()
		timer = Timer.scheduledTimer(withTimeInterval: t, repeats: false) { [weak self] _ in
			self?.sync()
		}

		guard let loadable = loadable else { preconditionFailure() }
		MMMLogTrace(loadable, "Going to sync in \(String(format: "%.1f", t))s")
	}

	private func sync() {

		cancelTimer()

		// The target can be gone anytime by design.
		guard let loadable = loadable else { return }

		switch syncPolicy {
		case .sync:
			loadable.sync()
		case .syncIfNeeded:
			loadable.syncIfNeeded()
			if loadable.loadableState == .didSyncSuccessfully {
				// Looks like no sync was required, so most likely no state change occurred and triggered `reschedule()`.
				reschedule()
			}
		}
	}

	private func reschedule() {

		// The target can be gone anytime by design.
		guard let loadable = loadable else { return }

		switch loadable.loadableState {
		case .idle:
			// Assuming that the initial sync needs to be driven by somebody else.
			cancelTimer()
		case .syncing:
			// Let's wait for sync to complete. Should cancel our timer if we had one.
			cancelTimer()
		case .didFailToSync:
			setTimer(timeout: timeoutPolicy.nextTimeout(afterFailure: true))
		case .didSyncSuccessfully:
			let timeout = timeoutPolicy.nextTimeout(afterFailure: false)
			if timeout > 0 {
				setTimer(timeout: timeout)
			} else {
				// Treating 0 as "no sync after success required".
			}
		}
	}
}

/// Tells when to try doing something next time depending on the outcome of the previous attempt (succeeded/failed)
/// and possibly external factors.
public protocol MMMTimeoutPolicy: AnyObject {
	/// A 0 after a success is treated as "no action required".
	func nextTimeout(afterFailure: Bool) -> TimeInterval
}

/// A timeout policy that is using a constant period after successful attempts and a set of incrementing timeouts
/// after failures.
public final class MMMBackoffTimeoutPolicy: MMMTimeoutPolicy {

	private let period: TimeInterval
	private let min: TimeInterval
	private let max: TimeInterval
	private let multiplier: Double

	public init(period: TimeInterval, min: TimeInterval, max: TimeInterval, multiplier: Double) {

		assert(period >= 0)
		assert(0 <= min && min <= max)
		assert(multiplier >= 1)

		self.period = period
		self.min = min
		self.max = max
		self.multiplier = multiplier

		reset()
	}

	private var upperBound: TimeInterval = 0

	private func reset() {
		upperBound = min
	}

	public func nextTimeout(afterFailure: Bool) -> TimeInterval {
		if afterFailure {
			// Could be `TimeInterval.random(in: min...upperBound)`, but being deterministic makes it easier to test.
			let next = upperBound
			upperBound = Swift.min(upperBound * multiplier, max)
			return next
		} else {
			reset()
			return period
		}
	}
}
