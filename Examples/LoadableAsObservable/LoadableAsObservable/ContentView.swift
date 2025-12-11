//
// MMMLoadable. Part of MMMTemple.
// Copyright (C) 2025 Monks. All rights reserved.
//

import SwiftUI
import MMMLoadable

// This view can work with `any TestViewModel` without being generic.
struct ContentView: View {

	@ObservedObject @UsingLoadable
	public var viewModel: TestViewModel

	public init(viewModel: TestViewModel) {
		self._viewModel = .init(initialValue: .init(wrappedValue: viewModel))
	}

    var body: some View {
        VStack {
			Image(uiImage: viewModel.image.image ?? UIImage(systemName: "globe")!)
                .imageScale(.large)
                .foregroundStyle(.tint)
            Text("Counter: \(viewModel.counter)")
            Button("Beep") {
            	// A function call.
            	viewModel.beep()
            }
			// A regular property.
            if viewModel.isEnabled {
            	Text("Enabled")
            } else {
            	Text("Disabled")
            }
            // A binding.
			Toggle(isOn: $viewModel.isEnabled) {
				Text("isEnabled")
			}
        }
        .padding()
		.onAppear {
			viewModel.image.syncIfNeeded()
		}
    }
}

#Preview {
	@Previewable @StateObject @UsingLoadable var viewModel = DefaultTestViewModel()

    ContentView(viewModel: viewModel)
}
