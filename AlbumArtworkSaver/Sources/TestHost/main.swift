import AppKit

// The TestHost shows the screensaver's view in a plain window, so the wall can
// be worked on without waiting for the screensaver. It runs outside the
// screensaver's sandbox and never replaces a test in the real screensaver.
//
//   ./build/TestHost                  a 1280×720 window running AlbumArtworkView
//   ./build/TestHost --covers <dir>   the same wall, with every *.jpg, *.jpeg and
//                                     *.png in <dir> as an album
//   ./build/TestHost --music <dir> [--cache <dir>]
//                                     the real wall: the music folder <dir> is
//                                     scanned into the cache folder (default: the
//                                     screensaver's), new albums join as found
//   ./build/TestHost --scan <dir> --cache <dir>
//                                     no window: scans <dir> into the cache once,
//                                     prints "outcome=… albums=… files=… new=…"
//                                     and exits 0

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
    FileHandle.standardError.write(Data("""
        usage: TestHost [--covers <dir> | --music <dir> [--cache <dir>] | --scan <dir> --cache <dir>]

        """.utf8))
    exit(2)
}

enum Mode {
    /// The view in a window, showing what the override names.
    case window(HostOverride?)
    /// One scan, no window.
    case scan(music: URL, cache: URL)
}

/// The command line as what to run.
func mode(from arguments: [String]) -> Mode {
    var arguments = arguments[...]
    var covers: URL?
    var music: URL?
    var scan: URL?
    var cache: URL?
    func folder(after option: String) -> URL {
        guard let path = arguments.popFirst() else { fail("\(option) needs a folder") }
        return URL(fileURLWithPath: path, isDirectory: true)
    }
    while let argument = arguments.popFirst() {
        switch argument {
        case "--covers":
            let url = folder(after: argument)
            var isFolder: ObjCBool = false
            guard FileManager.default.fileExists(atPath: url.path, isDirectory: &isFolder), isFolder.boolValue else {
                fail("--covers \(url.path): no such folder")
            }
            covers = url
        // A music folder that is not there is fine: the scan says so.
        case "--music": music = folder(after: argument)
        case "--scan": scan = folder(after: argument)
        case "--cache": cache = folder(after: argument)
        default:
            fail("unknown argument \(argument)")
        }
    }
    if [covers, music, scan].compactMap({ $0 }).count > 1 { fail("--covers, --music and --scan go alone") }
    if let scan {
        guard let cache else { fail("--scan needs --cache <dir>") }
        return .scan(music: scan, cache: cache)
    }
    if let music { return .window(.music(music, cache: cache ?? CoverCache.defaultDirectory)) }
    if cache != nil { fail("--cache goes with --music or --scan") }
    return .window(covers.map(HostOverride.covers))
}

/// Scans once, in the foreground, and prints the summary.
func runScan(music: URL, cache: URL) -> Never {
    let summary = LibraryScanner(root: music, cache: CoverCache(directory: cache))
        .run(isCancelled: { false }, onNewAlbums: { _ in })
    print("outcome=\(summary.outcome.rawValue) albums=\(summary.albums) files=\(summary.files) new=\(summary.newAlbums)")
    exit(0)
}

// Top-level code is nonisolated, but AppKit is main-actor-only; this runs on
// the main thread, so say so instead of fighting the concurrency checker.
switch mode(from: Array(CommandLine.arguments.dropFirst())) {
case let .scan(music, cache):
    runScan(music: music, cache: cache)
case let .window(host):
    MainActor.assumeIsolated {
        AlbumArtworkView.hostOverride = host
        let app = NSApplication.shared
        let delegate = TestHostDelegate()
        app.delegate = delegate
        app.setActivationPolicy(.regular)
        app.run()
    }
}
