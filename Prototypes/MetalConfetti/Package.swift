// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "MetalConfetti",
    platforms: [.macOS(.v14)],
    dependencies: [
        .package(path: "../..")
    ],
    targets: [
        .executableTarget(
            name: "MetalConfetti",
            dependencies: [
                .product(name: "ConfettiKit", package: "confetti")
            ],
            path: "Sources/MetalConfetti"
        )
    ]
)
