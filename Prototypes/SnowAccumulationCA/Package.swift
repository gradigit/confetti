// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "SnowAccumulationCA",
    platforms: [.macOS(.v12)],
    targets: [
        .executableTarget(
            name: "SnowAccumulationCA",
            path: "Sources/SnowAccumulationCA"
        )
    ]
)
