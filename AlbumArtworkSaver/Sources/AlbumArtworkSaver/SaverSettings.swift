import Foundation
import os
import ScreenSaver

/// What the options sheet sets, kept in `ScreenSaverDefaults` under the bundle
/// ID: the wall's rows and interval, and the music folder as a bookmark and as
/// a plain path (see `FolderAccess`).
struct SaverSettings {
    static let moduleName = "app.beamerpresenter.AlbumArtworkSaver"

    private enum Key {
        static let rows = "rows"
        static let interval = "interval"
        static let folderBookmark = "folderBookmark"
        static let folderPath = "folderPath"
    }

    var wall: WallSettings
    var folderBookmark: Data?
    var folderPath: String?

    init(wall: WallSettings = WallSettings(), folderBookmark: Data? = nil, folderPath: String? = nil) {
        self.wall = wall
        self.folderBookmark = folderBookmark
        self.folderPath = folderPath
    }

    /// The saved settings; the defaults (6 rows, 3 s, no folder) for what was
    /// never saved. Values out of range are clamped.
    static func load() -> SaverSettings {
        guard let defaults = defaults() else { return SaverSettings() }
        // Another process (System Settings' preview) may have saved since.
        defaults.synchronize()
        let standard = WallSettings()
        let rows = (defaults.object(forKey: Key.rows) as? NSNumber)?.intValue ?? standard.rows
        let interval = (defaults.object(forKey: Key.interval) as? NSNumber)?.doubleValue ?? standard.interval
        let path = defaults.string(forKey: Key.folderPath)
        return SaverSettings(wall: WallSettings(rows: rows, interval: interval),
                             folderBookmark: defaults.data(forKey: Key.folderBookmark),
                             folderPath: path?.isEmpty == false ? path : nil)
    }

    func save() {
        guard let defaults = Self.defaults() else { return }
        defaults.set(wall.rows, forKey: Key.rows)
        defaults.set(wall.interval, forKey: Key.interval)
        defaults.set(folderBookmark, forKey: Key.folderBookmark)
        defaults.set(folderPath, forKey: Key.folderPath)
        defaults.synchronize()
    }

    /// Saves only the folder, so a bookmark renewed off the main thread does
    /// not undo rows or an interval saved meanwhile.
    func saveFolder() {
        guard let defaults = Self.defaults() else { return }
        defaults.set(folderBookmark, forKey: Key.folderBookmark)
        defaults.set(folderPath, forKey: Key.folderPath)
        defaults.synchronize()
    }

    private static func defaults() -> ScreenSaverDefaults? {
        let defaults = ScreenSaverDefaults(forModuleWithName: moduleName)
        if defaults == nil {
            Logger.scan.error("settings: no ScreenSaverDefaults for \(moduleName, privacy: .public)")
        }
        return defaults
    }
}
