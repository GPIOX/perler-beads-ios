// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "BeadPatternCore",
    platforms: [
        .iOS(.v17),
        .macOS(.v14),
    ],
    products: [
        .library(name: "BeadPatternCore", targets: ["BeadPatternCore"]),
    ],
    targets: [
        .target(
            name: "BeadPatternCore",
            resources: [.process("Resources")]
        ),
        .testTarget(
            name: "BeadPatternCoreTests",
            dependencies: ["BeadPatternCore"],
            resources: [.process("Fixtures")]
        ),
    ]
)
