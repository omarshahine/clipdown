// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "clipdown",
    platforms: [.macOS(.v15)],
    products: [
        .executable(name: "clipdown", targets: ["clipdown"]),
    ],
    targets: [
        .target(name: "ClipDownCore"),
        .executableTarget(name: "clipdown", dependencies: ["ClipDownCore"]),
        .testTarget(name: "ClipDownCoreTests", dependencies: ["ClipDownCore"]),
    ]
)
