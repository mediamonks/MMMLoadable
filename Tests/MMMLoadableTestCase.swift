//
// MMMLoadable. Part of MMMTemple.
// Copyright (C) 2016-2023 MediaMonks. All rights reserved.
//

import MMMCommonCore
import MMMLoadable
import XCTest

public final class MMMLoadableTestCase: XCTestCase {

	func testGroup() {
		
		XCTAssertEqual(
			groupTruthTable(mode: .all),
			"""
			### isContentsAvailable
			
			false <- [false, false]
			false <- [false, true]
			false <- [true, false]
			true <- [true, true]
			
			### loadableState
			
			idle <- [idle, idle]
			idle <- [idle, did-sync-successfully]
			idle <- [did-sync-successfully, idle]
			syncing <- [idle, syncing]
			syncing <- [syncing, idle]
			syncing <- [syncing, syncing]
			syncing <- [syncing, did-sync-successfully]
			syncing <- [did-sync-successfully, syncing]
			did-sync-successfully <- [did-sync-successfully, did-sync-successfully]
			did-fail-to-sync <- [idle, did-fail-to-sync]
			did-fail-to-sync <- [syncing, did-fail-to-sync]
			did-fail-to-sync <- [did-sync-successfully, did-fail-to-sync]
			did-fail-to-sync <- [did-fail-to-sync, idle]
			did-fail-to-sync <- [did-fail-to-sync, syncing]
			did-fail-to-sync <- [did-fail-to-sync, did-sync-successfully]
			did-fail-to-sync <- [did-fail-to-sync, did-fail-to-sync]
			
			"""
		)

		XCTAssertEqual(
			groupTruthTable(mode: .any),
			"""
			### isContentsAvailable

			false <- [false, false]
			true <- [false, true]
			true <- [true, false]
			true <- [true, true]

			### loadableState

			idle <- [idle, idle]
			idle <- [idle, did-fail-to-sync]
			idle <- [did-fail-to-sync, idle]
			syncing <- [idle, syncing]
			syncing <- [syncing, idle]
			syncing <- [syncing, syncing]
			syncing <- [syncing, did-sync-successfully]
			syncing <- [syncing, did-fail-to-sync]
			syncing <- [did-sync-successfully, syncing]
			syncing <- [did-fail-to-sync, syncing]
			did-sync-successfully <- [idle, did-sync-successfully]
			did-sync-successfully <- [did-sync-successfully, idle]
			did-sync-successfully <- [did-sync-successfully, did-sync-successfully]
			did-sync-successfully <- [did-sync-successfully, did-fail-to-sync]
			did-sync-successfully <- [did-fail-to-sync, did-sync-successfully]
			did-fail-to-sync <- [did-fail-to-sync, did-fail-to-sync]
			
			"""
		)

		// This is what the former `MMMLoadableGroupFailurePolicyNever` would produce.
		// Note the issue with isContentsAvailable still depending on all objects which causes it to be `false`
		// when the composite state is `did-sync-successfully`.
		XCTAssertEqual(
			groupTruthTable(mode: .__deprecated),
			"""
			### isContentsAvailable

			false <- [false, false]
			false <- [false, true]
			false <- [true, false]
			true <- [true, true]

			### loadableState

			idle <- [idle, idle]
			idle <- [idle, did-sync-successfully]
			idle <- [idle, did-fail-to-sync]
			idle <- [did-sync-successfully, idle]
			idle <- [did-fail-to-sync, idle]
			syncing <- [idle, syncing]
			syncing <- [syncing, idle]
			syncing <- [syncing, syncing]
			syncing <- [syncing, did-sync-successfully]
			syncing <- [syncing, did-fail-to-sync]
			syncing <- [did-sync-successfully, syncing]
			syncing <- [did-fail-to-sync, syncing]
			did-sync-successfully <- [did-sync-successfully, did-sync-successfully]
			did-sync-successfully <- [did-sync-successfully, did-fail-to-sync]
			did-sync-successfully <- [did-fail-to-sync, did-sync-successfully]
			did-sync-successfully <- [did-fail-to-sync, did-fail-to-sync]
			
			"""
		)
	}
	
	private func groupTruthTable(mode: MMMLoadableGroupMode) -> String {
	
		var result: String = ""
		
		print("### isContentsAvailable\n", to: &result)
		print(
			truthTable(
				groupMode: mode,
				values: [false, true]
			) { group, pairs in
				// isContentsAvailable Is recalculated only with state changes, thus need to flip
				// the composite state back and forth.
				for (o, v) in pairs {
					o.isContentsAvailable = v
					o.setSyncing()
				}
				for (o, _) in pairs {
					o.setDidFailToSyncWithError(nil)
				}
				return group.isContentsAvailable
			},
			to: &result
		)
		
		print("\n### loadableState\n", to: &result)
		print(
			truthTable(
				groupMode: mode,
				values: [.idle, .syncing, .didFailToSync, .didSyncSuccessfully] as [MMMLoadableState]
			) { group, pairs in
				for (o, v) in pairs {
					o.loadableState = v
				}
				return group.loadableState
			},
			to: &result
		)
		
		return result
	}
	
	private struct TruthTable<T: Comparable>: CustomStringConvertible {
	
		public let rows: [TruthTableRow<T>]
		
		public var description: String {
			// Need to sorting because we are randomizing order while testing.
			let sorted = rows.sorted {
				if $0.output < $1.output {
					return true
				} else if $0.output == $1.output {
					// Arrays are not Comparable.
					for (a, b) in zip($0.inputs, $1.inputs) {
						if a < b {
							return true
						} else if a > b {
							return false
						}
					}
					return false
				} else {
					return false
				}
			}
			return sorted.map(String.init(describing:)).joined(separator: "\n")
		}
	}
	
	private struct TruthTableRow<T: Comparable>: Equatable, CustomStringConvertible {

		public let inputs: [T]
		public let output: T
		
		public init(_ inputs: [T], _ output: T) {
			self.inputs = inputs
			self.output = output
		}
		
		public var description: String {
			"\(output) <- \(inputs)"
		}
	}

	private func truthTable<T: Comparable>(
		groupMode: MMMLoadableGroupMode,
		values: [T],
		assign: (MMMLoadableGroup, [(MMMTestLoadable, T)]) -> T
	) -> TruthTable<T> {
	
		let c1 = MMMTestLoadable()
		let c2 = MMMTestLoadable()
		let group = MMMLoadableGroup(loadables: [c1, c2], mode: groupMode)
		
		var rows: [TruthTableRow<T>] = []
		// Shuffling to avoid dependency on the order.
		for v1 in values.shuffled() {
			for v2 in values.shuffled() {
				let output = assign(group, [(c1, v1), (c2, v2)])
				rows.append(.init([v1, v2], output))
			}
		}
		return .init(rows: rows)
	}
}

extension MMMLoadableState: Comparable {
	public static func < (lhs: MMMLoadableState, rhs: MMMLoadableState) -> Bool {
		lhs.rawValue < rhs.rawValue
	}
}

extension Bool: Comparable {
	public static func < (lhs: Bool, rhs: Bool) -> Bool {
		!lhs && rhs
	}
}
