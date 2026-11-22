import XCTest
@testable import AlbumArtworkCore

final class AnimationPlannerTests: XCTestCase {
    func testKindFrequencies() {
        var rng = SplitMix64(seed: 42)
        let n = 100_000
        var counts: [Int: Int] = [:]
        for _ in 0..<n {
            let kind = AnimationPlanner.pickKind(using: &rng)
            counts[AnimationKind.allCases.firstIndex(of: kind)!, default: 0] += 1
        }
        for (i, kind) in AnimationKind.allCases.enumerated() {
            let freq = Double(counts[i, default: 0]) / Double(n)
            XCTAssertEqual(freq, kind.weight / 100, accuracy: 0.01, "\(kind)")
        }
        XCTAssertEqual(AnimationKind.allCases.map(\.weight).reduce(0, +), 100, accuracy: 1e-9)
        XCTAssertEqual(AnimationKind.allCases.filter(\.isRow), [.rowRollDrop, .rowDrop])
    }

    func testCoverCountRange() {
        var rng = SplitMix64(seed: 1)
        let values = (0..<10_000).map { _ in AnimationPlanner.coverCount(using: &rng) }
        XCTAssertTrue(Set(values).isSubset(of: Set(3...6)))
        XCTAssertEqual(Set(values), Set(3...6))
    }

    func testPickCellsDistinct() {
        var rng = SplitMix64(seed: 3)
        let cells = (0..<4).flatMap { r in (0..<5).map { GridCell(row: r, col: $0) } }
        let picked = AnimationPlanner.pickCells(6, from: cells, using: &rng)
        XCTAssertEqual(picked.count, 6)
        XCTAssertEqual(Set(picked).count, 6)
        XCTAssertTrue(Set(picked).isSubset(of: Set(cells)))
        XCTAssertEqual(AnimationPlanner.pickCells(6, from: Array(cells.prefix(2)), using: &rng).count, 2)
    }

    func testRowInUpperHalf() {
        var rng = SplitMix64(seed: 5)
        for (rows, maxRow) in [(6, 2), (3, 0), (12, 5)] {
            let values = (0..<2_000).map { _ in AnimationPlanner.row(rows: rows, using: &rng) }
            XCTAssertTrue(values.allSatisfy { (0...maxRow).contains($0) }, "rows \(rows)")
            XCTAssertEqual(Set(values), Set(0...maxRow), "rows \(rows)")
        }
    }

    func testRowDelays() {
        var rng = SplitMix64(seed: 7)
        for _ in 0..<200 {
            let delays = AnimationPlanner.rowDelays(count: 4, using: &rng)
            XCTAssertEqual(delays.count, 4)
            XCTAssertEqual(delays[0], 0)
            for i in 1..<4 {
                let unit = delays[i] / Double(i)
                XCTAssertGreaterThanOrEqual(unit, 0.2 - 1e-12)
                XCTAssertLessThanOrEqual(unit, 0.4 + 1e-12)
            }
        }
    }

    func testTickInterval() {
        var rng = SplitMix64(seed: 9)
        for _ in 0..<1_000 {
            let t = AnimationPlanner.tickInterval(base: 3, using: &rng)
            XCTAssertGreaterThanOrEqual(t, 3)
            XCTAssertLessThan(t, 4)
        }
    }
}
