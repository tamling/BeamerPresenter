import XCTest
@testable import AlbumArtworkCore

final class FakeSource: ArtworkSource {
    var pool: [AlbumID]
    var ready = true
    private(set) var prefetched: [[AlbumID]] = []

    init(pool: [AlbumID]) { self.pool = pool }

    func isReady(_ album: AlbumID) -> Bool { ready }
    func prefetch(_ albums: [AlbumID]) { prefetched.append(albums) }
}

final class WallEngineTests: XCTestCase {
    private let layout = GridLayout(rows: 6, aspect: 16.0 / 9.0)
    private let albums = (0..<200).map { "album\($0)" }
    private let frame = 1.0 / 60

    private func makeEngine(seed: UInt64 = 42, pool: [AlbumID]? = nil, ready: Bool = true,
                            settings: WallSettings = WallSettings()) -> (WallEngine, FakeSource) {
        let pool = pool ?? albums
        let source = FakeSource(pool: pool)
        source.ready = ready
        let engine = WallEngine(layout: layout, settings: settings, source: source, seed: seed)
        var rng = SplitMix64(seed: seed)
        engine.start(at: 0, initialAlbums: AlbumPicker.initialFill(count: layout.cellCount, pool: pool, using: &rng))
        return (engine, source)
    }

    /// Advances frame by frame (1/60 s) up to `end` and collects every change.
    private func run(_ engine: WallEngine, from start: Double = 0, to end: Double) -> [WallChange] {
        var changes: [WallChange] = []
        var n = Int((start / frame).rounded())
        while Double(n) * frame <= end + 1e-9 {
            changes += engine.advance(to: Double(n) * frame)
            n += 1
        }
        return changes
    }

    private func isResting(_ pose: CoverPose, at p: Point2) -> Bool {
        let e = 1e-9
        return abs(pose.x - p.x) < e && abs(pose.y - p.y) < e && abs(pose.z) < e
            && abs(pose.rotX) < e && abs(pose.rotY) < e && abs(pose.rotZ) < e
            && abs(pose.scale - 1) < e && abs(pose.opacity - 1) < e
    }

    private func albumChanges(_ changes: [WallChange]) -> [WallChange] {
        changes.filter { if case .albumChanged = $0 { return true } else { return false } }
    }

    /// First broken wall invariant, or nil.
    private func violation(in engine: WallEngine, uniqueAlbums: Bool) -> String? {
        var ownerAlbums: [AlbumID] = []
        for cell in layout.allCells {
            guard let id = engine.owner(of: cell), let sprite = engine.sprites[id] else {
                return "cell \(cell) has no existing owner"
            }
            ownerAlbums.append(sprite.album)
            if !engine.isBusy(cell) && !isResting(sprite.pose, at: layout.center(of: cell)) {
                return "owner of free cell \(cell) is not resting: \(sprite.pose)"
            }
        }
        if engine.sprites.count > 3 * layout.cellCount { return "\(engine.sprites.count) sprites" }
        for sprite in engine.sprites.values {
            let p = sprite.pose
            if ![p.x, p.y, p.z, p.rotX, p.rotY, p.rotZ, p.scale, p.opacity].allSatisfy(\.isFinite) {
                return "sprite \(sprite.id) has a non-finite pose: \(p)"
            }
        }
        if uniqueAlbums && Set(ownerAlbums).count != ownerAlbums.count { return "duplicate albums among owners" }
        return nil
    }

    /// Runs `duration` seconds in 1/60 s steps, checking the invariants every `checkEvery` frames.
    private func assertLongRun(seed: UInt64, pool: [AlbumID]?, duration: Double, uniqueAlbums: Bool,
                               checkEvery: Int = 1, file: StaticString = #filePath, line: UInt = #line) {
        let (engine, _) = makeEngine(seed: seed, pool: pool)
        var added = 0, removed = 0, changed = 0
        let frames = Int(duration * 60)
        for n in 1...frames {
            for change in engine.advance(to: Double(n) * frame) {
                switch change {
                case .added: added += 1
                case .removed: removed += 1
                case .albumChanged: changed += 1
                }
            }
            if n % checkEvery == 0, let problem = violation(in: engine, uniqueAlbums: uniqueAlbums) {
                XCTFail("seed \(seed), t = \(Double(n) * frame): \(problem)", file: file, line: line)
                return
            }
        }
        XCTAssertGreaterThan(added, 0, "seed \(seed)", file: file, line: line)
        XCTAssertGreaterThan(removed, 0, "seed \(seed)", file: file, line: line)
        XCTAssertGreaterThan(changed, 0, "seed \(seed)", file: file, line: line)
    }

