import AppKit

// The TestHost shows the screensaver's view in a plain window, so the wall can
// be worked on without waiting for the screensaver. It runs outside the
// screensaver's sandbox and never replaces a test in the real screensaver.
//
//   ./build/TestHost          a 1280×720 window running AlbumArtworkView

final class TestHostDelegate: NSObject, NSApplicationDelegate {
    private var window: NSWindow?

    func applicationDidFinishLaunching(_ notification: Notification) {
        let frame = NSRect(x: 0, y: 0, width: 1280, height: 720)
        guard let view = AlbumArtworkView(frame: frame, isPreview: false) else {
            FileHandle.standardError.write(Data("✗ AlbumArtworkView(frame:isPreview:) returned nil\n".utf8))
            exit(1)
        }
        let window = NSWindow(contentRect: frame,
                              styleMask: [.titled, .closable, .miniaturizable, .resizable],
                              backing: .buffered,
                              defer: false)
        window.title = "AlbumArtwork TestHost"
        window.isReleasedWhenClosed = false
        window.contentView = view
        window.center()
        window.makeKeyAndOrderFront(nil)
        self.window = window
        view.startAnimation()
        NSApp.activate(ignoringOtherApps: true)
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        true
    }
}

// Top-level code is nonisolated, but AppKit is main-actor-only; this runs on
// the main thread, so say so instead of fighting the concurrency checker.
MainActor.assumeIsolated {
    let app = NSApplication.shared
    let delegate = TestHostDelegate()
    app.delegate = delegate
    app.setActivationPolicy(.regular)
    app.run()
}
