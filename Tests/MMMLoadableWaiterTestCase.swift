//
// MMMLoadable. Part of MMMTemple.
// Copyright (C) 2016-2020 MediaMonks. All rights reserved.
//

import MMMCommonCore
import MMMLoadable
import XCTest

class MMMLoadableWaiterTestCase: XCTestCase {

	private var loadable: MMMTestLoadable!
	private var loadableHasContentsAvailable: MMMLoadableWaiter!
	private var timeSource: MMMMockTimeSource!

    override func setUp() {
    	loadable = .init()
    	timeSource = .init(scale: 0.01)
    	loadableHasContentsAvailable = .init(
    		loadable: loadable,
    		condition: .isContentsAvailable,
    		timeout: 30,
    		shouldSyncIfPossible: true,
    		queue: nil,
    		timeSource: timeSource
		)
    }

    func testTimeout() {

    	let timedOut = expectation(description: "Waiting timed out")

    	let shouldNotTimeOut = expectation(description: "Should not time out")
    	shouldNotTimeOut.isInverted = true

    	loadable.isContentsAvailable = false
    	loadableHasContentsAvailable.wait {
    		if case .failure = $0 {
    			timedOut.fulfill()
    			shouldNotTimeOut.fulfill()
			}
		}
    	timeSource.now = timeSource.now.addingTimeInterval(10)
		wait(for: [shouldNotTimeOut], timeout: 1)

    	timeSource.now = timeSource.now.addingTimeInterval(30)
		wait(for: [timedOut], timeout: 1)
    }

    func testBasics() {

    	let done = expectation(description: "Waiting completed")

    	let notDoneYet = expectation(description: "Should not time out")
    	notDoneYet.isInverted = true

    	loadable.isContentsAvailable = false
    	var result: Result<MMMPureLoadableProtocol, Error>?
    	loadableHasContentsAvailable.wait {
    		result = $0
			done.fulfill()
			notDoneYet.fulfill()
		}
    	timeSource.now = timeSource.now.addingTimeInterval(10)
		wait(for: [notDoneYet], timeout: 1)

    	loadable.isContentsAvailable = true
		wait(for: [done], timeout: 1)
		if case .failure = result {
			XCTFail("Expected the waiting to be successful")
		}
    }
}
