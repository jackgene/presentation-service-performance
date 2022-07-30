// swift-tools-version: 5.6
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "PresentationServicePerformance",
    platforms: [.macOS(.v12)],
    dependencies: [
        .package(
            url: "https://github.com/apple/swift-collections-benchmark",
            from: "0.0.2"),
    ],
    targets: [
        .executableTarget(
            name: "PresentationServicePerformance",
            dependencies: [
                .product(
                    name: "CollectionsBenchmark",
                    package: "swift-collections-benchmark"),
            ]),
    ]
)
