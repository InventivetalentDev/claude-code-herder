// swift-tools-version:5.10
import PackageDescription

let package = Package(
    name: "ClaudeHerder",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(name: "ClaudeHerder"),
        .testTarget(
            name: "ClaudeHerderTests",
            dependencies: ["ClaudeHerder"]
        ),
    ]
)
