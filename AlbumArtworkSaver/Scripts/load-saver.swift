// Loads a built .saver the way the screensaver engine does — NSBundle, then its
// principal class — and makes one view from it:
//
//   swift Scripts/load-saver.swift build/AlbumArtwork.saver
//
// The view must start and stop (stopping before its music folder is resolved,
// whose late result must then be let go of), offer its options sheet, make
// its window, and fill the sheet's status line once the folder is resolved in
// the background. A second view, started without a size and sized later,
// then sized anew, must lay its wall and hint out for each size. Prints
// "OK <class name> (options sheet <w>×<h>, status "<status line>", hint
// "<hint>" after a late size and a resize)" and exits 0, or explains on
// stderr and exits 1.
import AppKit
import QuartzCore
import ScreenSaver

func fail(_ message: String) -> Never {
    FileHandle.standardError.write(Data("✗ \(message)\n".utf8))
    exit(1)
}

/// Runs the main run loop, which delivers what the background queues send to
/// the main thread, until `done` or the time is up.
@MainActor
func runMainLoop(for seconds: TimeInterval, until done: () -> Bool = { false }) {
    let deadline = Date().addingTimeInterval(seconds)
    while !done(), Date() < deadline {
        RunLoop.main.run(until: Date().addingTimeInterval(0.05))
    }
}

/// The sheet's status line: the label that is neither a field name ("…:")
/// nor a slider's value.
@MainActor
func statusLine(in view: NSView) -> String? {
    for subview in view.subviews {
        if let label = subview as? NSTextField, !label.isEditable {
            let text = label.stringValue
            if !text.hasSuffix(":"), text.contains("Musikordner") || text.contains(" · ") { return text }
        }
        if let text = statusLine(in: subview) { return text }
    }
    return nil
}

/// The text of the hint the view shows in the middle of its wall, if any.
@MainActor
func hint(in view: NSView) -> CATextLayer? {
    view.layer?.sublayers?.lazy.compactMap { $0 as? CATextLayer }.first
}

/// The wall's black layer: the view layer's sublayer that is not the hint.
@MainActor
func wallLayer(in view: NSView) -> CALayer? {
    view.layer?.sublayers?.first { !($0 is CATextLayer) }
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
    view.startAnimation()
    view.stopAnimation()
    runMainLoop(for: 1)
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
    guard let content = sheet.contentView else { fail("the options sheet has no content") }
    runMainLoop(for: 10) { statusLine(in: content) != nil }
    guard let status = statusLine(in: content) else {
        fail("the options sheet's status line stayed empty: the folder was never resolved")
    }

    // A host that sizes the view only after starting it, and then sizes it anew.
    guard let late = saverClass.init(frame: .zero, isPreview: false) else {
        fail("\(NSStringFromClass(saverClass))(frame: .zero, isPreview:) returned nil")
    }
    late.startAnimation()
    runMainLoop(for: 2)
    if let text = hint(in: late)?.string { fail("a view without a size showed the hint \"\(text)\"") }
    late.setFrameSize(NSSize(width: 400, height: 225))
    runMainLoop(for: 10) { hint(in: late) != nil }
    guard let firstHint = hint(in: late), let hintText = firstHint.string as? String else {
        fail("a view sized after it started never showed its hint")
    }
    late.setFrameSize(NSSize(width: 800, height: 450))
    runMainLoop(for: 1)
    guard let wall = wallLayer(in: late), wall.frame == CGRect(x: 0, y: 0, width: 800, height: 450) else {
        fail("after a resize to 800×450 the wall is \(wallLayer(in: late).map { "\($0.frame)" } ?? "gone")")
    }
    guard let movedHint = hint(in: late), abs(movedHint.frame.midX - 400) < 1, abs(movedHint.frame.midY - 225) < 1
    else {
        fail("after a resize to 800×450 the hint is not centred: \(hint(in: late).map { "\($0.frame)" } ?? "gone")")
    }
    late.stopAnimation()
    print("""
        OK \(NSStringFromClass(type(of: view))) (options sheet \(Int(size.width))×\(Int(size.height)), \
        status "\(status)", hint "\(hintText)" after a late size and a resize)
        """)
}
