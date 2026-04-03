// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "VirtuMic",
    platforms: [.macOS(.v13)],
    targets: [
        .executableTarget(
            name: "VirtuMic",
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
