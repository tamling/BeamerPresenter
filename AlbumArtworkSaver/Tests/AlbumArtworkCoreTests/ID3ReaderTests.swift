import XCTest
@testable import AlbumArtworkCore

final class ID3ReaderTests: XCTestCase {
    private func image(_ count: Int, seed: UInt8 = 1) -> Data {
        Data((0..<count).map { UInt8(truncatingIfNeeded: $0 &* 31 &+ Int(seed)) })
    }

    func testV23TextAndFrontCover() {
        let jpeg = image(500)
        var b = ID3Builder(version: 3)
        b.text("TALB", "Blue Train", encoding: 0)
        b.text("TPE1", "John Coltrane", encoding: 0)
        // UTF-16 description "A" has a 00 at an odd offset: terminator must be found on even positions.
        b.picture(type: 3, mime: "image/jpeg", description: "A", data: jpeg, encoding: 1)
        let tags = ID3Reader.parse(b.build())
        XCTAssertEqual(tags?.album, "Blue Train")
        XCTAssertEqual(tags?.artist, "John Coltrane")
        XCTAssertEqual(tags?.picture, jpeg)
        XCTAssertEqual(tags?.pictureMIME, "image/jpeg")
    }

    func testV24UTF8AndSyncSafeSizes() {
        let png = image(300)
        var b = ID3Builder(version: 4)
        b.text("TALB", "Ångström", encoding: 3)
        b.picture(type: 3, mime: "image/png", description: "", data: png, encoding: 3)
        let tags = ID3Reader.parse(b.build())
        XCTAssertEqual(tags?.album, "Ångström")
        XCTAssertEqual(tags?.picture, png)
        XCTAssertEqual(tags?.pictureMIME, "image/png")
    }

    func testV22Frames() {
        let png = image(64)
        var b = ID3Builder(version: 2)
        b.text("TAL", "Album", encoding: 0)
        b.text("TP1", "Artist", encoding: 0)
        b.text("TP2", "Band", encoding: 0)
        b.picture(type: 3, mime: "PNG", description: "", data: png, encoding: 0)
        let tags = ID3Reader.parse(b.build())
        XCTAssertEqual(tags?.album, "Album")
        XCTAssertEqual(tags?.artist, "Artist")
        XCTAssertEqual(tags?.albumArtist, "Band")
        XCTAssertEqual(tags?.picture, png)
        XCTAssertEqual(tags?.pictureMIME, "image/png")
    }

    func testUTF16Variants() {
        let units = Array("Kind of Blue".utf16)
        let le = units.flatMap { [UInt8($0 & 0xFF), UInt8($0 >> 8)] }
        let be = units.flatMap { [UInt8($0 >> 8), UInt8($0 & 0xFF)] }
        let cases: [(UInt8, [UInt8])] = [
            (1, [0xFF, 0xFE] + le),
            (1, [0xFE, 0xFF] + be),
            (1, le),
            (2, be),
        ]
        for (encoding, bytes) in cases {
            var b = ID3Builder(version: 3)
            b.rawFrame(id: "TALB", flags: [0, 0], body: Data([encoding] + bytes))
            XCTAssertEqual(ID3Reader.parse(b.build())?.album, "Kind of Blue", "encoding \(encoding) bytes \(bytes.prefix(2))")
        }
    }

    func testFrontCoverPreferred() {
        let other = image(40, seed: 5), front = image(50, seed: 9)
        var b = ID3Builder(version: 3)
        b.picture(type: 0, mime: "image/jpeg", description: "", data: other, encoding: 0)
        b.picture(type: 3, mime: "image/jpeg", description: "", data: front, encoding: 0)
        XCTAssertEqual(ID3Reader.parse(b.build())?.picture, front)
    }

    func testFirstPictureUsedWithoutFrontCover() {
        let first = image(40, seed: 5), second = image(50, seed: 9)
        var b = ID3Builder(version: 3)
        b.picture(type: 4, mime: "image/jpeg", description: "", data: first, encoding: 0)
        b.picture(type: 0, mime: "image/jpeg", description: "", data: second, encoding: 0)
        XCTAssertEqual(ID3Reader.parse(b.build())?.picture, first)
    }

    func testLinkPictureIgnored() {
        var b = ID3Builder(version: 3)
        b.picture(type: 3, mime: "-->", description: "", data: Data("http://example.com/a.jpg".utf8), encoding: 0)
        let tags = ID3Reader.parse(b.build())
        XCTAssertNotNil(tags)
        XCTAssertNil(tags?.picture)
    }

