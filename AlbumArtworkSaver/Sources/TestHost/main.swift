import AppKit

// The TestHost shows the screensaver's view in a plain window, so the wall can
// be worked on without waiting for the screensaver. It runs outside the
// screensaver's sandbox and never replaces a test in the real screensaver.
//
//   ./build/TestHost                  a 1280×720 window running AlbumArtworkView
//   ./build/TestHost --covers <dir>   the same wall, with every *.jpg, *.jpeg and
//                                     *.png in <dir> as an album

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

func fail(_ message: String) -> Never {
    FileHandle.standardError.write(Data("✗ \(message)\n".utf8))
    FileHandle.standardError.write(Data("usage: TestHost [--covers <dir>]\n".utf8))
    exit(2)
}

/// The command line as the host override for the view.
func hostOverride(from arguments: [String]) -> HostOverride? {
    var arguments = arguments[...]
    var result: HostOverride?
    while let argument = arguments.popFirst() {
        switch argument {
        case "--covers":
            guard let path = arguments.popFirst() else { fail("--covers needs a folder") }
            var isFolder: ObjCBool = false
            guard FileManager.default.fileExists(atPath: path, isDirectory: &isFolder), isFolder.boolValue else {
                fail("--covers \(path): no such folder")
            }
            result = .covers(URL(fileURLWithPath: path, isDirectory: true))
        default:
            fail("unknown argument \(argument)")
        }
    }
    return result
}

// Top-level code is nonisolated, but AppKit is main-actor-only; this runs on
// the main thread, so say so instead of fighting the concurrency checker.
MainActor.assumeIsolated {
    AlbumArtworkView.hostOverride = hostOverride(from: Array(CommandLine.arguments.dropFirst()))
    let app = NSApplication.shared
    let delegate = TestHostDelegate()
    app.delegate = delegate
    app.setActivationPolicy(.regular)
    app.run()
}
