import XCTest
@testable import AlbumArtworkCore

final class StatusTextTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_800_000_000)

    private func status(_ albums: Int, scannedAgo seconds: TimeInterval?, folder: FolderStatus = .available,
                        scanning: Bool = false) -> String {
        StatusText.make(albumCount: albums, lastCompleteScan: seconds.map { now.addingTimeInterval(-$0) },
                        now: now, folder: folder, isScanning: scanning)
    }

    func testStatusDefault() {
        XCTAssertEqual(status(1234, scannedAgo: 2 * 3600), "1.234 Alben · zuletzt eingelesen vor 2 Std.")
    }

    func testStatusRelativeTimes() {
        XCTAssertEqual(status(12, scannedAgo: 30), "12 Alben · zuletzt eingelesen gerade eben")
        XCTAssertEqual(status(12, scannedAgo: 5 * 60), "12 Alben · zuletzt eingelesen vor 5 Min.")
        XCTAssertEqual(status(12, scannedAgo: 86_400), "12 Alben · zuletzt eingelesen vor 1 Tag")
        XCTAssertEqual(status(12, scannedAgo: 3 * 86_400), "12 Alben · zuletzt eingelesen vor 3 Tagen")
        // The edges: each unit starts at its first whole value.
        XCTAssertEqual(status(12, scannedAgo: 59), "12 Alben · zuletzt eingelesen gerade eben")
        XCTAssertEqual(status(12, scannedAgo: 60), "12 Alben · zuletzt eingelesen vor 1 Min.")
        XCTAssertEqual(status(12, scannedAgo: 3599), "12 Alben · zuletzt eingelesen vor 59 Min.")
        XCTAssertEqual(status(12, scannedAgo: 3600), "12 Alben · zuletzt eingelesen vor 1 Std.")
        XCTAssertEqual(status(12, scannedAgo: 86_399), "12 Alben · zuletzt eingelesen vor 23 Std.")
        XCTAssertEqual(status(12, scannedAgo: 2 * 86_400 - 1), "12 Alben · zuletzt eingelesen vor 1 Tag")
        // A clock set back since the scan.
        XCTAssertEqual(status(12, scannedAgo: -600), "12 Alben · zuletzt eingelesen gerade eben")
    }

    func testStatusUnavailable() {
        // Review Focus 1: the cache stays and the status says so.
        XCTAssertEqual(status(12, scannedAgo: 3600, folder: .unavailable),
                       "Musikordner nicht erreichbar · zeige 12 Alben aus dem Zwischenspeicher")
        XCTAssertEqual(status(1234, scannedAgo: nil, folder: .unavailable, scanning: true),
                       "Musikordner nicht erreichbar · zeige 1.234 Alben aus dem Zwischenspeicher")
    }

    func testStatusNotChosen() {
        XCTAssertEqual(status(0, scannedAgo: nil, folder: .notChosen), "Kein Musikordner gewählt")
        XCTAssertEqual(status(12, scannedAgo: 60, folder: .notChosen, scanning: true), "Kein Musikordner gewählt")
    }

    func testStatusScanning() {
        XCTAssertEqual(status(1234, scannedAgo: 3600, scanning: true), "1.234 Alben · lese gerade ein …")
        XCTAssertEqual(status(0, scannedAgo: nil, scanning: true), "0 Alben · lese gerade ein …")
    }

    func testStatusNeverScanned() {
        XCTAssertEqual(status(7, scannedAgo: nil), "7 Alben · noch nicht eingelesen")
    }

    func testStatusOneAlbum() {
        XCTAssertEqual(status(1, scannedAgo: 30), "1 Album · zuletzt eingelesen gerade eben")
        XCTAssertEqual(status(1, scannedAgo: nil, folder: .unavailable),
                       "Musikordner nicht erreichbar · zeige 1 Album aus dem Zwischenspeicher")
    }

    func testNumbersGroupedWithDots() {
        XCTAssertEqual(StatusText.grouped(0), "0")
        XCTAssertEqual(StatusText.grouped(999), "999")
        XCTAssertEqual(StatusText.grouped(1000), "1.000")
        XCTAssertEqual(StatusText.grouped(1234), "1.234")
        XCTAssertEqual(StatusText.grouped(12_345_678), "12.345.678")
        XCTAssertEqual(StatusText.grouped(-1234), "-1.234")
    }

    func testHints() {
        XCTAssertEqual(StatusText.hint(folder: .notChosen, albumCount: 0, isScanning: false, needed: 66),
                       "Musikordner in den Screensaver-Optionen wählen")
        XCTAssertEqual(StatusText.hint(folder: .available, albumCount: 10, isScanning: true, needed: 66),
                       "Lese Musik ein … 10 Alben")
        XCTAssertNil(StatusText.hint(folder: .available, albumCount: 66, isScanning: true, needed: 66))
        XCTAssertEqual(StatusText.hint(folder: .available, albumCount: 0, isScanning: false, needed: 66),
                       "Keine Cover gefunden")
        // A finished scan with a few albums: the wall shows them, no hint.
        XCTAssertNil(StatusText.hint(folder: .available, albumCount: 10, isScanning: false, needed: 66))
        // Out of reach and nothing cached: the wall says where to look, instead of staying black.
        XCTAssertEqual(StatusText.hint(folder: .unavailable, albumCount: 0, isScanning: false, needed: 66),
                       "Musikordner nicht erreichbar – siehe Screensaver-Optionen")
        XCTAssertEqual(StatusText.hint(folder: .unavailable, albumCount: 0, isScanning: true, needed: 66),
                       "Musikordner nicht erreichbar – siehe Screensaver-Optionen")
        // Out of reach with covers cached: the wall shows them, no hint.
        XCTAssertNil(StatusText.hint(folder: .unavailable, albumCount: 10, isScanning: false, needed: 66))
        XCTAssertEqual(StatusText.hint(folder: .available, albumCount: 1_234, isScanning: true, needed: 2_000),
                       "Lese Musik ein … 1.234 Alben")
        XCTAssertEqual(StatusText.hint(folder: .available, albumCount: 1, isScanning: true, needed: 66),
                       "Lese Musik ein … 1 Album")
    }
}
