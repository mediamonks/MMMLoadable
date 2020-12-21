//
// Avianca iOS App.
// Copyright (C) 2020 Avianca S.A. All rights reserved.
// Developed for Avianca by MediaMonks B.V.
//

import MMMLoadable
import XCTest

class MMMSimpleLoadableWaiterTestCase: XCTestCase {

	private var loadable: MMMTestLoadable! = MMMTestLoadable()
	private var completed: XCTestExpectation!
	private var notTooEarly: XCTestExpectation!
	private var waiter: MMMSimpleLoadableWaiter!

	override func setUp() {
		super.setUp()
		loadable = MMMTestLoadable()
		completed = expectation(description: "Done waiting")
	}

	func testAlreadyNotSyncing() {
		waiter = MMMSimpleLoadableWaiter.whenDoneSyncing(loadable) {
			self.completed.fulfill()
		}
		self.wait(for: [ completed ], timeout: 1)
	}

	func testBasics() {

		notTooEarly = expectation(description: "Completed too early")
		notTooEarly.isInverted = true

		loadable.setSyncing()

		waiter = MMMSimpleLoadableWaiter.whenDoneSyncing(loadable) {
			self.completed.fulfill()
			self.notTooEarly.fulfill()
		}

		self.wait(for: [ notTooEarly ], timeout: 1)

		// It should not matter how exactly we stop syncing, thus random here.
		if Bool.random() {
			loadable.setDidSyncSuccessfully()
		} else {
			loadable.setDidFailToSyncWithError(nil)
		}
		self.wait(for: [ completed ], timeout: 1)
	}
}
