// swift-tools-version: 5.9
import PackageDescription

// BeamerCore is Foundation-only, so it (and its tests) also build on Linux,
// where CI runs `swift test`. The app itself needs AppKit and is macOS-only.
var targets: [Target] = [
    .target(
        name: "BeamerCore",
        path: "Sources/BeamerCore"
    ),
    .testTarget(
        name: "BeamerCoreTests",
        dependencies: ["BeamerCore"],
        path: "Tests/BeamerCoreTests"
    ),
]

#if !os(Linux)
targets.append(
    .executableTarget(
        name: "BeamerPresenter",
        dependencies: ["BeamerCore"],
        path: "Sources/BeamerPresenter"
    )
)
#endif

let package = Package(
    name: "BeamerPresenter",
    platforms: [.macOS(.v13)],
    targets: targets
)
