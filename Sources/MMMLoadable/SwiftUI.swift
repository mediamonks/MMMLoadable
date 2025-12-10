//
// MMMLoadable. Part of MMMTemple.
// Copyright (C) 2026 Monks. All rights reserved.
//

import SwiftUI
import Combine

/// A property wrapper that allows using loadables directly with `@StateObject` and `@ObservedObject` in SwiftUI.
///
/// For example:
///
/// ```swift
/// @StateObject @UsingLoadable var viewModel: TestViewModel = DefaultTestViewModel()
/// ```
@propertyWrapper @dynamicMemberLookup
public class UsingLoadable<T>: MMMPureLoadableProxy, ObservableObject {

	public let wrappedValue: T

	public init(wrappedValue: T) {
		self.wrappedValue = wrappedValue
		super.init()
		// Yeah, ugly runtime check, but allows to avoid those "`any P` does not conform to `MMMPureLoadableProtocol`"
		// errors when `T` is bound to `MMMLoadableProtocol` and `P` is a protocol conforming `MMMPureLoadableProtocol`.
		guard let loadable = wrappedValue as? MMMPureLoadableProtocol else {
			preconditionFailure("\(type(of: T.self)) is expected to conform to ")
		}
		self.loadable = loadable
	}

	public override func proxyDidChange() {
		objectWillChange.send()
	}

	public let objectWillChange = ObservableObjectPublisher()

	public subscript<Subject>(dynamicMember keyPath: ReferenceWritableKeyPath<T, Subject>) -> Subject {
		get { wrappedValue[keyPath: keyPath] }
		set { wrappedValue[keyPath: keyPath] = newValue }
	}

	public subscript<Subject>(dynamicMember keyPath: ReferenceWritableKeyPath<T, Subject>) -> Binding<Subject> {
		.init(
			get: { self.wrappedValue[keyPath: keyPath] },
			set: { self.wrappedValue[keyPath: keyPath] = $0 }
		)
	}
}
