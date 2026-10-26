// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "clipdown",
    platforms: [.macOS(.v15)],
    products: [
        .executable(name: "clipdown", targets: ["clipdown"]),
    ],
    dependencies: [
        // Same pinned version as Spotmoji.
        .package(url: "https://github.com/sparkle-project/Sparkle", exact: "2.9.6"),
    ],
    targets: [
        .target(name: "ClipDownCore"),
        .executableTarget(
            name: "clipdown",
            dependencies: [
                "ClipDownCore",
                .product(name: "Sparkle", package: "Sparkle"),
            ]
        ),
        .testTarget(name: "ClipDownCoreTests", dependencies: ["ClipDownCore"]),
    ]
)
