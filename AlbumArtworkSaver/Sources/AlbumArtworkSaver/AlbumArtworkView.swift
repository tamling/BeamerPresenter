import AppKit
import os
import ScreenSaver

/// What the TestHost shows instead of the folder chosen in the screensaver's
/// options. The real screensaver never sets it.
enum HostOverride {
    /// A folder of cover images; each file name without its extension is an album.
    case covers(URL)
    /// A music folder, scanned into the given cache folder.
    case music(URL, cache: URL)
}

/// The screensaver's principal class (`NSPrincipalClass` in Info.plist): a
/// black, layer-backed view showing the cover wall. The engine decides every
/// pose; this view feeds it time and mirrors its sprites into layers.
@objc(AlbumArtworkView)
final class AlbumArtworkView: ScreenSaverView {
    /// Set by the TestHost before it creates the view; `nil` in the real screensaver.
    static var hostOverride: HostOverride?

    /// After a longer pause between two frames (the screensaver was paused, the
    /// Mac slept) a fresh wall starts, instead of every missed tick at once.
    private static let maxFrameGap: TimeInterval = 1
    private static let statsInterval: TimeInterval = 10
    private static let log = Logger(subsystem: "app.beamerpresenter.AlbumArtworkSaver", category: "wall")

    private enum Phase {
        /// Nothing to show: the wall stays black.
        case idle
        /// The engine starts with these albums, one per cell, once all their images are ready.
        case waiting([AlbumID], since: TimeInterval)
        case running
    }

    private let settings = WallSettings()
    private var layout: GridLayout?
    private var store: CoverImageStore?
    private var wall: CoverWall?
    private var engine: WallEngine?
    private var rng = SplitMix64(seed: 0)
    private var phase = Phase.idle
    private var lastFrame: TimeInterval?

    private var statsSince: TimeInterval = 0
    private var frameCount = 0
    private var frameTotal: TimeInterval = 0
    private var frameLongest: TimeInterval = 0

    override init?(frame: NSRect, isPreview: Bool) {
        super.init(frame: frame, isPreview: isPreview)
        configure()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        configure()
    }

    // The view only shows its layer, so AppKit asks for updateLayer() instead
    // of drawing a full-screen backing store.
    override var wantsUpdateLayer: Bool { true }

    override func updateLayer() {
        layer?.backgroundColor = NSColor.black.cgColor
    }

    override func startAnimation() {
        super.startAnimation()
        setUpWall()
    }

    override func animateOneFrame() {
        let begin = CACurrentMediaTime()
        step(at: begin)
        recordFrame(lasting: CACurrentMediaTime() - begin, at: begin)
    }

    private func configure() {
        animationTimeInterval = 1.0 / 60
        wantsLayer = true
    }

    // MARK: - The wall

    private func setUpWall() {
        let now = CACurrentMediaTime()
        wall = nil
        engine = nil
        phase = .idle
        lastFrame = nil
        resetStats(at: now)
        guard let host = layer, bounds.width > 0, bounds.height > 0 else { return }
        let layout = GridLayout(rows: settings.rows, aspect: Double(bounds.width / bounds.height))
        let covers = Self.coverFiles(for: Self.hostOverride)
        let store = CoverImageStore { covers[$0] }
        store.pool = covers.keys.sorted()
        let wall = CoverWall(hostLayer: host, layout: layout, images: store)
        let scale = window?.backingScaleFactor ?? NSScreen.main?.backingScaleFactor ?? 2
        store.pixelEdge = Int((wall.coverEdge * scale).rounded(.up))
        let seed = UInt64.random(in: .min ... .max)
        rng = SplitMix64(seed: seed)
        self.layout = layout
        self.store = store
        self.wall = wall
        engine = WallEngine(layout: layout, settings: settings, source: store, seed: rng.next())
        let albums = store.pool.count, rows = layout.rows, columns = layout.columns, edge = store.pixelEdge
        Self.log.notice("""
            wall: \(albums, privacy: .public) albums, \(rows, privacy: .public)×\(columns, privacy: .public) \
            covers of \(edge, privacy: .public) px, seed \(seed, privacy: .public)
            """)
        fill(from: store.pool, since: now)
    }

    private func step(at now: TimeInterval) {
        let gap = now - (lastFrame ?? now)
        lastFrame = now
        switch phase {
        case .idle:
            break
        case let .waiting(albums, since: since):
            startIfReady(albums, waitingSince: since, at: now)
        case .running:
            guard let engine, let wall else { return }
            if gap > Self.maxFrameGap {
                restart(at: now, after: gap)
            } else {
                wall.apply(engine.advance(to: now), engine: engine)
            }
        }
    }

