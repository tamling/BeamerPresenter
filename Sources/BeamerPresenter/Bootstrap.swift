import AppKit

// AppKit bootstrap. Running as a Swift Package executable is the quickest way to
// iterate (`swift run`); for a distributable .app, wrap these sources in an
// Xcode app target (see README).
//
// The entry point is `@MainActor` so it can construct the (main-actor-isolated)
// `AppDelegate`. A plain top-level `main.swift` is nonisolated, which the Swift
// concurrency checker rejects, so we use an explicit `@main` type instead.
@main
enum Bootstrap {
    @MainActor
    static func main() {
        let app = NSApplication.shared
        let delegate = AppDelegate()
        app.delegate = delegate
        app.setActivationPolicy(.regular)
        app.run()
    }
}
