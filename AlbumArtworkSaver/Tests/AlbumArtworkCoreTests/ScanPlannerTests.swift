import XCTest
@testable import AlbumArtworkCore

final class ScanPlannerTests: XCTestCase {
    private func stamp(_ size: Int64, _ modified: Double = 1) -> FileStamp { FileStamp(size: size, modified: modified) }

    func testPlanNewChangedVanished() {
        var index = LibraryIndex()
        index.files = ["a.mp3": IndexedFile(stamp: stamp(1), album: nil),
                       "b.mp3": IndexedFile(stamp: stamp(2), album: nil),
                       "c.mp3": IndexedFile(stamp: stamp(3), album: nil)]
        let listing = ["a.mp3": stamp(1), "b.mp3": stamp(22), "d.mp3": stamp(4)]
        let plan = ScanPlanner.plan(index: index, listing: listing)
        XCTAssertEqual(plan, ScanPlan(toRead: ["b.mp3", "d.mp3"], vanished: ["c.mp3"]))
    }

    func testRecordGroupsTracksOfOneAlbum() {
        var index = LibraryIndex()
        let info = IndexedAlbum(fingerprint: 5, title: "T", artist: "A")
        let first = ScanPlanner.record(path: "1.mp3", stamp: stamp(1), album: "a-1", info: info, into: &index)
        let second = ScanPlanner.record(path: "2.mp3", stamp: stamp(2), album: "a-1", info: info, into: &index)
        XCTAssertTrue(first.isNew)
        XCTAssertFalse(second.isNew)
        XCTAssertEqual(index.albums.count, 1)
        XCTAssertEqual(index.files["2.mp3"]?.album, "a-1")
    }

    func testRecordDedupesIdenticalPictures() {
        var index = LibraryIndex()
        _ = ScanPlanner.record(path: "1.mp3", stamp: stamp(1), album: "a-1",
                               info: IndexedAlbum(fingerprint: 5, title: "One", artist: "A"), into: &index)
        let second = ScanPlanner.record(path: "2.mp3", stamp: stamp(2), album: "a-2",
                                        info: IndexedAlbum(fingerprint: 5, title: "Two", artist: "B"), into: &index)
        XCTAssertEqual(second.album, "a-1")
        XCTAssertFalse(second.isNew)
        XCTAssertEqual(index.albums.count, 1)
        XCTAssertEqual(index.files["2.mp3"]?.album, "a-1")
    }

    func testRecordWithoutPictureIsRemembered() {
        var index = LibraryIndex()
        let result = ScanPlanner.record(path: "p.mp3", stamp: stamp(1), album: nil, info: nil, into: &index)
        XCTAssertNil(result.album)
        XCTAssertFalse(result.isNew)
        XCTAssertNotNil(index.files["p.mp3"])
        XCTAssertNil(index.files["p.mp3"]?.album)
        XCTAssertEqual(ScanPlanner.plan(index: index, listing: ["p.mp3": stamp(1)]).toRead, [])
    }

    func testExistingAlbumLookup() {
        var index = LibraryIndex()
        index.albums["a-1"] = IndexedAlbum(fingerprint: 5, title: "", artist: "")
        XCTAssertEqual(ScanPlanner.existingAlbum(id: "a-1", fingerprint: 9, in: index), "a-1")
        XCTAssertEqual(ScanPlanner.existingAlbum(id: "a-2", fingerprint: 5, in: index), "a-1")
        XCTAssertNil(ScanPlanner.existingAlbum(id: "a-2", fingerprint: 6, in: index))
    }

    func testFinishCompleteRemovesOrphans() {
        var index = LibraryIndex()
        let info = IndexedAlbum(fingerprint: 1, title: "", artist: "")
        _ = ScanPlanner.record(path: "keep.mp3", stamp: stamp(1), album: "a-keep", info: info, into: &index)
        _ = ScanPlanner.record(path: "gone.mp3", stamp: stamp(1), album: "a-gone",
                               info: IndexedAlbum(fingerprint: 2, title: "", artist: ""), into: &index)
        let date = Date(timeIntervalSince1970: 100)
        let removed = ScanPlanner.finish(vanished: ["gone.mp3"], listingComplete: true, at: date, into: &index)
        XCTAssertEqual(removed, ["a-gone"])
        XCTAssertEqual(index.albumIDs, ["a-keep"])
        XCTAssertNil(index.files["gone.mp3"])
        XCTAssertEqual(index.lastCompleteScan, date)
    }

    func testFinishIncompleteRemovesNothing() {
        var index = LibraryIndex()
        _ = ScanPlanner.record(path: "x.mp3", stamp: stamp(1), album: "a-x",
                               info: IndexedAlbum(fingerprint: 1, title: "", artist: ""), into: &index)
        let before = index
        let removed = ScanPlanner.finish(vanished: ["x.mp3"], listingComplete: false, at: Date(), into: &index)
        XCTAssertEqual(removed, [])
        XCTAssertEqual(index, before)
    }

    func testIndexCodableRoundTrip() throws {
        var index = LibraryIndex()
        _ = ScanPlanner.record(path: "x.mp3", stamp: stamp(7, 12.5), album: "a-x",
                               info: IndexedAlbum(fingerprint: UInt64.max, title: "T", artist: "A"), into: &index)
        index.lastCompleteScan = Date(timeIntervalSince1970: 1000)
        let data = try JSONEncoder().encode(index)
        XCTAssertEqual(try JSONDecoder().decode(LibraryIndex.self, from: data), index)
        XCTAssertEqual(index.version, LibraryIndex.currentVersion)
    }

    func testPlanFiftyThousandFilesIsFast() {
        var index = LibraryIndex()
        var listing: [String: FileStamp] = [:]
        for i in 0..<50_000 {
            let path = "dir\(i % 500)/track\(i).mp3"
            index.files[path] = IndexedFile(stamp: stamp(Int64(i)), album: nil)
            listing[path] = stamp(Int64(i))
        }
        listing["new.mp3"] = stamp(1)
        let start = Date()
        let plan = ScanPlanner.plan(index: index, listing: listing)
        XCTAssertLessThan(Date().timeIntervalSince(start), 2)
        XCTAssertEqual(plan.toRead, ["new.mp3"])
    }
}
