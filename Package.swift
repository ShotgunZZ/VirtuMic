// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "VirtuMic",
    platforms: [.macOS(.v13)],
    dependencies: [
        .package(url: "https://github.com/apple/swift-atomics.git", from: "1.2.0"),
    ],
    targets: [
        .executableTarget(
            name: "VirtuMic",
            dependencies: [
                .product(name: "Atomics", package: "swift-atomics"),
            ],
            path: "Sources/VirtuMic",
            linkerSettings: [
                .linkedFramework("AVFoundation"),
                .linkedFramework("CoreAudio"),
                .linkedFramework("AudioToolbox"),
                .linkedFramework("Accelerate"),
            ]
        ),
    ]
)
