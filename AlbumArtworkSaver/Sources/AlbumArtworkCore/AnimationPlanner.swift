import Foundation

enum AnimationKind: CaseIterable {
    case flip, drop, linkedDrop, rollDrop, pinRotation, rowRollDrop, rowDrop

    /// Selection weight in percent; all weights sum to 100.
    var weight: Double {
        switch self {
        case .flip, .drop, .linkedDrop, .rollDrop, .pinRotation: return 15
        case .rowRollDrop, .rowDrop: return 12.5
        }
    }

    var isRow: Bool { self == .rowRollDrop || self == .rowDrop }
}

enum AnimationPlanner {
    /// Delay step between consecutive covers of one animation.
    static let stagger: TimeInterval = 0.2

    static func pickKind(using rng: inout SplitMix64) -> AnimationKind {
        let total = AnimationKind.allCases.reduce(0) { $0 + $1.weight }
        var roll = Double.random(in: 0..<total, using: &rng)
        for kind in AnimationKind.allCases {
            if roll < kind.weight { return kind }
            roll -= kind.weight
        }
        return AnimationKind.allCases[AnimationKind.allCases.count - 1]
    }

    static func coverCount(using rng: inout SplitMix64) -> Int {
        Int.random(in: 3...6, using: &rng)
    }

    static func pickCells(_ count: Int, from cells: [GridCell], using rng: inout SplitMix64) -> [GridCell] {
        Array(cells.shuffled(using: &rng).prefix(max(0, count)))
    }

    /// A row from the upper half of the wall.
    static func row(rows: Int, using rng: inout SplitMix64) -> Int {
        Int.random(in: 0..<max(1, rows / 2), using: &rng)
    }

    /// Entry i is i times its own random step in 0.2...0.4 (entry 0 is 0).
    static func rowDelays(count: Int, using rng: inout SplitMix64) -> [TimeInterval] {
        (0..<max(0, count)).map { i in
            Double(i) * Double.random(in: 0.2...0.4, using: &rng)
        }
    }

    static func tickInterval(base: TimeInterval, using rng: inout SplitMix64) -> TimeInterval {
        base + Double.random(in: 0..<1, using: &rng)
    }
}
