// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "SnowAccumulation",
    platforms: [.macOS(.v12)],
    targets: [
        .executableTarget(
            name: "SnowAccumulation",
            path: "Sources/SnowAccumulation"
        )
    ]
)
