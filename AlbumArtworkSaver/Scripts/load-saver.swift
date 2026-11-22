// Loads a built .saver the way the screensaver engine does — NSBundle, then its
// principal class — and makes one view from it:
//
//   swift Scripts/load-saver.swift build/AlbumArtwork.saver
//
// The view must offer its options sheet, and make its window, as System
// Settings asks for it. Prints "OK <class name> (options sheet <w>×<h>)" and
// exits 0, or explains on stderr and exits 1.
import AppKit
import ScreenSaver

func fail(_ message: String) -> Never {
    FileHandle.standardError.write(Data("✗ \(message)\n".utf8))
    exit(1)
}

let arguments = CommandLine.arguments.dropFirst()
guard arguments.count == 1, let path = arguments.first else {
    fail("usage: swift Scripts/load-saver.swift <path/to/Name.saver>")
}

// Top-level code is nonisolated, but views are main-actor-only; this runs on
// the main thread.
MainActor.assumeIsolated {
    // The options sheet is a window; windows want an application object.
    _ = NSApplication.shared
    guard let bundle = Bundle(path: path) else {
        fail("\(path) is not a bundle")
    }
    do {
        try bundle.loadAndReturnError()
    } catch {
        fail("cannot load \(path): \(error)")
    }
    guard let principal = bundle.principalClass else {
        fail("\(path) has no principal class (NSPrincipalClass)")
    }
    guard let saverClass = principal as? ScreenSaverView.Type else {
        fail("principal class \(NSStringFromClass(principal)) is not a ScreenSaverView subclass")
    }
    let frame = NSRect(x: 0, y: 0, width: 400, height: 225)
    guard let view = saverClass.init(frame: frame, isPreview: false) else {
        fail("\(NSStringFromClass(saverClass))(frame:isPreview:) returned nil")
    }
    guard view.hasConfigureSheet else {
        fail("\(NSStringFromClass(saverClass)).hasConfigureSheet is false")
    }
    guard let sheet = view.configureSheet else {
        fail("\(NSStringFromClass(saverClass)).configureSheet returned nil")
    }
    let size = sheet.frame.size
    guard size.width > 0, size.height > 0 else {
        fail("the options sheet has no size (\(size.width)×\(size.height))")
    }
    print("OK \(NSStringFromClass(type(of: view))) (options sheet \(Int(size.width))×\(Int(size.height)))")
}
