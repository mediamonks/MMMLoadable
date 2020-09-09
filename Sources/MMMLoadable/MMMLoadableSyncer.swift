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

	private let timeoutPolicy: TimeoutPolicy

	/// Designated initializer allowing to customize the timeout policy, something that can be useful at least for testing.
	public init(loadable: MMMLoadableProtocol, timeoutPolicy: TimeoutPolicy) {
		self.loadable = loadable
		self.timeoutPolicy = timeoutPolicy
		self.loadableObserver = MMMLoadableObserver(loadable: loadable) { [weak self] _ in
			self?.reschedule()
		}
		reschedule()
	}

	deinit {
    	cancelTimer()
	}

	/// Convenience for syncing a loadable at regular intervals using a simple back off policy in case of failures.
	public convenience init(
		loadable: MMMLoadableProtocol,
		period: TimeInterval,
		backoff: (min: TimeInterval, max: TimeInterval, multiplier: Double)
	) {
		self.init(
			loadable: loadable,
			timeoutPolicy: BackoffTimeoutPolicy(
				period: period,
				min: backoff.min,
				max: backoff.max,
				multiplier: backoff.multiplier
			)
		)
	}

	private var timer: Timer?

	private func cancelTimer() {
		timer?.invalidate()
		timer = nil
	}

	private func setTimer(timeout: TimeInterval) {

		let t = max(timeout, 0.1)
		timer?.invalidate()
		timer = Timer.scheduledTimer(withTimeInterval: t, repeats: false) { [weak self] _ in
			self?.sync()
		}

		guard let loadable = loadable else { preconditionFailure() }
		MMMLogTrace(self, "Going to sync \(MMMLogContext(fromObject: loadable)) in \(t)s")
	}

	private func sync() {
		cancelTimer()
		// TODO: Might be useful to do syncIfNeeded() in some cases. Make configurable?
		loadable?.sync()
	}

	private func reschedule() {

		guard let loadable = loadable else {
			// It's weak by design, so might be gone and then we just stop refreshing it.
			return
		}

		switch loadable.loadableState {
		case .idle:
			// TODO: it might be benefitial in some cases to wait for someone else to drive the first sync. Make configurable?
			setTimer(timeout: timeoutPolicy.nextTimeout(afterFailure: false))
		case .syncing:
			// Let's wait for sync to complete. Should cancel our timer if we had one.
			cancelTimer()
		case .didFailToSync:
			setTimer(timeout: timeoutPolicy.nextTimeout(afterFailure: true))
		case .didSyncSuccessfully:
			setTimer(timeout: timeoutPolicy.nextTimeout(afterFailure: false))
		}
	}
}

/// Tells when to try doing something next time depending on the outcome of the previous attempt (succeeded/failed)
/// and possibly external factors.
public protocol TimeoutPolicy: AnyObject {
	func nextTimeout(afterFailure: Bool) -> TimeInterval
}

/// A timeout policy that is using a constant period after successful attempts and a set of incrementing timeouts
/// after failures.
public final class BackoffTimeoutPolicy: TimeoutPolicy {

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
