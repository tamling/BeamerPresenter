import Foundation

struct SpriteID: Hashable {
    let raw: Int
}

/// One cover on the wall: a grid cell's owner or a cover in flight.
struct Sprite: Equatable {
    let id: SpriteID
    var album: AlbumID
    var pose: CoverPose
}

/// What `WallEngine.advance` reports, so a renderer can mirror the sprites.
enum WallChange: Equatable {
    case added(SpriteID), removed(SpriteID), albumChanged(SpriteID)
}

struct WallSettings: Equatable {
    var rows: Int
    var interval: TimeInterval

    init(rows: Int = 6, interval: TimeInterval = 3) {
        self.rows = min(max(rows, 3), 12)
        self.interval = min(max(interval, 1), 10)
    }
}

protocol ArtworkSource: AnyObject {
    var pool: [AlbumID] { get }
    func isReady(_ album: AlbumID) -> Bool
    func prefetch(_ albums: [AlbumID])
}

/// The cover wall: one owner sprite per grid cell plus the covers in flight.
/// Time enters only through `start`, `trigger` and `advance`, and all randomness
/// comes from one seeded generator, so a seed replays the same wall.
///
/// A cell taking part in an animation is busy until the animation ends; until
/// then its old owner keeps it, so the wall never has a hole.
final class WallEngine {
    private static let prefetchCount = 12
    private static let successorZ = -0.01
    private static let pinMiddleZ = 0.002
    private static let chainLimit = 5
    private static let chainChance = 0.8

    let layout: GridLayout
    private(set) var sprites: [SpriteID: Sprite] = [:]

    private let settings: WallSettings
    private let source: ArtworkSource
    private var rng: SplitMix64
    private var nextRaw = 0
    private var owners: [GridCell: SpriteID] = [:]
    private var busy: Set<GridCell> = []
    private var tickInterval: TimeInterval = 0
    /// Sorted by time; equal times keep the order they were planned in.
    private var planned: [Planned] = []
    /// In start order.
    private var running: [Running] = []

    init(layout: GridLayout, settings: WallSettings, source: ArtworkSource, seed: UInt64) {
        self.layout = layout
        self.settings = settings
        self.source = source
        rng = SplitMix64(seed: seed)
    }

    func owner(of cell: GridCell) -> SpriteID? { owners[cell] }

    func isBusy(_ cell: GridCell) -> Bool { busy.contains(cell) }

    /// One resting sprite per cell (row-major, like `layout.allCells`); the
    /// first tick follows one tick interval later.
    func start(at time: TimeInterval, initialAlbums: [AlbumID]) {
        precondition(initialAlbums.count == layout.cellCount, "one initial album per cell")
        sprites = [:]
        owners = [:]
        busy = []
        planned = []
        running = []
        for (cell, album) in zip(layout.allCells, initialAlbums) {
            let id = makeID()
            sprites[id] = Sprite(id: id, album: album, pose: .resting(at: layout.center(of: cell)))
            owners[cell] = id
        }
        tickInterval = AnimationPlanner.tickInterval(base: settings.interval, using: &rng)
        schedule(.tick, at: time + tickInterval)
    }

    /// Plans `kind` like a tick would; row kinds pick their own row and ignore `cells`.
    func trigger(_ kind: AnimationKind, cells: [GridCell], at time: TimeInterval) {
        plan(kind, cells: cells, at: time)
    }

    /// Due planned events in time order, then poses, then finished animations in start order.
    func advance(to time: TimeInterval) -> [WallChange] {
        var changes: [WallChange] = []
        while let next = planned.first, next.time <= time {
            planned.removeFirst()
            switch next.action {
            case .tick: tick(at: next.time)
            case let .begin(kind, cell): changes += begin(kind, at: cell, time: next.time)
            }
        }
        for i in running.indices {
            if applyFrame(running[i], at: time, into: &changes) { running[i].switched = true }
        }
        // Chains started while finishing join `running` and finish in a later call.
        let due = running.filter { $0.end <= time }
        running.removeAll { $0.end <= time }
        for animation in due {
            changes += finish(animation)
        }
        return changes
    }

    // MARK: - Planning

    private struct Planned {
        enum Action {
            case tick
            case begin(AnimationKind, GridCell)
        }

        let time: TimeInterval
        let action: Action
    }

