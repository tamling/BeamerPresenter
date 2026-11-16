// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "BeamerPresenter",
    platforms: [.macOS(.v13)],
    targets: [
        .executableTarget(
            name: "BeamerPresenter",
            // Shared/ holds what the macOS and iPad targets both compile. It is
            // listed as sources rather than split into its own module so the
            // types stay internal — making them public to cross a module
            // boundary would be a wide change for no gain here.
            path: "Sources",
            sources: ["BeamerPresenter", "Shared"]
        )
    ]
)