    func testTagUnsynchronisation() {
        let original = Data([0xFF, 0xE0, 0x00, 0xFF, 0xFF, 0xD8, 0x01, 0xFF])
        var b = ID3Builder(version: 3)
        b.unsynchronised = true
        b.text("TALB", "Sync", encoding: 0)
        b.picture(type: 3, mime: "image/jpeg", description: "", data: original, encoding: 0)
        let tags = ID3Reader.parse(b.build())
        XCTAssertEqual(tags?.album, "Sync")
        XCTAssertEqual(tags?.picture, original)
    }

    func testV24FrameUnsynchronisation() {
        let original = Data([0xFF, 0xE0, 0x00, 0xFF, 0xD8])
        var b = ID3Builder(version: 4)
        b.unsynchronised = true
        b.picture(type: 3, mime: "image/jpeg", description: "", data: original, encoding: 0)
        XCTAssertEqual(ID3Reader.parse(b.build())?.picture, original)
    }

    func testV24DataLengthIndicator() {
        var b = ID3Builder(version: 4)
        var body = Data([0, 0, 0, 6, 0])
        body.append(Data("Hello".utf8))
        b.rawFrame(id: "TALB", flags: [0, 0x01], body: body)
        XCTAssertEqual(ID3Reader.parse(b.build())?.album, "Hello")
    }

    func testExtendedHeaders() {
        for version: UInt8 in [3, 4] {
            var b = ID3Builder(version: version)
            b.extendedHeader = true
            b.text("TALB", "Ext", encoding: 0)
            XCTAssertEqual(ID3Reader.parse(b.build())?.album, "Ext", "version \(version)")
        }
    }

    func testCompressedFrameSkipped() {
        var v3 = ID3Builder(version: 3)
        v3.rawFrame(id: "TALB", flags: [0, 0x80], body: Data([0, 1, 2, 3]))
        v3.text("TPE1", "Artist", encoding: 0)
        let t3 = ID3Reader.parse(v3.build())
        XCTAssertNil(t3?.album)
        XCTAssertEqual(t3?.artist, "Artist")

        var v4 = ID3Builder(version: 4)
        v4.rawFrame(id: "TALB", flags: [0, 0x08], body: Data([0, 1, 2, 3]))
        v4.text("TPE1", "Artist", encoding: 0)
        let t4 = ID3Reader.parse(v4.build())
        XCTAssertNil(t4?.album)
        XCTAssertEqual(t4?.artist, "Artist")
    }

    func testTruncatedTag() {
        var b = ID3Builder(version: 3)
        b.text("TALB", "Album", encoding: 0)
        b.text("TPE1", "Artist", encoding: 0)
        b.picture(type: 3, mime: "image/jpeg", description: "", data: image(1000), encoding: 0)
        let full = b.build()
        let tags = ID3Reader.parse(full.prefix(full.count / 2))
        XCTAssertEqual(tags?.album, "Album")
        XCTAssertEqual(tags?.artist, "Artist")
        XCTAssertNil(tags?.picture)
    }

    func testFrameSizeBeyondEnd() {
        var b = ID3Builder(version: 3)
        b.text("TALB", "Album", encoding: 0)
        b.rawFrame(id: "TXXX", flags: [0, 0], body: Data(), sizeOverride: 0x7FFF_FFFF)
        XCTAssertEqual(ID3Reader.parse(b.build())?.album, "Album")
    }

    func testNotID3() {
        let riff = Data("RIFF....WAVE".utf8)
        XCTAssertNil(ID3Reader.tagLength(header: riff))
        XCTAssertNil(ID3Reader.parse(riff))
        let v5 = Data([0x49, 0x44, 0x33, 5, 0, 0, 0, 0, 0, 0])
        XCTAssertNil(ID3Reader.tagLength(header: v5))
        XCTAssertNil(ID3Reader.parse(v5))
        XCTAssertNil(ID3Reader.tagLength(header: Data([0x49, 0x44, 0x33, 4, 0, 0, 0, 0, 0x80, 0])))
    }

    func testTagLength() {
        var header: [UInt8] = [0x49, 0x44, 0x33, 4, 0, 0, 0, 0, 0x02, 0x01]
        XCTAssertEqual(ID3Reader.tagLength(header: Data(header)), 267)
        header[5] = 0x10
        XCTAssertEqual(ID3Reader.tagLength(header: Data(header)), 277)
    }

    func testRandomGarbageNeverCrashes() {
        var rng = SplitMix64(seed: 7)
        for _ in 0..<2000 {
            var input = Data([0x49, 0x44, 0x33, 3, 0, 0])
            for _ in 0..<4 { input.append(UInt8.random(in: 0..<0x80, using: &rng)) }
            let count = Int.random(in: 0...2000, using: &rng)
            for _ in 0..<count { input.append(UInt8.random(in: 0...255, using: &rng)) }
            XCTAssertNotNil(ID3Reader.parse(input))
        }
    }
}
