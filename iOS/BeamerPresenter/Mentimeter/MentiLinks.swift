import Foundation

/// One recently presented Mentimeter, for quick relaunch.
struct MentiLink: Identifiable, Hashable {
    let title: String
    let url: URL
    var id: URL { url }
}

/// Remembers the menti pages you presented, so you can relaunch a poll in one
/// tap at the start of the next lecture. Stored as "title\turl" in UserDefaults.
enum MentiLinks {
    private static let key = "mentiRecentLinks"
    static let didChange = Notification.Name("MentiLinksDidChange")

    static func add(title: String, url: URL) {
        let name = title.trimmingCharacters(in: .whitespacesAndNewlines)
        let link = MentiLink(title: name.isEmpty ? url.absoluteString : name, url: url)
        var items = load().filter { $0.url != url }
        items.insert(link, at: 0)
        UserDefaults.standard.set(items.prefix(12).map { "\($0.title)\t\($0.url.absoluteString)" }, forKey: key)
        NotificationCenter.default.post(name: didChange, object: nil)
    }

    static func load() -> [MentiLink] {
        (UserDefaults.standard.stringArray(forKey: key) ?? []).compactMap { line in
            let parts = line.split(separator: "\t", maxSplits: 1).map(String.init)
            guard parts.count == 2, let url = URL(string: parts[1]) else { return nil }
            return MentiLink(title: parts[0], url: url)
        }
    }

    static func remove(_ url: URL) {
        let kept = load().filter { $0.url != url }
        UserDefaults.standard.set(kept.map { "\($0.title)\t\($0.url.absoluteString)" }, forKey: key)
        NotificationCenter.default.post(name: didChange, object: nil)
    }
}
