// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "XeneonUI",
    platforms: [.macOS(.v13)],
    targets: [
        .executableTarget(
            name: "XeneonUI",
            path: "Sources/XeneonUI"
        )
    ]
)