    /// Picks one album per cell from `pool` and starts decoding them. An empty
    /// pool leaves the wall black: the engine needs an album for every cell.
    private func fill(from pool: [AlbumID], since: TimeInterval) {
        guard let layout, let store else { return }
        let albums = AlbumPicker.initialFill(count: layout.cellCount, pool: pool, using: &rng)
        guard !albums.isEmpty else {
            phase = .idle
            return
        }
        store.prefetch(albums)
        phase = .waiting(albums, since: since)
    }

    /// Starts the engine as soon as every one of `albums` is ready, so the wall
    /// appears whole.
    private func startIfReady(_ albums: [AlbumID], waitingSince since: TimeInterval, at now: TimeInterval) {
        guard let store, let engine, let wall else { return }
        if albums.contains(where: store.hasFailed) {
            // An image that cannot be read never becomes ready: pick again without it.
            fill(from: store.pool.filter { !store.hasFailed($0) }, since: since)
            if case .idle = phase { Self.log.error("wall: none of the cover images can be read") }
            return
        }
        let missing = albums.filter { !store.isReady($0) }
        guard missing.isEmpty else {
            // Skips the ones still decoding; asks again for any the cache dropped.
            store.prefetch(missing)
            return
        }
        engine.start(at: now, initialAlbums: albums)
        wall.apply(engine.sprites.keys.sorted { $0.raw < $1.raw }.map(WallChange.added), engine: engine)
        phase = .running
        let waited = (now - since) * 1000
        Self.log.notice("wall started after \(waited, format: .fixed(precision: 0), privacy: .public) ms")
    }

    /// A fresh engine and wall after a long pause, from the images already
    /// decoded, so the wall does not replay every tick it missed at once.
    private func restart(at now: TimeInterval, after gap: TimeInterval) {
        guard let host = layer, let layout, let store else { return }
        Self.log.notice("wall restarted after a \(gap, format: .fixed(precision: 1), privacy: .public) s pause")
        // One transaction, so the new covers replace the old ones in one frame.
        CATransaction.begin()
        defer { CATransaction.commit() }
        wall = CoverWall(hostLayer: host, layout: layout, images: store)
        engine = WallEngine(layout: layout, settings: settings, source: store, seed: rng.next())
        let ready = store.pool.filter(store.isReady)
        fill(from: ready.isEmpty ? store.pool : ready, since: now)
        if case let .waiting(albums, since: since) = phase {
            startIfReady(albums, waitingSince: since, at: now)
        }
    }

    // MARK: - Frame time

    private func resetStats(at now: TimeInterval) {
        statsSince = now
        frameCount = 0
        frameTotal = 0
        frameLongest = 0
    }

    /// Logs the mean and longest `animateOneFrame` every `statsInterval`.
    private func recordFrame(lasting duration: TimeInterval, at now: TimeInterval) {
        frameCount += 1
        frameTotal += duration
        frameLongest = max(frameLongest, duration)
        let elapsed = now - statsSince
        guard elapsed >= Self.statsInterval else { return }
        let frames = frameCount, mean = frameTotal / Double(frameCount) * 1000, longest = frameLongest * 1000
        let covers = engine?.sprites.count ?? 0
        Self.log.notice("""
            frames: \(frames, privacy: .public) in \(elapsed, format: .fixed(precision: 1), privacy: .public) s, \
            mean \(mean, format: .fixed(precision: 3), privacy: .public) ms, \
            longest \(longest, format: .fixed(precision: 3), privacy: .public) ms, \
            \(covers, privacy: .public) covers
            """)
        resetStats(at: now)
    }

    // MARK: - Covers

    /// The TestHost's `--covers` folder: each `*.jpg`, `*.jpeg` or `*.png` in it
    /// is one album, named by the file name without its extension.
    private static func coverFiles(for host: HostOverride?) -> [AlbumID: URL] {
        guard case let .covers(folder) = host else { return [:] }
        let files = (try? FileManager.default.contentsOfDirectory(
            at: folder, includingPropertiesForKeys: nil, options: .skipsHiddenFiles)) ?? []
        var covers: [AlbumID: URL] = [:]
        for file in files.sorted(by: { $0.lastPathComponent < $1.lastPathComponent })
        where ["jpg", "jpeg", "png"].contains(file.pathExtension.lowercased()) {
            let album = file.deletingPathExtension().lastPathComponent
            if covers[album] == nil { covers[album] = file }
        }
        return covers
    }
}
