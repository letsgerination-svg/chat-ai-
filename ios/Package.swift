// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "HybridChatCore",
    platforms: [.iOS(.v16), .macOS(.v13)],
    products: [
        .library(name: "HybridChatCore", targets: ["HybridChatCore"])
    ],
    targets: [
        .target(name: "HybridChatCore"),
        .testTarget(
            name: "HybridChatCoreTests",
            dependencies: ["HybridChatCore"]
        )
    ]
)
