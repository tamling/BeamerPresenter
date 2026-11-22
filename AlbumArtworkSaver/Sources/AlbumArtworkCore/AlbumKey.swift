import Foundation

typealias AlbumID = String

enum AlbumKey {
    /// Lowercased, whitespace runs collapsed to one space, trimmed, in Unicode
    /// NFC: the key hashes the UTF-8 bytes, and "é" may come as one code point
    /// or as "e" plus an accent.
    static func normalize(_ s: String) -> String {
        s.lowercased().split(whereSeparator: { $0.isWhitespace }).joined(separator: " ")
            .precomposedStringWithCanonicalMapping
    }

    /// Albums with a title are keyed by artist + title; untitled ones by their picture fingerprint.
    static func make(album: String?, albumArtist: String?, artist: String?, pictureFingerprint: UInt64) -> AlbumID {
        let title = normalize(album ?? "")
        if title.isEmpty { return "i-" + hex(pictureFingerprint) }
        let who = [albumArtist, artist].lazy.map { normalize($0 ?? "") }.first { !$0.isEmpty } ?? ""
        return "a-" + hex(Fingerprint.fnv1a64(Data((who + "\u{1F}" + title).utf8)))
    }

    private static func hex(_ value: UInt64) -> String {
        let s = String(value, radix: 16)
        return String(repeating: "0", count: 16 - s.count) + s
    }
}
