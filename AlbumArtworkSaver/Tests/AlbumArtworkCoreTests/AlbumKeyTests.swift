import XCTest
@testable import AlbumArtworkCore

final class AlbumKeyTests: XCTestCase {
    func testFNVVectors() {
        XCTAssertEqual(Fingerprint.fnv1a64(Data()), 0xcbf29ce484222325)
        XCTAssertEqual(Fingerprint.fnv1a64(Data("a".utf8)), 0xaf63dc4c8601ec8c)
    }

    func testAlbumKeyNormalisation() {
        XCTAssertEqual(AlbumKey.make(album: "Blue Train", albumArtist: nil, artist: "John Coltrane", pictureFingerprint: 1),
                       AlbumKey.make(album: "  blue   TRAIN ", albumArtist: nil, artist: "JOHN COLTRANE", pictureFingerprint: 2))
    }

    func testAlbumArtistBeatsArtist() {
        XCTAssertEqual(AlbumKey.make(album: "Hits", albumArtist: "VA", artist: "A", pictureFingerprint: 1),
                       AlbumKey.make(album: "Hits", albumArtist: "VA", artist: "B", pictureFingerprint: 1))
    }

    func testNoAlbumUsesFingerprint() {
        XCTAssertEqual(AlbumKey.make(album: nil, albumArtist: nil, artist: "x", pictureFingerprint: 0xABC), "i-0000000000000abc")
        XCTAssertEqual(AlbumKey.make(album: "  ", albumArtist: nil, artist: "x", pictureFingerprint: 0xABC), "i-0000000000000abc")
    }

    func testIDsAreFileSafe() {
        let ids = [
            AlbumKey.make(album: "A/B:C", albumArtist: "x\u{0}y", artist: nil, pictureFingerprint: 1),
            AlbumKey.make(album: "Ünï", albumArtist: nil, artist: nil, pictureFingerprint: UInt64.max),
            AlbumKey.make(album: nil, albumArtist: nil, artist: nil, pictureFingerprint: 0),
        ]
        for id in ids {
            XCTAssertNotNil(id.range(of: "^[ai]-[0-9a-f]{16}$", options: .regularExpression), id)
        }
    }
}
