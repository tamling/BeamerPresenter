import Foundation

/// A command the remote (iPhone) sends to the presenter (iPad).
public enum RemoteCommand: String, Codable {
    case previous, next, blackout, toggleTimer, resetTimer
}

/// A snapshot the presenter pushes to the remote so it can mirror the talk.
public struct PresenterState: Codable, Equatable {
    public var title: String
    public var index: Int
    public var pageCount: Int
    public var note: String
    public var blackout: Bool
    public var timerRunning: Bool
    public var elapsed: Int

    public init(title: String, index: Int, pageCount: Int, note: String,
                blackout: Bool, timerRunning: Bool, elapsed: Int) {
        self.title = title
        self.index = index
        self.pageCount = pageCount
        self.note = note
        self.blackout = blackout
        self.timerRunning = timerRunning
        self.elapsed = elapsed
    }
}

/// The wire packet exchanged over the session (Codable is synthesised for the
/// enum's associated values).
public enum RemotePacket: Codable {
    case command(RemoteCommand)
    case state(PresenterState)
}

extension RemotePacket {
    /// Hard cap for one packet on the wire, both directions. Anything larger is
    /// dropped unread, so a hostile peer cannot make us decode megabytes of JSON.
    public static let maxPacketBytes = 64 * 1024

    /// Size-checked decode; a `.state` comes back already `sanitized()`.
    public static func decode(_ data: Data) -> RemotePacket? {
        guard data.count <= maxPacketBytes,
              let packet = try? JSONDecoder().decode(RemotePacket.self, from: data) else { return nil }
        if case .state(let s) = packet { return .state(s.sanitized()) }
        return packet
    }

    /// Encoded packet, or nil if it would exceed `maxPacketBytes`.
    public func encoded() -> Data? {
        guard let data = try? JSONEncoder().encode(self), data.count <= Self.maxPacketBytes else { return nil }
        return data
    }
}

extension PresenterState {
    public static let maxPageCount = 10_000
    public static let maxNoteLength = 20_000
    public static let maxTitleLength = 200
    /// Timer cap (100 days): `Int(Double(Int.max))` in the timer label would trap.
    public static let maxElapsed = 100 * 24 * 3600
    /// Byte budget for the note, so a note full of multi-byte characters still
    /// leaves the packet under `RemotePacket.maxPacketBytes` (JSON may escape
    /// some characters, hence the headroom).
    public static let maxNoteBytes = 24 * 1024

    /// Clamps every field to a range the UI can show safely (no `index + 1`
    /// overflow, no out-of-range page, no negative timer, bounded text).
    public func sanitized() -> PresenterState {
        var s = self
        s.pageCount = min(max(pageCount, 0), Self.maxPageCount)
        s.index = min(max(index, 0), max(s.pageCount - 1, 0))
        s.title = String(title.prefix(Self.maxTitleLength))
        s.note = Self.truncated(String(note.prefix(Self.maxNoteLength)), maxBytes: Self.maxNoteBytes)
        s.elapsed = min(max(elapsed, 0), Self.maxElapsed)
        return s
    }

    /// Longest prefix of `text` (whole characters) whose UTF-8 form fits `maxBytes`.
    public static func truncated(_ text: String, maxBytes: Int) -> String {
        guard text.utf8.count > maxBytes else { return text }
        var bytes = 0
        var end = text.startIndex
        for i in text.indices {
            let n = String(text[i]).utf8.count
            if bytes + n > maxBytes { break }
            bytes += n
            end = text.index(after: i)
        }
        return String(text[..<end])
    }
}

/// The presenter's pairing code: six random digits, compared in constant time.
public enum PairingCode {
    public static let length = 6

    public static func make() -> String {
        let s = String(Int.random(in: 0...999_999))
        return String(repeating: "0", count: length - s.count) + s
    }

    public static func isWellFormed(_ s: String) -> Bool {
        s.utf8.count == length && s.utf8.allSatisfy { (48...57).contains($0) }
    }

    /// Constant-time comparison: no early exit, so timing reveals nothing about
    /// how many leading digits were right.
    public static func matches(_ a: String, _ b: String) -> Bool {
        let x = Array(a.utf8), y = Array(b.utf8)
        var diff: UInt8 = x.count == y.count ? 0 : 1
        for i in 0..<max(x.count, y.count) {
            diff |= (i < x.count ? x[i] : 0) ^ (i < y.count ? y[i] : 0)
        }
        return diff == 0
    }
}
