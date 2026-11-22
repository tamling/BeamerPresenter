// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "AlbumArtworkSaver",
    platforms: [.macOS(.v13)],
    targets: [
        .target(name: "AlbumArtworkCore"),
        .testTarget(name: "AlbumArtworkCoreTests", dependencies: ["AlbumArtworkCore"]),
    ]
)
