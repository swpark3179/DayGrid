// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "DayGridCore",
    platforms: [
        .iOS(.v18),
        .macOS(.v15),
    ],
    products: [
        .library(name: "DayGridCore", targets: ["DayGridCore"]),
    ],
    targets: [
        .target(name: "DayGridCore"),
        .testTarget(name: "DayGridCoreTests", dependencies: ["DayGridCore"]),
    ]
)