    func testSettingsClamp() {
        XCTAssertEqual(WallSettings(), WallSettings(rows: 6, interval: 3))
        let low = WallSettings(rows: 1, interval: 0.2)
        XCTAssertEqual(low.rows, 3); XCTAssertEqual(low.interval, 1)
        let high = WallSettings(rows: 40, interval: 60)
        XCTAssertEqual(high.rows, 12); XCTAssertEqual(high.interval, 10)
    }

    func testStartFillsEveryCell() {
        let source = FakeSource(pool: albums)
        let engine = WallEngine(layout: layout, settings: WallSettings(), source: source, seed: 3)
        let initial = Array(albums.prefix(layout.cellCount))
        engine.start(at: 0, initialAlbums: initial)
        XCTAssertEqual(layout.cellCount, 66)
        XCTAssertEqual(engine.sprites.count, 66)
        var owners = Set<SpriteID>()
        for (i, cell) in layout.allCells.enumerated() {
            guard let id = engine.owner(of: cell), let sprite = engine.sprites[id] else {
                XCTFail("no owner for \(cell)"); continue
            }
            owners.insert(id)
            XCTAssertEqual(sprite.album, initial[i])
            XCTAssertEqual(sprite.pose, CoverPose.resting(at: layout.center(of: cell)))
            XCTAssertFalse(engine.isBusy(cell))
        }
        XCTAssertEqual(owners.count, 66)
    }

    func testTicksPrefetchAtOneFixedInterval() {
        let (engine, source) = makeEngine(seed: 5)
        var tickFrames: [Int] = []
        for n in 1...(30 * 60) {
            let before = source.prefetched.count
            _ = engine.advance(to: Double(n) * frame)
            if source.prefetched.count > before { tickFrames.append(n) }
        }
        XCTAssertGreaterThanOrEqual(tickFrames.count, 7)
        XCTAssertTrue((180...241).contains(tickFrames[0]), "first tick at frame \(tickFrames[0])")
        let gaps = zip(tickFrames.dropFirst(), tickFrames).map { $0 - $1 }
        XCTAssertLessThanOrEqual(gaps.max()! - gaps.min()!, 1, "interval rolled once: \(gaps)")
        XCTAssertLessThanOrEqual(abs(gaps[0] - tickFrames[0]), 1)
        for batch in source.prefetched {
            XCTAssertEqual(batch.count, 12)
            XCTAssertEqual(Set(batch).count, 12)
        }
    }

    func testFlipChangesAlbumHalfway() {
        let (engine, _) = makeEngine()
        let cell = GridCell(row: 2, col: 3)
        let owner = engine.owner(of: cell)!
        let oldAlbum = engine.sprites[owner]!.album
        engine.trigger(.flip, cells: [cell], at: 0)
        XCTAssertEqual(engine.advance(to: 0.4), [])
        XCTAssertTrue(engine.isBusy(cell))
        XCTAssertEqual(engine.advance(to: 0.5), [.albumChanged(owner)])
        XCTAssertNotEqual(engine.sprites[owner]!.album, oldAlbum)
        XCTAssertEqual(engine.advance(to: 0.95), [])
        XCTAssertEqual(engine.sprites[owner]!.pose.rotY, 0)
        XCTAssertFalse(engine.isBusy(cell))
        XCTAssertEqual(engine.owner(of: cell), owner)
    }

