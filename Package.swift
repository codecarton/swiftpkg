// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "swiftpkg",
    platforms: [.macOS(.v13)],
    products: [
        .library(name: "SwiftPkgCore", type: .static, targets: ["SwiftPkgCore"]),
        .executable(name: "swiftpkg", targets: ["swiftpkg"])
    ],
    dependencies: [
        .package(url: "https://github.com/apple/swift-argument-parser", from: "1.7.0"),
        .package(url: "https://github.com/jpsim/Yams.git", from: "6.2.2")
    ],
    targets: [
        .target(
            name: "SwiftPkgCore",
            dependencies: ["Yams"],
            path: "swiftpkg"
        ),
        .executableTarget(
            name: "swiftpkg",
            dependencies: [
                "SwiftPkgCore",
                .product(name: "ArgumentParser", package: "swift-argument-parser"),
            ],
            path: "swiftpkgCLI"
        ),
        .testTarget(
            name: "swiftpkgTests",
            dependencies: ["SwiftPkgCore", "swiftpkg", "Yams"],
            path: "swiftpkgTests"
        )
    ]
)
