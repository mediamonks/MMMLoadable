//
// Starbucks App.
// Copyright (c) 2024 MediaMonks. All rights reserved.
// 

#if canImport(CoreImage)

import CoreImage

/// A simple proxy filtering the contents of another loadable image with CoreImage filters.
public final class MMMFilteredLoadableImage: MMMLoadableProxy, MMMLoadableImage {

	private let upstreamImage: MMMLoadableImage
	private let filters: [CIFilter]

	public init(_ image: MMMLoadableImage, _ filters: [CIFilter]) {
		self.upstreamImage = image
		self.filters = filters
		super.init()
		self.loadable = image
	}

	public override func proxyDidChange() {
		if
			upstreamImage.isContentsAvailable, let uiImage = upstreamImage.image,
			let ciImage = uiImage.ciImage ?? uiImage.cgImage.flatMap(CIImage.init(cgImage:))
		{
			// TODO: it would be great to move it out of the main thread of course.
			let outputImage = filters.reduce(ciImage) { inputImage, filter in
				filter.setValue(inputImage, forKey: kCIInputImageKey)
				return filter.outputImage ?? inputImage
			}
			self.image = UIImage(ciImage: outputImage)
		} else {
			self.image = nil
		}
	}

	public override var isContentsAvailable: Bool { image != nil }

	public override var loadableState: MMMLoadableState {
		set { self.loadableState = newValue }
		get {
			if super.loadableState == .didSyncSuccessfully && !isContentsAvailable {
				.didFailToSync
			} else {
				super.loadableState
			}
		}
	}

	public private(set) var image: UIImage?
}

#endif
