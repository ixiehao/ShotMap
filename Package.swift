// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "ShotMap",
    defaultLocalization: "zh-Hans",
    platforms: [.macOS(.v13)],
    products: [
        .executable(name: "ShotMap", targets: ["ShotMapApp"])
    ],
    targets: [
        .executableTarget(
            name: "ShotMapApp",
            path: "Sources/ShotMapApp",
            resources: [.process("Resources")]
        ),
        .testTarget(
            name: "ShotMapCoreTests",
            dependencies: ["ShotMapApp"],
            path: "Tests/ShotMapCoreTests"
        )
    ]
)