    func testDropReplacesCover() {
        let (engine, _) = makeEngine()
        let cell = GridCell(row: 2, col: 3)
        let old = engine.owner(of: cell)!
        engine.trigger(.drop, cells: [cell], at: 0)
        let changes = engine.advance(to: 0)
        guard changes.count == 1, case let .added(r) = changes[0] else {
            return XCTFail("expected one .added, got \(changes)")
        }
        XCTAssertEqual(engine.sprites[r]!.pose.z, -0.01)
        XCTAssertNotEqual(engine.sprites[r]!.album, engine.sprites[old]!.album)
        XCTAssertEqual(engine.owner(of: cell), old, "the old cover owns the cell until the drop ends")
        XCTAssertTrue(engine.advance(to: 2.25).contains(.removed(old)))
        XCTAssertNil(engine.sprites[old])
        XCTAssertEqual(engine.owner(of: cell), r)
        XCTAssertEqual(engine.sprites[r]!.pose.z, 0)
        XCTAssertFalse(engine.isBusy(cell))
    }

    func testLinkedDropMovesToTarget() {
        let (engine, _) = makeEngine(seed: 1)
        let start = GridCell(row: 0, col: 0)
        let old = engine.owner(of: start)!
        let candidates = Array(GridTargets.linkedDropCandidates(from: start, in: layout).prefix(3))
        let candidateOwners = candidates.map { engine.owner(of: $0)! }
        engine.trigger(.linkedDrop, cells: [start], at: 0)
        var changes = run(engine, to: 0.6)
        XCTAssertTrue(engine.isBusy(start))
        XCTAssertEqual(candidates.filter(engine.isBusy).count, 1)
        XCTAssertEqual(engine.owner(of: start), old)
        changes += engine.advance(to: 1.25)
        let reached = candidates.indices.filter { engine.owner(of: candidates[$0]) == old }
        XCTAssertEqual(reached.count, 1)
        guard let index = reached.first else { return }
        let pose = engine.sprites[old]!.pose
        XCTAssertEqual(pose.rotZ, 0)
        XCTAssertTrue(isResting(pose, at: layout.center(of: candidates[index])))
        XCTAssertTrue(changes.contains(.removed(candidateOwners[index])))
        XCTAssertNil(engine.sprites[candidateOwners[index]])
        let fresh = engine.owner(of: start)!
        XCTAssertNotEqual(fresh, old)
        XCTAssertTrue(changes.contains(.added(fresh)))
        XCTAssertFalse(engine.isBusy(start))
        XCTAssertFalse(engine.isBusy(candidates[index]))
    }

    func testLinkedDropFromBottomRowDrops() {
        let (engine, _) = makeEngine()
        let cell = GridCell(row: 5, col: 4)
        let old = engine.owner(of: cell)!
        engine.trigger(.linkedDrop, cells: [cell], at: 0)
        let changes = engine.advance(to: 0)
        guard changes.count == 1, case let .added(r) = changes[0] else {
            return XCTFail("expected one .added, got \(changes)")
        }
        XCTAssertEqual(engine.sprites[r]!.pose.z, -0.01)
        _ = engine.advance(to: 1.25)
        XCTAssertEqual(layout.allCells.filter(engine.isBusy), [cell])
        XCTAssertEqual(engine.owner(of: cell), old)
        XCTAssertLessThan(engine.sprites[old]!.pose.y, layout.center(of: cell).y)
        XCTAssertTrue(engine.advance(to: 2.25).contains(.removed(old)))
        XCTAssertEqual(engine.owner(of: cell), r)
        XCTAssertEqual(engine.sprites[r]!.pose.z, 0)
    }

    func testRollDropLeavesScreen() {
        let (engine, _) = makeEngine()
        let cell = GridCell(row: 4, col: 0)
        let old = engine.owner(of: cell)!
        engine.trigger(.rollDrop, cells: [cell], at: 0)
        let first = engine.advance(to: 4 * 0.43 - 0.02)
        guard first.count == 1, case let .added(r) = first[0] else {
            return XCTFail("expected one .added, got \(first)")
        }
        XCTAssertLessThan(engine.sprites[old]!.pose.y, layout.bottomEdge - layout.coverSize / 2)
        XCTAssertEqual(engine.owner(of: cell), old)
        XCTAssertTrue(engine.advance(to: 4 * 0.43 + 0.02).contains(.removed(old)))
        XCTAssertEqual(engine.owner(of: cell), r)
        XCTAssertTrue(isResting(engine.sprites[r]!.pose, at: layout.center(of: cell)))
    }

