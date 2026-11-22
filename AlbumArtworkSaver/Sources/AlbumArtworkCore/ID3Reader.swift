import Foundation

struct TrackTags: Equatable {
    var album: String?
    var albumArtist: String?
    var artist: String?
    var picture: Data?
    var pictureMIME: String?
}

/// Minimal ID3v2.2–2.4 reader for album/artist text frames and cover art.
/// Operates on untrusted bytes: every length is checked against the remaining data.
enum ID3Reader {
    static let headerLength = 10

    /// Total tag length in bytes (header + body + optional footer), or nil if `header` is not a supported ID3v2 header.
    static func tagLength(header: Data) -> Int? {
        let h = Array(header.prefix(headerLength))
        guard h.count == headerLength, h[0] == 0x49, h[1] == 0x44, h[2] == 0x33,
              (2...4).contains(h[3]), let size = syncSafe(h[6..<10]) else { return nil }
        let footer = h[3] == 4 && h[5] & 0x10 != 0
        return size + headerLength + (footer ? 10 : 0)
    }

    static func parse(_ tag: Data) -> TrackTags? {
        let bytes = Array(tag)
        guard bytes.count >= headerLength, tagLength(header: Data(bytes[0..<headerLength])) != nil,
              let size = syncSafe(bytes[6..<10]) else { return nil }
        let version = bytes[3], flags = bytes[5]
        if version == 2 && flags & 0x40 != 0 { return nil }  // compressed v2.2 tag
        var body = Array(bytes[headerLength..<min(bytes.count, headerLength + size)])
        let tagUnsync = flags & 0x80 != 0
        if tagUnsync && version != 4 { body = unsynchronise(body) }
        var pos = 0
        if flags & 0x40 != 0 {
            if version == 3, body.count >= 4 {
                let ext = body[0..<4].reduce(0) { $0 << 8 | Int($1) }
                pos = 4 + ext
            } else if version == 4, let ext = syncSafe(body.prefix(4)) {
                pos = ext
            } else {
                return TrackTags()
            }
        }

        let idLength = version == 2 ? 3 : 4
        let frameHeader = version == 2 ? 6 : 10
        var tags = TrackTags()
        var front: (Data, String?)?
        var first: (Data, String?)?

        while pos <= body.count - frameHeader, body[pos] != 0 {
            let id = String(decoding: body[pos..<pos + idLength], as: UTF8.self)
            let sizeBytes = body[pos + idLength..<pos + idLength + (version == 2 ? 3 : 4)]
            let frameFlags: [UInt8] = version == 2 ? [0, 0] : Array(body[pos + 8..<pos + 10])
            let start = pos + frameHeader
            guard let size = frameSize(sizeBytes, version: version, start: start, in: body),
                  size <= body.count - start else { break }
            pos = start + size
            var content = Array(body[start..<pos])

            // Skipped: compressed and encrypted frames. Dropped: the grouping
            // identity byte, then (v2.4) the data length indicator.
            if version == 3 {
                if frameFlags[1] & 0xC0 != 0 { continue }
                if frameFlags[1] & 0x20 != 0 {
                    guard !content.isEmpty else { continue }
                    content.removeFirst()
                }
            }
            if version == 4 {
                if frameFlags[1] & 0x0C != 0 { continue }
                if frameFlags[1] & 0x40 != 0 {
                    guard !content.isEmpty else { continue }
                    content.removeFirst()
                }
                if frameFlags[1] & 0x01 != 0 {
                    guard content.count >= 4 else { continue }
                    content.removeFirst(4)
                }
                if frameFlags[1] & 0x02 != 0 || tagUnsync { content = unsynchronise(content) }
            }

            switch id {
            case "TALB", "TAL": if tags.album == nil { tags.album = text(content) }
            case "TPE2", "TP2": if tags.albumArtist == nil { tags.albumArtist = text(content) }
            case "TPE1", "TP1": if tags.artist == nil { tags.artist = text(content) }
            case "APIC", "PIC":
                guard first == nil || front == nil,
                      let (type, mime, data) = picture(content, legacy: id == "PIC") else { continue }
                if first == nil { first = (data, mime) }
                if type == 3 && front == nil { front = (data, mime) }
            default: break
            }
        }
        if let chosen = front ?? first {
            tags.picture = chosen.0
            tags.pictureMIME = chosen.1
        }
        return tags
    }

    // MARK: - Helpers

