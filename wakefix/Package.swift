// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "XeneonWakeFix",
    platforms: [.macOS(.v13)],
    targets: [
        .executableTarget(
            name: "XeneonWakeFix",
            path: "Sources/XeneonWakeFix"
        )
    ]
)
