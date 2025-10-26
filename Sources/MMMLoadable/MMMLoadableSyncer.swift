//
// MMMLoadable. Part of MMMTemple.
// Copyright (C) 2016-2020 MediaMonks. All rights reserved.
//

import MMMCommonCore
import MMMLog

#if os(iOS)
import UIKit // For UIApplication.
#endif

#if SWIFT_PACKAGE
import MMMLoadableObjC
#endif

/// Syncs a loadable periodically using backoff timeouts in case of failures.
///
/// Note that it holds a weak reference to the target loadable, which makes it easier to compose it into
/// the implementation of the loadable if needed.
///
/// Also note, that when a non-zero period is used, then an extra sync is performed everytime the app enters
/// foreground.
public final class MMMLoadableSyncer {

	private weak var loadable: MMMLoadableProtocol?
	private var loadableObserver: MMMLoadableObserver?
	private let timeoutPolicy: MMMTimeoutPolicy

	/// Should the sync be triggered in any case ("hard" sync by calling `sync`)
	/// or only when needed (`syncIfNeeded`).
	public enum SyncPolicy {
		case sync
		case syncIfNeeded
	}
	private let syncPolicy: SyncPolicy

	private let timeSource: MMMTimeSource

	private var didBecomeActiveObserver: NSObjectProtocol?

	/// Designated initializer allowing to customize the timeout policy, something that can be useful at least for testing.
	public init(
		loadable: MMMLoadableProtocol,
		syncPolicy: SyncPolicy = .sync,
		timeoutPolicy: MMMTimeoutPolicy,
		timeSource: MMMTimeSource? = nil
	) {

		self.loadable = loadable
		self.syncPolicy = syncPolicy
		self.timeoutPolicy = timeoutPolicy
		self.timeSource = timeSource ?? MMMDefaultTimeSource()

		self.loadableObserver = MMMLoadableObserver(loadable: loadable) { [weak self] _ in
			self?.reschedule()
		}

		#if os(iOS)
		self.didBecomeActiveObserver = NotificationCenter.default.addObserver(
			forName: UIApplication.didBecomeActiveNotification,
			object: nil,
			queue: .main
		) { [weak self] _ in
			self?.reschedule(afterAppBecameActive: true)
		}
		#endif

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
		backoff: BackoffSettings,
		timeSource: MMMTimeSource? = nil
	) {
		self.init(
			loadable: loadable,
			syncPolicy: syncPolicy,
			timeoutPolicy: MMMBackoffTimeoutPolicy(
				period: period,
				min: backoff.min,
				max: backoff.max,
				multiplier: backoff.multiplier
			),
			timeSource: timeSource
		)
	}

	deinit {
    	cancelTimer()
		didBecomeActiveObserver.map { NotificationCenter.default.removeObserver($0) }
	}

	private var timer: Timer?

	private func cancelTimer() {
		timer?.invalidate()
		timer = nil
	}

	private func setTimer(timeout: TimeInterval) {

		let t = max(timeout, 0)
		timer?.invalidate()
		timer = Timer.scheduledTimer(
			withTimeInterval: timeSource.realTimeIntervalFrom(timeout),
			repeats: false
		) { [weak self] _ in
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

	private func reschedule(afterAppBecameActive: Bool = false) {

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
			// Let's stir the backoff timer when the app becomes active to recover after the failure faster.
			if afterAppBecameActive {
				timeoutPolicy.reset()
			}
			setTimer(timeout: timeoutPolicy.nextTimeout(afterFailure: true))
		case .didSyncSuccessfully:
			let timeout = timeoutPolicy.nextTimeout(afterFailure: false)
			if timeout > 0 {
				// We want to re-sync things after the app becomes active with the minimum timeout
				// like after a failure, unless it's not allowed to re-sync.
				// TODO: make this more explicit in the timeout policy
				if afterAppBecameActive {
					timeoutPolicy.reset()
					setTimer(timeout: timeoutPolicy.nextTimeout(afterFailure: true))
				} else {
					setTimer(timeout: timeout)
				}
			} else {
				// Treating 0 period as "no sync after success required".
			}
		}
	}
}

/// Tells when to try doing something next time depending on the outcome of the previous attempt (succeeded/failed)
/// and possibly external factors.
public protocol MMMTimeoutPolicy: AnyObject {

	/// A 0 after a success is treated as "no action required".
	func nextTimeout(afterFailure: Bool) -> TimeInterval

	func reset()
}

/// A timeout policy that is using a constant period after successful attempts and a set of incrementing timeouts
/// after failures.
public final class MMMBackoffTimeoutPolicy: MMMTimeoutPolicy {

	private let min: TimeInterval
	private let max: TimeInterval
	private let multiplier: Double

	public init(
		period: TimeInterval = 0,
		min: TimeInterval,
		max: TimeInterval,
		multiplier: Double = 2.0.squareRoot()
	) {

		assert(period >= 0)
		// Note that we cannot allow zero for min as we won't be able to increase it then.
		assert(0 < min && min <= max)
		assert(multiplier >= 1)

		self.period = period
		self.min = min
		self.max = max
		self.multiplier = multiplier

		reset()
	}

	private var upperBound: TimeInterval = 0

	public func reset() {
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

	/// How often to sync after a success. Set to 0 to disable.
	///
	/// You can change this but note that it will be used only on the next change in the state of the loadable,
	/// because there is no feedback between the policy and the syncer.
	public var period: TimeInterval
}
