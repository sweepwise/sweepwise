// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "Sweepwise",
    platforms: [.macOS(.v14)],
    targets: [
        .target(
            name: "SweepwiseCore",
            resources: [.copy("Resources/rules.json")]
        ),
        .executableTarget(
            name: "Sweepwise",
            dependencies: ["SweepwiseCore"]
        ),
        .testTarget(
            name: "SweepwiseCoreTests",
            dependencies: ["SweepwiseCore"]
        ),
    ]
)
