import XCTest
@testable import AlbumArtworkCore

final class AlbumPickerTests: XCTestCase {
    private func pool(_ n: Int) -> [AlbumID] { (0..<n).map { "album\($0)" } }

    func testInitialFillUnique() {
        var rng = SplitMix64(seed: 1)
        let fill = AlbumPicker.initialFill(count: 66, pool: pool(100), using: &rng)
        XCTAssertEqual(fill.count, 66)
        XCTAssertEqual(Set(fill).count, 66)
    }

    func testInitialFillRepeats() {
        var rng = SplitMix64(seed: 2)
        let fill = AlbumPicker.initialFill(count: 66, pool: pool(7), using: &rng)
        XCTAssertEqual(fill.count, 66)
        let counts = Dictionary(grouping: fill, by: { $0 }).mapValues(\.count)
        XCTAssertEqual(counts.count, 7)
        XCTAssertTrue(counts.values.allSatisfy { $0 == 9 || $0 == 10 })
    }

    func testInitialFillEmptyPool() {
        var rng = SplitMix64(seed: 3)
        XCTAssertEqual(AlbumPicker.initialFill(count: 10, pool: [], using: &rng), [])
    }

    func testReplacementPrefersInvisible() {
        var rng = SplitMix64(seed: 4)
        let all = pool(100)
        let visible = Set(all.prefix(66))
        for _ in 0..<1_000 {
            let pick = AlbumPicker.replacement(
                pool: all, isReady: { _ in true }, visible: visible,
                avoiding: all[0], using: &rng)
            XCTAssertNotNil(pick)
            XCTAssertFalse(visible.contains(pick!))
        }
    }

    func testReplacementFallsBackToReadyNotAvoiding() {
        var rng = SplitMix64(seed: 5)
        let all = pool(3)
        for _ in 0..<200 {
            let pick = AlbumPicker.replacement(
                pool: all, isReady: { _ in true }, visible: Set(all),
                avoiding: "album1", using: &rng)
            XCTAssertNotNil(pick)
            XCTAssertNotEqual(pick, "album1")
        }
    }

    func testSingleAlbumPool() {
        var rng = SplitMix64(seed: 6)
        let pick = AlbumPicker.replacement(
            pool: ["a"], isReady: { _ in true }, visible: ["a"], avoiding: "a", using: &rng)
        XCTAssertEqual(pick, "a")
    }

    func testNothingReady() {
        var rng = SplitMix64(seed: 7)
        let pick = AlbumPicker.replacement(
            pool: pool(5), isReady: { _ in false }, visible: [], avoiding: nil, using: &rng)
        XCTAssertNil(pick)
    }

    func testPrefetchCandidates() {
        var rng = SplitMix64(seed: 8)
        let all = pool(10)
        let visible = Set(all.prefix(7))
        let few = AlbumPicker.prefetchCandidates(pool: all, visible: visible, count: 2, using: &rng)
        XCTAssertEqual(few.count, 2)
        XCTAssertTrue(few.allSatisfy { !visible.contains($0) })
        let many = AlbumPicker.prefetchCandidates(pool: all, visible: visible, count: 5, using: &rng)
        XCTAssertEqual(many.count, 5)
        XCTAssertEqual(Set(many).count, 5)
        XCTAssertEqual(many.prefix(3).filter { !visible.contains($0) }.count, 3)
        let capped = AlbumPicker.prefetchCandidates(pool: all, visible: visible, count: 50, using: &rng)
        XCTAssertEqual(capped.count, 10)
    }
}
