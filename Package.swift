// swift-tools-version:5.1
import PackageDescription

let package = Package(
    name: "MMMLoadable",
    platforms: [
        .iOS(.v11)
    ],
    products: [
        .library(
            name: "MMMLoadable",
            targets: ["MMMLoadable"]
		)
    ],
    dependencies: [
		.package(url: "https://github.com/mediamonks/MMMCommonCore", .upToNextMajor(from: "1.3.2")),
		.package(url: "https://github.com/mediamonks/MMMObservables", .upToNextMajor(from: "1.2.2")),
		.package(url: "https://github.com/mediamonks/MMMLog", .upToNextMajor(from: "1.2.2"))
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
