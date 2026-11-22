import Foundation

/// Whether the chosen music folder can be read right now.
enum FolderStatus: Equatable {
    case notChosen, available, unavailable
}

/// The German texts of the options sheet's status line and of the hint on a
/// black wall. Numbers are grouped with dots whatever the locale (1.234).
enum StatusText {
    /// The options sheet's status line, e.g. "1.234 Alben · zuletzt eingelesen vor 2 Std.".
    static func make(albumCount: Int, lastCompleteScan: Date?, now: Date, folder: FolderStatus,
                     isScanning: Bool) -> String {
        let albums = albumsText(albumCount)
        switch folder {
        case .notChosen:
            return "Kein Musikordner gewählt"
        case .unavailable:
            return "Musikordner nicht erreichbar · zeige \(albums) aus dem Zwischenspeicher"
        case .available:
            if isScanning { return "\(albums) · lese gerade ein …" }
            guard let lastCompleteScan else { return "\(albums) · noch nicht eingelesen" }
            return "\(albums) · zuletzt eingelesen \(ago(now.timeIntervalSince(lastCompleteScan)))"
        }
    }

    /// The quiet line in the middle of a wall that cannot start yet, or nil
    /// when there is nothing to say. `needed` is the number of cells.
    static func hint(folder: FolderStatus, albumCount: Int, isScanning: Bool, needed: Int) -> String? {
        if folder == .notChosen { return "Musikordner in den Screensaver-Optionen wählen" }
        if isScanning, albumCount < needed { return "Lese Musik ein … \(albumsText(albumCount))" }
        if !isScanning, folder == .available, albumCount == 0 { return "Keine Cover gefunden" }
        return nil
    }

    /// `value` with a dot between each group of three digits.
    static func grouped(_ value: Int) -> String {
        var digits = String(value.magnitude)
        var groups: [Substring] = []
        while digits.count > 3 {
            groups.insert(digits.suffix(3), at: 0)
            digits.removeLast(3)
        }
        groups.insert(Substring(digits), at: 0)
        return (value < 0 ? "-" : "") + groups.joined(separator: ".")
    }

    private static func albumsText(_ count: Int) -> String {
        "\(grouped(count)) \(count == 1 ? "Album" : "Alben")"
    }

    /// How long ago, in whole units: "gerade eben", "vor 5 Min.", "vor 2 Std.", "vor 1 Tag", "vor 3 Tagen".
    private static func ago(_ seconds: TimeInterval) -> String {
        let minutes = Int((seconds / 60).rounded(.down))
        if minutes < 1 { return "gerade eben" }
        if minutes < 60 { return "vor \(minutes) Min." }
        let hours = minutes / 60
        if hours < 24 { return "vor \(hours) Std." }
        let days = hours / 24
        return days == 1 ? "vor 1 Tag" : "vor \(days) Tagen"
    }
}
