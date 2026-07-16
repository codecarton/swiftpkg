// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "munkipkg",
    platforms: [.macOS(.v13)],
    products: [
        .executable(name: "munkipkg", targets: ["munkipkg"])
    ],
    dependencies: [
        .package(url: "https://github.com/jpsim/Yams.git", from: "6.2.2")
    ],
    targets: [
        .executableTarget(
            name: "munkipkg",
            dependencies: ["Yams"],
            path: "munki-pkg"
        ),
        .testTarget(
            name: "munkipkgTests",
            dependencies: ["munkipkg", "Yams"],
            path: "munki-pkgTests"
        )
    ]
)
