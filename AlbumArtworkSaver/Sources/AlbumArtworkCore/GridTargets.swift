import Foundation

enum Corner: CaseIterable {
    case topLeft, topRight, bottomLeft, bottomRight
}

/// A 2x2 block used by the pin rotation: the cover at `source` swings diagonally
/// to `target`, the two `middle` covers (row-major) stay in the block.
struct PinBlock: Equatable {
    var source: GridCell
    var target: GridCell
    var middle: [GridCell]
    /// Corner of the block that `target` occupies.
    var targetCorner: Corner

    /// Mean of the four cell centres of the block.
    func pinPoint(in layout: GridLayout) -> Point2 {
        let cells = [source, target] + middle
        let centers = cells.map { layout.center(of: $0) }
        let n = Double(centers.count)
        return Point2(x: centers.reduce(0) { $0 + $1.x } / n,
                      y: centers.reduce(0) { $0 + $1.y } / n)
    }
}

enum ChainKind: CaseIterable {
    case sequential, downward, fall
}

enum GridTargets {
    /// Cells below `from` at Manhattan distance 4, 8 or 12.
    static func linkedDropCandidates(from: GridCell, in layout: GridLayout) -> [GridCell] {
        let distances: Set<Int> = [4, 8, 12]
        var result: [(cell: GridCell, distance: Int)] = []
        for cell in layout.allCells where cell.row > from.row {
            let d = abs(cell.row - from.row) + abs(cell.col - from.col)
            if distances.contains(d) { result.append((cell, d)) }
        }
        result.sort {
            ($0.distance, $0.cell.row, $0.cell.col) < ($1.distance, $1.cell.row, $1.cell.col)
        }
        return result.map(\.cell)
    }

    /// Horizontal first, then vertical; excludes `from`, includes `to`.
    static func rollPath(from: GridCell, to: GridCell) -> [GridCell] {
        var path: [GridCell] = []
        var col = from.col
        let dc = to.col < from.col ? -1 : 1
        while col != to.col {
            col += dc
            path.append(GridCell(row: from.row, col: col))
        }
        var row = from.row
        let dr = to.row < from.row ? -1 : 1
        while row != to.row {
            row += dr
            path.append(GridCell(row: row, col: to.col))
        }
        return path
    }

    /// Same increment for every step of a path, so distances of 4, 8 or 12
    /// always add up to full turns.
    static func rollIncrement(from: GridCell, to: GridCell) -> Double {
        to.col < from.col ? Double.pi / 2 : -Double.pi / 2
    }

    static func tumbleSteps(from: GridCell, rows: Int) -> Int {
        rows - from.row + 2
    }

    static func pinBlocks(for cell: GridCell, in layout: GridLayout) -> [PinBlock] {
        let r = cell.row, c = cell.col
        // (block origin offset, corner the source occupies, corner of the target)
        let configs: [(dr: Int, dc: Int, targetCorner: Corner)] = [
            (0, 0, .bottomRight),   // source top left
            (0, -1, .bottomLeft),   // source top right
            (-1, 0, .topRight),     // source bottom left
            (-1, -1, .topLeft),     // source bottom right
        ]
        var blocks: [PinBlock] = []
        for config in configs {
            let top = r + config.dr, left = c + config.dc
            let all = [GridCell(row: top, col: left), GridCell(row: top, col: left + 1),
                       GridCell(row: top + 1, col: left), GridCell(row: top + 1, col: left + 1)]
            guard all.allSatisfy(layout.contains) else { continue }
            let target: GridCell
            switch config.targetCorner {
            case .topLeft: target = all[0]
            case .topRight: target = all[1]
            case .bottomLeft: target = all[2]
            case .bottomRight: target = all[3]
            }
            let middle = all.filter { $0 != cell && $0 != target }
            blocks.append(PinBlock(source: cell, target: target, middle: middle,
                                   targetCorner: config.targetCorner))
        }
        return blocks
    }

    static func chainCell(_ kind: ChainKind, arrivedAt cell: GridCell, corner: Corner) -> GridCell {
        let r = cell.row, c = cell.col
        let isBottom = corner == .bottomLeft || corner == .bottomRight
        let isRight = corner == .topRight || corner == .bottomRight
        switch kind {
        case .sequential:
            if !isBottom { return GridCell(row: r + 1, col: c) }
            return GridCell(row: r, col: isRight ? c - 1 : c + 1)
        case .downward:
            return GridCell(row: r + 1, col: c)
        case .fall:
            if isBottom { return GridCell(row: r - 1, col: c) }
            return GridCell(row: r, col: isRight ? c - 1 : c + 1)
        }
    }
}
