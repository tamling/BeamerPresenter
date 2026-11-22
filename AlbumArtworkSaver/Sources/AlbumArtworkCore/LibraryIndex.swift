import Foundation

struct FileStamp: Codable, Equatable {
    var size: Int64
    var modified: Double
}

struct IndexedFile: Codable, Equatable {
    var stamp: FileStamp
    /// `nil` = no usable picture.
    var album: AlbumID?
}

struct IndexedAlbum: Codable, Equatable {
    var fingerprint: UInt64
    var title: String
    var artist: String

    init(fingerprint: UInt64, title: String, artist: String) {
        self.fingerprint = fingerprint
        self.title = title
        self.artist = artist
    }

    // In JSON the fingerprint is 16 lowercase hex digits: a number above 2^53
    // need not survive every JSON decoder (Foundation on macOS 13 goes through
    // NSNumber), and a lost digit would break the dedup of identical pictures.
    private enum CodingKeys: String, CodingKey {
        case fingerprint, title, artist
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let hex = try container.decode(String.self, forKey: .fingerprint)
        let digits = hex.utf8
        guard digits.count == 16, digits.allSatisfy({ (0x30...0x39).contains($0) || (0x61...0x66).contains($0) }),
              let fingerprint = UInt64(hex, radix: 16)
        else {
            throw DecodingError.dataCorruptedError(forKey: .fingerprint, in: container,
                                                   debugDescription: "not 16 lowercase hex digits: \(hex)")
        }
        self.fingerprint = fingerprint
        title = try container.decode(String.self, forKey: .title)
        artist = try container.decode(String.self, forKey: .artist)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        let hex = String(fingerprint, radix: 16)
        try container.encode(String(repeating: "0", count: 16 - hex.count) + hex, forKey: .fingerprint)
        try container.encode(title, forKey: .title)
        try container.encode(artist, forKey: .artist)
    }
}

struct LibraryIndex: Codable, Equatable {
    static let currentVersion = 1
    var version: Int
    /// Keyed by path relative to the music folder.
    var files: [String: IndexedFile]
    var albums: [AlbumID: IndexedAlbum]
    var lastCompleteScan: Date?

    init() {
        version = Self.currentVersion
        files = [:]
        albums = [:]
        lastCompleteScan = nil
    }

    var albumIDs: [AlbumID] { albums.keys.sorted() }
}
