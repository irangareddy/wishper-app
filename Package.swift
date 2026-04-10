// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "WishperApp",
    platforms: [
        .macOS(.v15),
    ],
    dependencies: [
        .package(url: "https://github.com/ml-explore/mlx-swift-lm.git", from: "2.31.0"),
        .package(url: "https://github.com/soniqo/speech-swift.git", from: "0.0.8"),
    ],
    targets: [
        .executableTarget(
            name: "WishperApp",
            dependencies: [
                .product(name: "MLXLLM", package: "mlx-swift-lm"),
                .product(name: "MLXLMCommon", package: "mlx-swift-lm"),
                .product(name: "Qwen3ASR", package: "speech-swift"),
                .product(name: "SpeechVAD", package: "speech-swift"),
            ],
            path: "Sources/WishperApp"
        ),
    ]
)
