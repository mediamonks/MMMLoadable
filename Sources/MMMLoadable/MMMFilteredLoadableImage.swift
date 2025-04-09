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
			// Copying filters in order to quickly dispose of their input and output images, so we don't hold them
			// more than needed and TODO: can process them on a background thread.
			let tempFilters = filters.map { $0.copy() as! CIFilter }
			let outputImage = tempFilters.reduce(ciImage) { inputImage, filter in
				filter.setValue(inputImage, forKey: kCIInputImageKey)
				return filter.outputImage ?? inputImage
			}
			// Going with `UIImage(ciImage: outputImage)` would cause an issue with `UIImageView` (at least on iOS 17),
			// if a smaller image is processed after the larger one. It looks like the same surface is reused for both
			// of them, but `UIImageView` fails to properly show only the used portion of that surface.
			// Pre-rendering this as a CGImage avoids the issue.
			self.image = CIContext().createCGImage(outputImage, from: .init(origin: .zero, size: outputImage.extent.size))
				.map(UIImage.init(cgImage:))
		} else {
			self.image = nil
		}
	}

	public override var isContentsAvailable: Bool { image != nil }

	public override var loadableState: MMMLoadableState {
		set { super.loadableState = newValue }
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