    private func schedule(_ action: Planned.Action, at time: TimeInterval) {
        let index = planned.firstIndex { $0.time > time } ?? planned.endIndex
        planned.insert(Planned(time: time, action: action), at: index)
    }

    private func tick(at time: TimeInterval) {
        schedule(.tick, at: time + tickInterval)
        source.prefetch(AlbumPicker.prefetchCandidates(
            pool: source.pool, visible: visibleAlbums(), count: Self.prefetchCount, using: &rng))
        let kind = AnimationPlanner.pickKind(using: &rng)
        var cells: [GridCell] = []
        if !kind.isRow {
            let count = AnimationPlanner.coverCount(using: &rng)
            cells = AnimationPlanner.pickCells(count, from: layout.allCells, using: &rng)
        }
        plan(kind, cells: cells, at: time)
    }

    private func plan(_ kind: AnimationKind, cells: [GridCell], at time: TimeInterval) {
        guard kind.isRow else {
            for (i, cell) in cells.enumerated() {
                schedule(.begin(kind, cell), at: time + Double(i) * AnimationPlanner.stagger)
            }
            return
        }
        let row = AnimationPlanner.row(rows: layout.rows, using: &rng)
        let delays = AnimationPlanner.rowDelays(count: layout.columns, using: &rng)
        let single: AnimationKind = kind == .rowRollDrop ? .rollDrop : .drop
        for (col, delay) in delays.enumerated() {
            schedule(.begin(single, GridCell(row: row, col: col)), at: time + delay)
        }
    }

    // MARK: - Running animations

    private enum Motion {
        case flip(sprite: SpriteID, cell: GridCell, motion: FlipMotion, album: AlbumID)
        case drop(sprite: SpriteID, successor: SpriteID, cell: GridCell, motion: DropMotion)
        case roll(sprite: SpriteID, successor: SpriteID, source: GridCell, target: GridCell,
                  steps: [RollStepMotion])
        case tumble(sprite: SpriteID, successor: SpriteID, cell: GridCell, steps: [TumbleStepMotion])
        case pin(sprite: SpriteID, successor: SpriteID, block: PinBlock, motion: PinSwingMotion,
                 level: Int)
    }

    private struct Running {
        let start: TimeInterval
        let end: TimeInterval
        let cells: [GridCell]
        let motion: Motion
        /// Flip: the new album is shown. Pin: the album swap is done.
        var switched = false
    }

    private func run(_ motion: Motion, cells: [GridCell], at time: TimeInterval, for duration: TimeInterval) {
        busy.formUnion(cells)
        running.append(Running(start: time, end: time + duration, cells: cells, motion: motion))
    }

    /// Starts one single-cover animation at `cell`, or skips it without any change.
    private func begin(_ kind: AnimationKind, at cell: GridCell, time: TimeInterval, level: Int = 0) -> [WallChange] {
        guard !busy.contains(cell), let id = owners[cell], let sprite = sprites[id] else { return [] }
        switch kind {
        case .flip: return beginFlip(sprite, at: cell, time: time)
        case .drop, .rowDrop: return beginDrop(sprite, at: cell, time: time)
        case .linkedDrop: return beginLinkedDrop(sprite, at: cell, time: time)
        case .rollDrop, .rowRollDrop: return beginRollDrop(sprite, at: cell, time: time)
        case .pinRotation: return beginPinRotation(sprite, at: cell, time: time, level: level)
        }
    }

    private func beginFlip(_ sprite: Sprite, at cell: GridCell, time: TimeInterval) -> [WallChange] {
        // Picked now, shown half-way; until then it counts as visible (see `visibleAlbums`).
        guard let album = pickAlbum(avoiding: sprite.album) else { return [] }
        let motion = FlipMotion(center: layout.center(of: cell))
        run(.flip(sprite: sprite.id, cell: cell, motion: motion, album: album), cells: [cell], at: time,
            for: FlipMotion.duration)
        return []
    }

    private func beginDrop(_ sprite: Sprite, at cell: GridCell, time: TimeInterval) -> [WallChange] {
        guard let successor = spawnSuccessor(of: sprite, at: cell) else { return [] }
        let motion = DropMotion.random(origin: layout.center(of: cell), coverSize: layout.coverSize, using: &rng)
        run(.drop(sprite: sprite.id, successor: successor, cell: cell, motion: motion), cells: [cell],
            at: time, for: DropMotion.duration)
        return [.added(successor)]
    }