    /// A frame's size from its header. v2.4 sizes are sync-safe, but old
    /// iTunes versions wrote plain integers: the plain reading is taken when
    /// the sync-safe one is no number or ends where no frame follows, and the
    /// plain one does end where one follows (as mutagen does).
    private static func frameSize(_ bytes: ArraySlice<UInt8>, version: UInt8, start: Int, in body: [UInt8]) -> Int? {
        let plain = bytes.reduce(0) { $0 << 8 | Int($1) }
        guard version == 4 else { return plain }
        let standard = syncSafe(bytes)
        if let standard, endsFrame(at: start + standard, in: body) { return standard }
        if endsFrame(at: start + plain, in: body) { return plain }
        return standard
    }

    /// Whether a v2.3/2.4 frame can end at `end`: the tag ends there, or
    /// padding (zeros) or another frame's ID (A–Z, 0–9) follows.
    private static func endsFrame(at end: Int, in body: [UInt8]) -> Bool {
        guard end <= body.count else { return false }
        if body[end..<min(end + 10, body.count)].allSatisfy({ $0 == 0 }) { return true }
        guard end + 4 <= body.count else { return false }
        return body[end..<end + 4].allSatisfy { (0x41...0x5A).contains($0) || (0x30...0x39).contains($0) }
    }

    private static func syncSafe<S: Sequence>(_ bytes: S) -> Int? where S.Element == UInt8 {
        var value = 0
        var count = 0
        for byte in bytes {
            guard byte < 0x80 else { return nil }
            value = value << 7 | Int(byte)
            count += 1
        }
        return count == 4 ? value : nil
    }

    private static func unsynchronise(_ bytes: [UInt8]) -> [UInt8] {
        var out: [UInt8] = []
        out.reserveCapacity(bytes.count)
        var i = 0
        while i < bytes.count {
            out.append(bytes[i])
            if bytes[i] == 0xFF, i + 1 < bytes.count, bytes[i + 1] == 0 { i += 1 }
            i += 1
        }
        return out
    }

    /// Finds the terminator at or after `from`; returns (end of text, index after terminator).
    private static func terminator(_ bytes: [UInt8], from: Int, encoding: UInt8) -> (end: Int, next: Int) {
        if encoding == 1 || encoding == 2 {
            var i = from
            while i + 1 < bytes.count {
                if bytes[i] == 0 && bytes[i + 1] == 0 { return (i, i + 2) }
                i += 2
            }
        } else if let i = bytes[from...].firstIndex(of: 0) {
            return (i, i + 1)
        }
        return (bytes.count, bytes.count)
    }

    private static func decode(_ bytes: ArraySlice<UInt8>, encoding: UInt8) -> String? {
        var data = Array(bytes)
        let string: String?
        switch encoding {
        case 0: string = String(data: Data(data), encoding: .isoLatin1)
        case 3: string = String(data: Data(data), encoding: .utf8)
        case 1, 2:
            if data.count % 2 == 1 { data.removeLast() }
            var bigEndian = encoding == 2
            if encoding == 1, data.count >= 2 {
                if data[0] == 0xFE && data[1] == 0xFF { bigEndian = true; data.removeFirst(2) }
                else if data[0] == 0xFF && data[1] == 0xFE { data.removeFirst(2) }
            }
            string = String(data: Data(data), encoding: bigEndian ? .utf16BigEndian : .utf16LittleEndian)
        default: string = nil
        }
        let trimmed = string?.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed?.isEmpty == false ? trimmed : nil
    }

    private static func text(_ content: [UInt8]) -> String? {
        guard let encoding = content.first else { return nil }
        return decode(content[1...][..<terminator(content, from: 1, encoding: encoding).end], encoding: encoding)
    }

    private static func picture(_ c: [UInt8], legacy: Bool) -> (type: UInt8, mime: String?, data: Data)? {
        guard let encoding = c.first else { return nil }
        var pos = 1
        let mime: String?
        if legacy {
            guard c.count >= 5 else { return nil }
            switch String(decoding: c[1..<4], as: UTF8.self).uppercased() {
            case "JPG": mime = "image/jpeg"
            case "PNG": mime = "image/png"
            case "-->": return nil
            default: mime = nil
            }
            pos = 4
        } else {
            let t = terminator(c, from: 1, encoding: 0)
            let value = String(data: Data(c[1..<t.end]), encoding: .isoLatin1)?.trimmingCharacters(in: .whitespaces)
            if value == "-->" { return nil }
            mime = value?.isEmpty == false ? value : nil
            pos = t.next
        }
        guard pos < c.count else { return nil }
        let type = c[pos]
        let dataStart = terminator(c, from: pos + 1, encoding: encoding).next
        guard dataStart < c.count else { return nil }
        return (type, mime, Data(c[dataStart...]))
    }
}
