import Foundation

/// Reads the ID3v2 tag at the start of an MP3, and nothing else of the file.
/// The music folder is strictly read-only: the file is only ever opened for reading.
enum TagFileReader {
    /// A larger tag is not read at all: real covers are far smaller, and the
    /// size comes from untrusted bytes.
    static let maxTagBytes = 16 << 20

    enum Outcome: Equatable {
        /// The whole tag, header included; shorter than the header says when
        /// the file ends early.
        case tag(Data)
        /// The file has no ID3v2 tag, or one larger than `maxTagBytes`: it
        /// has no cover to offer, until it changes.
        case noTag
        /// The file could not be opened or read (permissions, a share that
        /// timed out, a disk that went away): try again next time.
        case unreadable
    }

    static func read(at url: URL) -> Outcome {
        let file: FileHandle
        do {
            file = try FileHandle(forReadingFrom: url)
        } catch {
            return .unreadable
        }
        defer { try? file.close() }
        do {
            // nil: the file is empty.
            guard let header = try file.read(upToCount: ID3Reader.headerLength),
                  let length = ID3Reader.tagLength(header: header), length <= maxTagBytes
            else { return .noTag }
            // nil: the file ends right after the header.
            return .tag(header + (try file.read(upToCount: length - ID3Reader.headerLength) ?? Data()))
        } catch {
            return .unreadable
        }
    }
}
