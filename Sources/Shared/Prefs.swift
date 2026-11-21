import Foundation

/// The UserDefaults keys the app reads and writes, in one place.
///
/// Shared rather than per-platform on purpose: these are strings, and a string
/// that drifts between two copies does not fail to build — it quietly reads a
/// setting nobody wrote. Keys the iPad target does not use yet still belong
/// here, so the vocabulary stays one list.
enum Prefs {
    static let startBlackedOut = "startBlackedOut"
    static let blackScreenMessage = "blackScreenMessage"
    static let blackScreenImage = "blackScreenImage"
    static let showStatusItem = "showStatusItem"
    static let backgroundMode = "backgroundMode"
    static let audienceFullscreen = "audienceFullscreen"
    /// Open a slide from the thumbnail strip / overview with a double click
    /// instead of a single click.
    static let doubleClickSlides = "doubleClickSlides"
    /// Thumbnail height of the bottom slide strip (shared by the strip and the
    /// drag handle in the presenter view).
    static let thumbStripHeight = "thumbStripHeight"
    /// Console appearance: "night" (dark, default) or "paper" (light).
    static let appearance = "appearance"
}
