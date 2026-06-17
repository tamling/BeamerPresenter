import AppKit

// AppKit bootstrap. Running as a Swift Package executable is the quickest way to
// iterate (`swift run`); for a distributable .app, wrap these sources in an
// Xcode app target (see README).
let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.regular)
app.run()
