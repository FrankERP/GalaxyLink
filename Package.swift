// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "GalaxyLink",
    platforms: [.macOS(.v14)],
    targets: [
        .target(name: "CGVirtualDisplayShim", publicHeadersPath: "include"),
        .executableTarget(
            name: "GalaxyLink",
            dependencies: ["CGVirtualDisplayShim"],
            resources: [.copy("Resources/web")]
        ),
        .testTarget(name: "GalaxyLinkTests", dependencies: ["GalaxyLink"]),
    ]
)
