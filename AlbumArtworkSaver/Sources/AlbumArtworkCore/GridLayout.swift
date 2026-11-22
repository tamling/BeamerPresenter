import Foundation

struct GridCell: Hashable, Codable {
    var row: Int
    var col: Int
}

struct Point2: Equatable {
    var x: Double
    var y: Double
}

/// Seamless (zero-gap) cover grid in world units. The visible world is
/// `worldHeight` units tall, centred on the origin; the width follows the aspect.
struct GridLayout: Equatable {
    static let worldHeight = 20.0
    /// Camera distance for a 45 degree vertical field of view that shows `worldHeight`.
    static let cameraDistance = (worldHeight / 2) / tan(22.5 * Double.pi / 180)

    let rows: Int
    let aspect: Double

    init(rows: Int, aspect: Double) {
        self.rows = min(max(rows, 3), 12)
        self.aspect = max(aspect, 0.1)
    }

    var coverSize: Double { GridLayout.worldHeight / Double(rows) }

    var columns: Int {
        // Epsilon guards against ceil() overshooting exact integer products.
        max(1, Int((GridLayout.worldHeight * aspect / coverSize - 1e-9).rounded(.up)))
    }

    var cellCount: Int { rows * columns }

    var allCells: [GridCell] {
        (0..<rows).flatMap { r in (0..<columns).map { GridCell(row: r, col: $0) } }
    }

    var bottomEdge: Double { -GridLayout.worldHeight / 2 }

    func center(of cell: GridCell) -> Point2 {
        let size = coverSize
        return Point2(
            x: -Double(columns) * size / 2 + (Double(cell.col) + 0.5) * size,
            y: GridLayout.worldHeight / 2 - (Double(cell.row) + 0.5) * size)
    }

    func contains(_ cell: GridCell) -> Bool {
        cell.row >= 0 && cell.row < rows && cell.col >= 0 && cell.col < columns
    }
}
