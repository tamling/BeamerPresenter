import AppKit
import ScreenSaver

/// What the TestHost shows instead of the folder chosen in the screensaver's
/// options. The real screensaver never sets it.
enum HostOverride {
    /// A folder of cover images; each file name without its extension is an album.
    case covers(URL)
    /// A music folder, scanned into the given cache folder.
    case music(URL, cache: URL)
}

/// The screensaver's principal class (`NSPrincipalClass` in Info.plist): a
/// black, layer-backed view that the cover wall will draw into.
@objc(AlbumArtworkView)
final class AlbumArtworkView: ScreenSaverView {
    /// Set by the TestHost before it creates the view; `nil` in the real screensaver.
    static var hostOverride: HostOverride?

    override init?(frame: NSRect, isPreview: Bool) {
        super.init(frame: frame, isPreview: isPreview)
        configure()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        configure()
    }

    // The view only shows its layer, so AppKit asks for updateLayer() instead
    // of drawing a full-screen backing store.
    override var wantsUpdateLayer: Bool { true }

    override func updateLayer() {
        layer?.backgroundColor = NSColor.black.cgColor
    }

    private func configure() {
        animationTimeInterval = 1.0 / 60
        wantsLayer = true
    }
}
