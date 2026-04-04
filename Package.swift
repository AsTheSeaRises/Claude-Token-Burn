// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "ClaudeTokenBurn",
    platforms: [.macOS(.v13)],
    targets: [
        .executableTarget(
            name: "ClaudeTokenBurn",
            path: "Sources/ClaudeTokenBurn"
        )
    ]
)