    func testPinRotationSwapsOnce() {
        let (engine, _) = makeEngine()
        let cell = GridCell(row: 2, col: 3)
        let old = engine.owner(of: cell)!
        let oldAlbum = engine.sprites[old]!.album
        let targets = GridTargets.pinBlocks(for: cell, in: layout).map(\.target)
        engine.trigger(.pinRotation, cells: [cell], at: 0)
        let changes = run(engine, to: 0.85)
        XCTAssertEqual(albumChanges(changes), [.albumChanged(old)])
        XCTAssertNotEqual(engine.sprites[old]!.album, oldAlbum)
        let owned = targets.filter { engine.owner(of: $0) == old }
        XCTAssertEqual(owned.count, 1)
        if let target = owned.first {
            XCTAssertEqual(engine.sprites[old]!.pose.x, layout.center(of: target).x, accuracy: 1e-9)
            XCTAssertEqual(engine.sprites[old]!.pose.y, layout.center(of: target).y, accuracy: 1e-9)
        }
        let fresh = engine.owner(of: cell)!
        XCTAssertNotEqual(fresh, old)
        XCTAssertTrue(changes.contains(.added(fresh)))
        XCTAssertEqual(changes.filter { if case .removed = $0 { return true } else { return false } }.count, 1)
    }

    func testPinSwapKeepsAlbumWhenNothingReady() {
        let (engine, source) = makeEngine()
        let cell = GridCell(row: 2, col: 3)
        let old = engine.owner(of: cell)!
        let oldAlbum = engine.sprites[old]!.album
        engine.trigger(.pinRotation, cells: [cell], at: 0)
        XCTAssertEqual(run(engine, to: 0.1).count, 1)
        source.ready = false
        let changes = run(engine, from: 0.1 + frame, to: 0.85)
        XCTAssertEqual(albumChanges(changes), [])
        XCTAssertEqual(engine.sprites[old]!.album, oldAlbum)
        XCTAssertEqual(GridTargets.pinBlocks(for: cell, in: layout).filter { engine.owner(of: $0.target) == old }.count, 1)
    }

    func testPinRotationChainsAtMostFiveLinks() {
        // Interval 10: the first tick comes after 10 s, so only the triggered chain runs.
        var lengths: [Int] = []
        for seed in UInt64(1)...200 {
            let (engine, _) = makeEngine(seed: seed, settings: WallSettings(interval: 10))
            engine.trigger(.pinRotation, cells: [GridCell(row: 2, col: 3)], at: 0)
            // Each pin rotation (and a flip in place of one) changes exactly one album.
            lengths.append(albumChanges(run(engine, to: 9.9)).count)
            XCTAssertTrue(layout.allCells.allSatisfy { !engine.isBusy($0) }, "seed \(seed)")
        }
        XCTAssertEqual(lengths.max(), 6)
        XCTAssertEqual(lengths.min(), 1)
    }

    func testNothingReadySkips() {
        let (engine, _) = makeEngine(ready: false)
        let before = engine.sprites
        let cells = [GridCell(row: 2, col: 3), GridCell(row: 0, col: 0), GridCell(row: 5, col: 4)]
        for kind in AnimationKind.allCases {
            engine.trigger(kind, cells: cells, at: 0)
        }
        XCTAssertEqual(engine.advance(to: 5), [])
        XCTAssertEqual(engine.sprites, before)
        XCTAssertTrue(layout.allCells.allSatisfy { !engine.isBusy($0) })
    }

    func testSameSeedSameWall() {
        let (a, _) = makeEngine(seed: 9)
        let (b, _) = makeEngine(seed: 9)
        for n in 1...(60 * 60) {
            XCTAssertEqual(a.advance(to: Double(n) * frame), b.advance(to: Double(n) * frame))
        }
        XCTAssertEqual(a.sprites, b.sprites)
    }

    func testLongRunInvariants() {
        for seed in UInt64(1)...3 {
            assertLongRun(seed: seed, pool: nil, duration: 600, uniqueAlbums: true)
        }
    }

    func testLongRunSingleAlbum() {
        assertLongRun(seed: 1, pool: ["a"], duration: 120, uniqueAlbums: false)
    }
}
