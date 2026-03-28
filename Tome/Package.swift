// swift-tools-version: 6.2

import PackageDescription

let package = Package(
    name: "Tome",
    platforms: [.macOS(.v26)],
    dependencies: [
        .package(url: "https://github.com/FluidInference/FluidAudio.git", "0.12.1"..<"0.12.2"),
        .package(url: "https://github.com/sparkle-project/Sparkle", from: "2.7.0"),
    ],
    targets: [
        .executableTarget(
            name: "Tome",
            dependencies: [
                .product(name: "FluidAudio", package: "FluidAudio"),
                .product(name: "Sparkle", package: "Sparkle"),
            ],
            path: "Sources/Tome",
            exclude: ["Info.plist", "Tome.entitlements", "Assets"]
        ),
    ]
)
