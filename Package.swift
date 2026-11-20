// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "ShotMap",
    defaultLocalization: "en",
    platforms: [.macOS(.v13)],
    products: [
        .executable(name: "ShotMap", targets: ["ShotMapApp"])
    ],
    targets: [
        .target(
            name: "CWebP",
            path: "Sources/CWebP",
            exclude: ["COPYING", "PATENTS"],
            publicHeadersPath: "include",
            cSettings: [.headerSearchPath(".")]
        ),
        .executableTarget(
            name: "ShotMapApp",
            dependencies: ["CWebP"],
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
