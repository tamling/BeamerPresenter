import XCTest
@testable import AlbumArtworkCore

final class GridTargetsTests: XCTestCase {
    private let layout = GridLayout(rows: 6, aspect: 16.0 / 9.0)

    private func cell(_ r: Int, _ c: Int) -> GridCell { GridCell(row: r, col: c) }

    func testLinkedDropCandidatesFromTopLeft() {
        let candidates = GridTargets.linkedDropCandidates(from: cell(0, 0), in: layout)
        XCTAssertEqual(Array(candidates.prefix(3)), [cell(1, 3), cell(2, 2), cell(3, 1)])
        for c in candidates {
            XCTAssertTrue([4, 8, 12].contains(abs(c.row) + abs(c.col)))
            XCTAssertGreaterThan(c.row, 0)
        }
    }

    func testNoCandidatesFromBottomRow() {
        XCTAssertEqual(GridTargets.linkedDropCandidates(from: cell(5, 4), in: layout), [])
    }

    func testRollPath() {
        XCTAssertEqual(GridTargets.rollPath(from: cell(0, 0), to: cell(2, 2)),
                       [cell(0, 1), cell(0, 2), cell(1, 2), cell(2, 2)])
        XCTAssertEqual(GridTargets.rollPath(from: cell(0, 3), to: cell(1, 0)),
                       [cell(0, 2), cell(0, 1), cell(0, 0), cell(1, 0)])
    }

    func testRollIncrementGivesFullTurns() {
        let start = cell(0, 5)
        let candidates = GridTargets.linkedDropCandidates(from: start, in: layout)
        XCTAssertFalse(candidates.isEmpty)
        for target in candidates {
            let path = GridTargets.rollPath(from: start, to: target)
            let turns = GridTargets.rollIncrement(from: start, to: target) * Double(path.count) / (2 * Double.pi)
            XCTAssertEqual(turns, turns.rounded(), accuracy: 1e-9)
        }
    }

    func testTumbleSteps() {
        XCTAssertEqual(GridTargets.tumbleSteps(from: cell(0, 0), rows: 6), 8)
        XCTAssertEqual(GridTargets.tumbleSteps(from: cell(5, 0), rows: 6), 3)
    }

    func testPinBlockAtCorner() {
        let blocks = GridTargets.pinBlocks(for: cell(0, 0), in: layout)
        XCTAssertEqual(blocks.count, 1)
        let b = blocks[0]
        XCTAssertEqual(b.target, cell(1, 1))
        XCTAssertEqual(b.middle, [cell(0, 1), cell(1, 0)])
        XCTAssertEqual(b.targetCorner, .bottomRight)
        let p = b.pinPoint(in: layout)
        XCTAssertEqual(p.x, -15, accuracy: 1e-5)
        XCTAssertEqual(p.y, 6.666667, accuracy: 1e-5)
    }

    func testPinBlocksInterior() {
        XCTAssertEqual(GridTargets.pinBlocks(for: cell(2, 3), in: layout).count, 4)
        let corner = GridTargets.pinBlocks(for: cell(5, 10), in: layout)
        XCTAssertEqual(corner.count, 1)
        XCTAssertEqual(corner[0].target, cell(4, 9))
        XCTAssertEqual(corner[0].targetCorner, .topLeft)
    }

    func testChainCells() {
        let at = cell(3, 3)
        XCTAssertEqual(GridTargets.chainCell(.sequential, arrivedAt: at, corner: .bottomRight), cell(3, 2))
        XCTAssertEqual(GridTargets.chainCell(.fall, arrivedAt: at, corner: .topLeft), cell(3, 4))
        XCTAssertEqual(GridTargets.chainCell(.downward, arrivedAt: at, corner: .bottomRight), cell(4, 3))
    }
}
