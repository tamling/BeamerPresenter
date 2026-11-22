import XCTest
@testable import AlbumArtworkCore

final class GridLayoutTests: XCTestCase {
    func testSixRowsSixteenByNine() {
        let g = GridLayout(rows: 6, aspect: 16.0 / 9.0)
        XCTAssertEqual(g.coverSize, 20.0 / 6, accuracy: 1e-9)
        XCTAssertEqual(g.columns, 11); XCTAssertEqual(g.cellCount, 66)
        XCTAssertEqual(g.center(of: GridCell(row: 0, col: 0)).x, -16.666667, accuracy: 1e-5)
        XCTAssertEqual(g.center(of: GridCell(row: 0, col: 0)).y, 8.333333, accuracy: 1e-5)
        XCTAssertEqual(g.center(of: GridCell(row: 5, col: 10)).x, 16.666667, accuracy: 1e-5)
        XCTAssertEqual(g.center(of: GridCell(row: 5, col: 10)).y, -8.333333, accuracy: 1e-5)
    }

    func testCameraDistance() {
        XCTAssertEqual(GridLayout.cameraDistance, 24.142136, accuracy: 1e-5)
    }

    func testOddScreens() {
        XCTAssertEqual(GridLayout(rows: 6, aspect: 296.0 / 184.0).columns, 10)
        XCTAssertEqual(GridLayout(rows: 6, aspect: 9.0 / 16.0).columns, 4)
        XCTAssertEqual(GridLayout(rows: 6, aspect: 32.0 / 9.0).columns, 22)
        XCTAssertEqual(GridLayout(rows: 1, aspect: 1.5).rows, 3)
        XCTAssertEqual(GridLayout(rows: 40, aspect: 1.5).rows, 12)
        XCTAssertEqual(GridLayout(rows: 6, aspect: 0).columns, 1)
    }

    func testAllCellsRowMajorAndContains() {
        let g = GridLayout(rows: 3, aspect: 1.0)
        XCTAssertEqual(g.allCells.count, g.cellCount)
        XCTAssertEqual(g.allCells.first, GridCell(row: 0, col: 0))
        XCTAssertEqual(g.allCells[1], GridCell(row: 0, col: 1))
        XCTAssertTrue(g.contains(GridCell(row: 2, col: g.columns - 1)))
        XCTAssertFalse(g.contains(GridCell(row: 3, col: 0)))
        XCTAssertFalse(g.contains(GridCell(row: 0, col: -1)))
        XCTAssertEqual(g.bottomEdge, -10)
    }
}
