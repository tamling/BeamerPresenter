import SwiftUI
import AppKit

/// Shared state for the unified (title-bar-less) window look.
///
/// The presenter window hides the system title bar and lets its content run
/// all the way to the window's top edge — the way Safari, Vivaldi, or the
/// Claude app look. The traffic lights then float over the content's
/// top-left corner, so views keep that corner clear. In full screen the
/// lights are gone and the reserved room collapses to zero.
final class WindowChrome: ObservableObject {
    static let shared = WindowChrome()

    /// Vertical room for the (invisible) title bar, which stays draggable.
    @Published private(set) var titlebarHeight: CGFloat = 28
    /// Horizontal room the traffic lights need at the top-left.
    @Published private(set) var trafficLightInset: CGFloat = 76

    private static let barHeight: CGFloat = 28
    private static let lightsWidth: CGFloat = 76

    func setFullScreen(_ fullScreen: Bool) {
        titlebarHeight = fullScreen ? 0 : Self.barHeight
        trafficLightInset = fullScreen ? 0 : Self.lightsWidth
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
