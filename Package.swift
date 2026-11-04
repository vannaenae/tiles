// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "Tiles",
    platforms: [.macOS(.v13)],
    products: [
        .executable(name: "Tiles", targets: ["Tiles"]),
        .library(name: "TilesCore", targets: ["TilesCore"]),
    ],
    targets: [
        // Pure Swift: layouts, config, scenes, geometry. No AppKit, fully unit-tested.
        .target(name: "TilesCore"),
        // The macOS menu bar app: Accessibility, hotkeys, window events.
        .executableTarget(
            name: "Tiles",
            dependencies: ["TilesCore"],
            linkerSettings: [
                .linkedFramework("AppKit"),
                .linkedFramework("ApplicationServices"),
                .linkedFramework("Carbon"),
                .linkedFramework("ServiceManagement"),
            ]
        ),
        .testTarget(name: "TilesCoreTests", dependencies: ["TilesCore"]),
    ]
)
