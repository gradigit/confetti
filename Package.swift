// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "confetti",
    platforms: [
        .macOS(.v12)
    ],
    products: [
        .library(
            name: "ConfettiKit",
            targets: ["ConfettiKit"]
        ),
        .executable(
            name: "confetti",
            targets: ["confetti"]
        )
    ],
    targets: [
        .target(
            name: "ConfettiKit",
            path: "Sources/ConfettiKit"
        ),
        .executableTarget(
            name: "confetti",
            dependencies: ["ConfettiKit"],
            path: "Sources/confetti"
        ),
        .executableTarget(
            name: "benchmark",
            dependencies: ["ConfettiKit"],
            path: "Sources/benchmark"
        ),
        .testTarget(
            name: "ConfettiKitTests",
            dependencies: ["ConfettiKit"],
            path: "Tests/ConfettiKitTests"
        )
    ]
)
