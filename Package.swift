// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "MorningCheckCore",
    platforms: [.macOS(.v14), .iOS(.v18), .watchOS(.v11)],
    products: [.library(name: "MorningCheckCore", targets: ["MorningCheckCore"])],
    targets: [
        .target(name: "MorningCheckCore", path: "Core"),
        .testTarget(name: "MorningCheckCoreTests", dependencies: ["MorningCheckCore"], path: "Tests/Core")
    ]
)
