// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "Cropit",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(name: "Cropit", path: "Sources/Cropit", exclude: ["Info.plist"], resources: [.process("Resources")]),
        .testTarget(name: "CropitTests", dependencies: ["Cropit"], path: "Tests/CropitTests")
    ]
)
