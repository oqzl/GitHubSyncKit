// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "GitHubSyncKit",
    platforms: [.iOS(.v17), .macOS(.v14)],
    products: [
        .library(name: "GitHubSyncKit", targets: ["GitHubSyncKit"]),
        .library(name: "GitHubSyncKitUI", targets: ["GitHubSyncKitUI"])
    ],
    targets: [
        .target(name: "GitHubSyncKit"),
        .target(name: "GitHubSyncKitUI", dependencies: ["GitHubSyncKit"]),
        .testTarget(name: "GitHubSyncKitTests", dependencies: ["GitHubSyncKit"])
    ]
)
