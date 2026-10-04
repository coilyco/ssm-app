// swift-tools-version:5.10
import PackageDescription

let package = Package(
    name: "SsmApp",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "SsmApp", targets: ["SsmApp"]),
        .executable(name: "ssm-check", targets: ["SsmCheck"]),
    ],
    targets: [
        .target(name: "SsmCore"),
        .executableTarget(name: "SsmApp", dependencies: ["SsmCore"]),
        .executableTarget(name: "SsmCheck", dependencies: ["SsmCore"]),
    ]
)
