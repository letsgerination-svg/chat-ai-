// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "HybridChatCore",
    platforms: [.iOS("16.4"), .macOS("13.3")],
    products: [
        .library(name: "HybridChatCore", targets: ["HybridChatCore"]),
        .library(name: "LlamaRuntime", targets: ["LlamaRuntime"])
    ],
    targets: [
        .binaryTarget(
            name: "LlamaFramework",
            url: "https://github.com/ggml-org/llama.cpp/releases/download/b12387/llama-b12387-xcframework.zip",
            checksum: "93d4ab674c75d590b6e0650b24683964c61dbbeb6bb94aa8dbed5a61346899f8"
        ),
        .target(
            name: "LlamaRuntime",
            dependencies: ["LlamaFramework"]
        ),
        .target(name: "HybridChatCore"),
        .testTarget(
            name: "HybridChatCoreTests",
            dependencies: ["HybridChatCore"]
        )
    ]
)
