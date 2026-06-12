// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "Stag",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(name: "Stag", path: "Sources/Stag", exclude: ["Info.plist"], resources: [.process("Resources")]),
        .executableTarget(name: "stag-cli", path: "Sources/StagCLI",
                          swiftSettings: [.unsafeFlags(["-parse-as-library"], .when(configuration: .release))]),
        .testTarget(name: "StagTests", dependencies: ["Stag"], path: "Tests/StagTests")
    ]
)
