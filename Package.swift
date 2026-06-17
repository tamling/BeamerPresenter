// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "BeamerPresenter",
    platforms: [.macOS(.v13)],
    targets: [
        .executableTarget(
            name: "BeamerPresenter",
            path: "Sources/BeamerPresenter"
        )
    ]
)
