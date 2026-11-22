// Loads a built .saver the way the screensaver engine does — NSBundle, then its
// principal class — and makes one view from it:
//
//   swift Scripts/load-saver.swift build/AlbumArtwork.saver
//
// Prints "OK <class name>" and exits 0, or explains on stderr and exits 1.
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
    print("OK \(NSStringFromClass(type(of: view)))")
}
