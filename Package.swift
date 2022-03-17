// swift-tools-version:5.4
import PackageDescription

let package = Package(
    name: "MMMLoadable",
    platforms: [
        .iOS(.v11),
        .watchOS(.v5),
        .tvOS(.v10),
        .macOS(.v10_12)
    ],
    products: [
        .library(
            name: "MMMLoadable",
            targets: ["MMMLoadable"]
		)
    ],
    dependencies: [
		.package(url: "https://github.com/mediamonks/MMMCommonCore", .upToNextMajor(from: "1.7.0")),
		.package(url: "https://github.com/mediamonks/MMMObservables", .upToNextMajor(from: "1.3.2")),
		.package(url: "https://github.com/mediamonks/MMMLog", .upToNextMajor(from: "1.2.4"))
    ],
    targets: [
        .target(
            name: "MMMLoadableObjC",
            dependencies: [
				"MMMCommonCore",
				"MMMLog",
				"MMMObservables"
            ],
            path: "Sources/MMMLoadableObjC"
		),
        .target(
            name: "MMMLoadable",
            dependencies: [
				"MMMLoadableObjC",
				"MMMCommonCore",
				"MMMLog"
			],
            path: "Sources/MMMLoadable"
		),
        .testTarget(
            name: "MMMLoadableTests",
            dependencies: [
				"MMMLoadable",
				"MMMCommonCore"
			],
            path: "Tests"
		)
    ]
)
