// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "swiftpkg",
    platforms: [.macOS(.v13)],
    products: [
        .executable(name: "swiftpkg", targets: ["swiftpkg"])
    ],
    dependencies: [
        .package(url: "https://github.com/jpsim/Yams.git", from: "6.2.2")
    ],
    targets: [
        .executableTarget(
            name: "swiftpkg",
            dependencies: ["Yams"],
            path: "swiftpkg"
        ),
        .testTarget(
            name: "swiftpkgTests",
            dependencies: ["swiftpkg", "Yams"],
            path: "swiftpkgTests"
        )
    ]
)