    private func beginLinkedDrop(_ sprite: Sprite, at cell: GridCell, time: TimeInterval) -> [WallChange] {
        let candidates = GridTargets.linkedDropCandidates(from: cell, in: layout)
        guard let target = candidates.prefix(3).randomElement(using: &rng) else {
            return beginDrop(sprite, at: cell, time: time)
        }
        guard !busy.contains(target), let successor = spawnSuccessor(of: sprite, at: cell) else { return [] }
        let increment = GridTargets.rollIncrement(from: cell, to: target)
        var from = layout.center(of: cell)
        var steps: [RollStepMotion] = []
        for (i, step) in GridTargets.rollPath(from: cell, to: target).enumerated() {
            let to = layout.center(of: step)
            steps.append(RollStepMotion(from: from, to: to, startRotZ: Double(i) * increment,
                                        increment: increment, coverSize: layout.coverSize))
            from = to
        }
        run(.roll(sprite: sprite.id, successor: successor, source: cell, target: target, steps: steps),
            cells: [cell, target], at: time, for: Double(steps.count) * RollStepMotion.duration)
        return [.added(successor)]
    }

    private func beginRollDrop(_ sprite: Sprite, at cell: GridCell, time: TimeInterval) -> [WallChange] {
        guard let successor = spawnSuccessor(of: sprite, at: cell) else { return [] }
        let center = layout.center(of: cell)
        let count = GridTargets.tumbleSteps(from: cell, rows: layout.rows)
        let steps = (0..<count).map { i in
            TumbleStepMotion(from: Point2(x: center.x, y: center.y - Double(i) * layout.coverSize),
                             coverSize: layout.coverSize, startRotX: Double(i) * Double.pi)
        }
        run(.tumble(sprite: sprite.id, successor: successor, cell: cell, steps: steps), cells: [cell],
            at: time, for: Double(count) * (TumbleStepMotion.duration + TumbleStepMotion.pause))
        return [.added(successor)]
    }

    private func beginPinRotation(_ sprite: Sprite, at cell: GridCell, time: TimeInterval,
                                  level: Int) -> [WallChange] {
        let blocks = GridTargets.pinBlocks(for: cell, in: layout).filter { block in
            ([block.source, block.target] + block.middle).allSatisfy { !busy.contains($0) }
        }
        guard let block = blocks.randomElement(using: &rng) else {
            return beginFlip(sprite, at: cell, time: time)
        }
        guard let successor = spawnSuccessor(of: sprite, at: cell) else { return [] }
        for middle in block.middle {
            if let id = owners[middle] { sprites[id]?.pose.z = Self.pinMiddleZ }
        }
        let motion = PinSwingMotion(pin: block.pinPoint(in: layout), from: layout.center(of: cell))
        run(.pin(sprite: sprite.id, successor: successor, block: block, motion: motion, level: level),
            cells: [block.source, block.target] + block.middle, at: time, for: PinSwingMotion.duration)
        return [.added(successor)]
    }

    /// Poses the moving sprite of `animation`; returns true when it switches album in this frame.
    private func applyFrame(_ animation: Running, at time: TimeInterval, into changes: inout [WallChange]) -> Bool {
        let elapsed = time - animation.start
        switch animation.motion {
        case let .flip(id, _, motion, album):
            let frame = motion.frame(at: elapsed)
            sprites[id]?.pose = frame.pose
            guard frame.showsNewAlbum, !animation.switched else { return false }
            sprites[id]?.album = album
            changes.append(.albumChanged(id))
            return true
        case let .drop(id, _, _, motion):
            sprites[id]?.pose = motion.pose(at: elapsed)
        case let .roll(id, _, _, _, steps):
            let (i, local) = Self.step(at: elapsed, period: RollStepMotion.duration, count: steps.count)
            sprites[id]?.pose = steps[i].pose(at: local)
        case let .tumble(id, _, _, steps):
            let period = TumbleStepMotion.duration + TumbleStepMotion.pause
            let (i, local) = Self.step(at: elapsed, period: period, count: steps.count)
            sprites[id]?.pose = steps[i].pose(at: local)
        case let .pin(id, _, _, motion, _):
            sprites[id]?.pose = motion.pose(at: elapsed)
            guard motion.hasSwapped(at: elapsed), !animation.switched else { return false }
            // Hidden under the middle covers; nothing ready keeps the old album.
            if let old = sprites[id]?.album, let album = pickAlbum(avoiding: old) {
                sprites[id]?.album = album
                changes.append(.albumChanged(id))
            }
            return true
        }
        return false
    }

