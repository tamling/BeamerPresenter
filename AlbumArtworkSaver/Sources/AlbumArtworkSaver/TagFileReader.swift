import Foundation

/// Reads the ID3v2 tag at the start of an MP3, and nothing else of the file.
/// The music folder is strictly read-only: the file is only ever opened for reading.
enum TagFileReader {
    /// A larger tag is not read at all: real covers are far smaller, and the
    /// size comes from untrusted bytes.
    static let maxTagBytes = 16 << 20

    /// The whole tag, header included; shorter than the header says when the
    /// file ends early. `nil` without a tag, for a tag larger than
    /// `maxTagBytes`, or when the file cannot be read.
    static func readTag(at url: URL) -> Data? {
        guard let file = try? FileHandle(forReadingFrom: url) else { return nil }
        defer { try? file.close() }
        guard let header = try? file.read(upToCount: ID3Reader.headerLength),
              let length = ID3Reader.tagLength(header: header), length <= maxTagBytes
        else { return nil }
        do {
            // nil: the file ends right after the header.
            return header + (try file.read(upToCount: length - ID3Reader.headerLength) ?? Data())
        } catch {
            return nil
        }
    }
}
