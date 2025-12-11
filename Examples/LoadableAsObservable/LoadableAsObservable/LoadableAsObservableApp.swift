//
// MMMLoadable. Part of MMMTemple.
// Copyright (C) 2025 Monks. All rights reserved.
//

import SwiftUI
import MMMLoadable

protocol TestViewModel: MMMLoadableProtocol {
	var image: MMMLoadableImage { get }
	var counter: Int { get set }
	var isEnabled: Bool { get set }
	func beep()
}

final class DefaultTestViewModel: MMMLoadableProxy, TestViewModel {

	public let image: MMMLoadableImage

	public override init() {
		self.image = MMMPublicLoadableImage(url: .init(string: "https://picsum.photos/200/300"))
		super.init()
		self.loadable = image
	}

	public var counter: Int = 0 {
		didSet { notifyDidChange() }
	}

	public var isEnabled: Bool = false {
		didSet { notifyDidChange() }
	}

	public func beep() {
		counter += 1
		isEnabled.toggle()
	}
}

@main
struct LoadableAsObservableApp: App {

	@StateObject @UsingLoadable
	var viewModel: TestViewModel = DefaultTestViewModel()

    var body: some Scene {
        WindowGroup {
            ContentView(viewModel: viewModel)
        }
    }
}