    /// Index of the step running at `elapsed` and the time into it; a pause holds the step's end pose.
    private static func step(at elapsed: TimeInterval, period: TimeInterval,
                             count: Int) -> (index: Int, local: TimeInterval) {
        let index = min(max(Int(elapsed / period), 0), count - 1)
        return (index, elapsed - Double(index) * period)
    }

    /// Hands the cells to their new owners, removes covers that left, frees the cells.
    private func finish(_ animation: Running) -> [WallChange] {
        busy.subtract(animation.cells)
        switch animation.motion {
        case let .flip(id, cell, _, _):
            settle(id, in: cell)
            return []
        case let .drop(id, successor, cell, _), let .tumble(id, successor, cell, _):
            sprites[id] = nil
            settle(successor, in: cell)
            return [.removed(id)]
        case let .roll(id, successor, source, target, _):
            let changes = replaceOwner(of: target, with: id)
            settle(successor, in: source)
            return changes
        case let .pin(id, successor, block, _, level):
            var changes = replaceOwner(of: block.target, with: id)
            settle(successor, in: block.source)
            for middle in block.middle {
                if let owner = owners[middle] { settle(owner, in: middle) }
            }
            changes += chain(after: block, level: level, at: animation.end)
            return changes
        }
    }

    /// A finished pin rotation may start the next animation next to where it arrived.
    private func chain(after block: PinBlock, level: Int, at time: TimeInterval) -> [WallChange] {
        guard level < Self.chainLimit, Double.random(in: 0..<1, using: &rng) < Self.chainChance else { return [] }
        let options = ChainKind.allCases.compactMap { kind -> (kind: ChainKind, cell: GridCell)? in
            let cell = GridTargets.chainCell(kind, arrivedAt: block.target, corner: block.targetCorner)
            return layout.contains(cell) && !busy.contains(cell) ? (kind, cell) : nil
        }
        guard let next = options.randomElement(using: &rng) else { return [] }
        switch next.kind {
        case .sequential, .downward:
            return begin(.pinRotation, at: next.cell, time: time, level: level + 1)
        case .fall:
            return begin(Bool.random(using: &rng) ? .drop : .rollDrop, at: next.cell, time: time)
        }
    }

    // MARK: - Sprites and albums

    private func makeID() -> SpriteID {
        defer { nextRaw += 1 }
        return SpriteID(raw: nextRaw)
    }

    /// A new cover resting just behind `sprite`, or nil when no album is ready.
    private func spawnSuccessor(of sprite: Sprite, at cell: GridCell) -> SpriteID? {
        guard let album = pickAlbum(avoiding: sprite.album) else { return nil }
        let id = makeID()
        sprites[id] = Sprite(id: id, album: album, pose: .resting(at: layout.center(of: cell), z: Self.successorZ))
        return id
    }

    /// `id` owns `cell` and rests in its middle.
    private func settle(_ id: SpriteID, in cell: GridCell) {
        owners[cell] = id
        sprites[id]?.pose = .resting(at: layout.center(of: cell))
    }

    private func replaceOwner(of cell: GridCell, with id: SpriteID) -> [WallChange] {
        let old = owners[cell]
        settle(id, in: cell)
        guard let old, old != id else { return [] }
        sprites[old] = nil
        return [.removed(old)]
    }

    private func pickAlbum(avoiding album: AlbumID) -> AlbumID? {
        AlbumPicker.replacement(pool: source.pool, isReady: source.isReady, visible: visibleAlbums(),
                                avoiding: album, using: &rng)
    }

    /// Albums of all sprites plus albums picked but not yet shown.
    private func visibleAlbums() -> Set<AlbumID> {
        var albums = Set(sprites.values.map(\.album))
        for animation in running where !animation.switched {
            if case let .flip(_, _, _, album) = animation.motion { albums.insert(album) }
        }
        return albums
    }
}
