// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "Cleanium",
    platforms: [.macOS(.v14)],
    targets: [
        .target(
            name: "CleaniumCore",
            resources: [.copy("Resources/rules.json")]
        ),
        .executableTarget(
            name: "Cleanium",
            dependencies: ["CleaniumCore"]
        ),
        .testTarget(
            name: "CleaniumCoreTests",
            dependencies: ["CleaniumCore"]
        ),
    ]
)
