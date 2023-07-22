//
// Starbucks App.
// Copyright (c) 2023 MediaMonks. All rights reserved.
// 

import MMMLoadable
import XCTest

public final class MMMLoadableChainTestCase: XCTestCase {

	public func testBasics() {

		let a = MMMTestLoadable()
		let b = MMMTestLoadable()
		let c = MMMTestLoadable()

		let chain = MMMLoadableChain([a, b, c])
		XCTAssertEqual(a.loadableState, .idle)
		XCTAssertEqual(b.loadableState, .idle)
		XCTAssertEqual(c.loadableState, .idle)
		XCTAssertEqual(chain.loadableState, .idle)
		XCTAssert(!chain.isContentsAvailable)

		// When the chain syncs it starts with the first object.
		chain.syncIfNeeded()
		pump()
		XCTAssertEqual(a.loadableState, .syncing) // <--
		XCTAssertEqual(b.loadableState, .idle)
		XCTAssertEqual(c.loadableState, .idle)
		XCTAssertEqual(chain.loadableState, .syncing)
		XCTAssert(!chain.isContentsAvailable)

		// ...and then continues to the next.
		a.setDidSyncSuccessfully()
		pump()
		XCTAssertEqual(a.loadableState, .didSyncSuccessfully)
		XCTAssertEqual(b.loadableState, .syncing) // <--
		XCTAssertEqual(c.loadableState, .idle)
		XCTAssertEqual(chain.loadableState, .syncing)
		XCTAssert(!chain.isContentsAvailable)

		// The whole chain fails to sync as soon as the current object does.
		b.setDidFailToSyncWithError(NSError(domain: self, message: "Simulated error"))
		pump()
		XCTAssertEqual(a.loadableState, .didSyncSuccessfully)
		XCTAssertEqual(b.loadableState, .didFailToSync) // <--
		XCTAssertEqual(c.loadableState, .idle)
		XCTAssertEqual(chain.loadableState, .didFailToSync) // <--
		XCTAssertEqual(
			chain.error?.mmm_description,
			"Could not sync element #1 (MMMLoadableChain) > Simulated error (MMMLoadableChainTestCase)"
		)
		XCTAssert(!chain.isContentsAvailable)

		// When restarted it should continue with the first failed.
		chain.syncIfNeeded()
		pump()
		XCTAssertEqual(a.loadableState, .didSyncSuccessfully)
		XCTAssertEqual(b.loadableState, .syncing) // <--
		XCTAssertEqual(c.loadableState, .idle)
		XCTAssertEqual(chain.loadableState, .syncing) // <--
		XCTAssertNil(chain.error)
		XCTAssert(!chain.isContentsAvailable)

		// Let's sync the last one in advance on its own.
		c.setDidSyncSuccessfully()
		pump()
		XCTAssertEqual(a.loadableState, .didSyncSuccessfully)
		XCTAssertEqual(b.loadableState, .syncing)
		XCTAssertEqual(c.loadableState, .didSyncSuccessfully) // <--
		XCTAssertEqual(chain.loadableState, .syncing)
		XCTAssertNil(chain.error)
		XCTAssert(!chain.isContentsAvailable)

		// So the whole chain is ready as soon as `b` is.
		b.setDidSyncSuccessfully()
		pump()
		XCTAssertEqual(a.loadableState, .didSyncSuccessfully)
		XCTAssertEqual(b.loadableState, .didSyncSuccessfully)
		XCTAssertEqual(c.loadableState, .didSyncSuccessfully)
		XCTAssertEqual(chain.loadableState, .didSyncSuccessfully)
		XCTAssertNil(chain.error)
		XCTAssert(chain.isContentsAvailable)
	}

	public func testCallbacks() {

		let actions = [
			.completeSuccessfully,
			.proceed,
			.fail(NSError(domain: self, message: "Simulated error"))
		] as [MMMLoadableChain.NextAction]

		for action in actions.shuffled() {

			let a = MMMTestLoadable()
			let b = MMMTestLoadable()
			let c = MMMTestLoadable()

			let chain = MMMLoadableChain([
				.init(a),
				.init(b) { action },
				.init(c)
			])

			// Let's start with the first object synced already, so it begins with the second.
			a.setDidSyncSuccessfully()
			chain.syncIfNeeded()
			pump()
			XCTAssertEqual(a.loadableState, .didSyncSuccessfully)
			XCTAssertEqual(b.loadableState, .syncing) // <--
			XCTAssertEqual(c.loadableState, .idle)
			XCTAssertEqual(chain.loadableState, .syncing)
			XCTAssertNil(chain.error)
			XCTAssert(!chain.isContentsAvailable)

			// Now when the second is synced the corresponding callback can control what happens next.
			b.setDidSyncSuccessfully()
			pump()
			switch action {
			case .completeSuccessfully:
				// The callback can indicate that we have enough info with `a` and `b` already and don't need the rest...
				XCTAssertEqual(a.loadableState, .didSyncSuccessfully)
				XCTAssertEqual(b.loadableState, .didSyncSuccessfully)
				XCTAssertEqual(c.loadableState, .idle)
				XCTAssertEqual(chain.loadableState, .didSyncSuccessfully)
				XCTAssertNil(chain.error)
				XCTAssert(chain.isContentsAvailable)
			case .fail:
				// ... or it can tell that something is still not enough to sync c even though a and b were properly synced.
				XCTAssertEqual(a.loadableState, .didSyncSuccessfully)
				XCTAssertEqual(b.loadableState, .didSyncSuccessfully)
				XCTAssertEqual(c.loadableState, .idle)
				XCTAssertEqual(chain.loadableState, .didFailToSync)
				XCTAssertEqual(chain.error?.mmm_description, "Simulated error (MMMLoadableChainTestCase)")
				XCTAssert(!chain.isContentsAvailable)
			case .proceed:
				// And of course the callback can, for example, prepare `c` based on the info from `a` or `b` and
				// the ask the chain to proceed.
				XCTAssertEqual(a.loadableState, .didSyncSuccessfully)
				XCTAssertEqual(b.loadableState, .didSyncSuccessfully)
				XCTAssertEqual(c.loadableState, .syncing)
				XCTAssertEqual(chain.loadableState, .syncing)
				XCTAssertNil(chain.error)
				XCTAssert(!chain.isContentsAvailable)
			}
		}
	}

	private func pump(count: Int = 16) {
		for _ in 1...count {
			let e = expectation(description: "Next cycle of the main queue")
			DispatchQueue.main.async {
				e.fulfill()
			}
			wait(for: [e])
		}
	}
}
