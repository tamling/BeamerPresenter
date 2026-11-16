import SwiftUI
import AppKit

/// Shared state for the unified (title-bar-less) window look.
///
/// The presenter window hides the system title bar and lets its content run
/// all the way to the window's top edge — the way Safari, Vivaldi, or the
/// Claude app look. The traffic lights then float over the content's
/// top-left corner, so views keep that corner clear. In full screen the
/// vertical room collapses, but the corner stays reserved: full screen only
/// auto-hides the lights, and pointing at the top edge slides them back over
/// the content.
final class WindowChrome: ObservableObject {
    static let shared = WindowChrome()

    /// Vertical room for the (invisible) title bar, which stays draggable.
    @Published private(set) var titlebarHeight: CGFloat = 28
    /// Horizontal room the traffic lights need at the top-left.
    @Published private(set) var trafficLightInset: CGFloat = WindowChrome.lightsWidth
    /// Whether the presenter window is in macOS full screen. The brand border
    /// reads this: a window has rounded corners to follow, a full screen has
    /// square ones, and a rounded border on a square screen leaves four gaps.
    @Published private(set) var isFullScreen = false

    private static let barHeight: CGFloat = 28
    private static let lightsWidth: CGFloat = 76

    func setFullScreen(_ fullScreen: Bool) {
        isFullScreen = fullScreen
        // Only the height collapses — the content legitimately extends to the
        // top edge there. `trafficLightInset` stays, so the revealed title bar
        // can't drop the lights onto the control bar's first key.
        titlebarHeight = fullScreen ? 0 : Self.barHeight
    }

    /// Gives a window the unified look: no title text, transparent bar, and
    /// content extending beneath it.
    static func unify(_ window: NSWindow) {
        window.styleMask.insert(.fullSizeContentView)
        window.titlebarAppearsTransparent = true
        window.titleVisibility = .hidden
        window.titlebarSeparatorStyle = .none
    }
}
