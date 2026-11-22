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
///
/// The real screensaver shows the cache of the music folder chosen in its
/// options and scans that folder at every start. `stopAnimation`, and the
/// `com.apple.screensaver.willstop` notification the host sends even when it
/// forgets to stop the view, end the scan and let go of the wall, its images
/// and the folder, so the process does nothing once the screensaver is over.
@objc(AlbumArtworkView)
final class AlbumArtworkView: ScreenSaverView {
    /// Set by the TestHost before it creates the view; `nil` in the real screensaver.
    static var hostOverride: HostOverride?

    /// After a longer pause between two frames (the screensaver was paused, the
    /// Mac slept) a fresh wall starts, instead of every missed tick at once.
    private static let maxFrameGap: TimeInterval = 1
    private static let statsInterval: TimeInterval = 10
    private static let willStop = Notification.Name("com.apple.screensaver.willstop")

    private enum Phase {
        /// Nothing to show: the wall stays black.
        case idle
        /// The engine starts with these albums, one per cell, once all their images are ready.
        case waiting([AlbumID], since: TimeInterval)
        case running
    }

    private var settings = WallSettings()
    private var layout: GridLayout?
    private var store: CoverImageStore?
    /// The albums of the music folder's cache; nil for `HostOverride.covers`.
    private var library: LibraryService?
    /// Whether the music folder can be read, for the hint; nil while it is
    /// being resolved.
    private var folder: FolderStatus?
    /// The chosen folder as `FolderAccess.resolve` gave it, with its access;
    /// nil when it cannot be read, and in the TestHost.
    private var folderURL: URL?
    /// Counts tear-downs, so a folder resolved for an earlier start is let go
    /// of instead of scanned.
    private var generation = 0
    /// The quiet line in the middle of a wall that has not started.
    private var hint: CATextLayer?
    private var optionsSheet: OptionsSheet?
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
        start(with: SaverSettings.load())
    }

    override func stopAnimation() {
        tearDown(cancellingScan: true)
        super.stopAnimation()
    }

    override var hasConfigureSheet: Bool { true }

    override var configureSheet: NSWindow? {
        if let window = optionsSheet?.window, window.isVisible { return window }
        let service = library ?? Self.cacheDirectory(for: Self.hostOverride).map(LibraryService.shared)
        let sheet = OptionsSheet(settings: SaverSettings.load(), service: service) { [weak self] settings in
            self?.optionsDone(settings)
        }
        optionsSheet = sheet
        return sheet.window
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

    // MARK: - Start and stop

    /// Shows the wall from the cache at once, then scans the music folder. The
    /// real screensaver resolves the folder in the background first: a disk
    /// or share that is slow to answer must not keep the cached wall waiting.
    /// A start without a stop before it first lets go of what the last one set up.
    private func start(with saved: SaverSettings) {
        tearDown(cancellingScan: false)
        settings = saved.wall
        DistributedNotificationCenter.default().addObserver(
            self, selector: #selector(screensaverWillStop(_:)), name: Self.willStop, object: nil)
        setUpWall()
        switch Self.hostOverride {
        case nil:
            let began = CACurrentMediaTime(), generation = self.generation
            FolderAccess.resolve(saved) { [weak self] status, url in
                let waited = (CACurrentMediaTime() - began) * 1000
                guard let self, self.generation == generation else {
                    // Stopped (or started again) meanwhile: nothing to scan for.
                    if let url { FolderAccess.stopAccessing(url) }
                    Logger.scan.notice("folder: resolved after the wall stopped; let go")
                    return
                }
                Logger.scan.notice("""
                    folder: \(String(describing: status), privacy: .public) for the wall, \
                    resolved in \(waited, format: .fixed(precision: 0), privacy: .public) ms
                    """)
                self.folderResolved(status, url)
            }
        case let .music(root, cache: _):
            var isFolder: ObjCBool = false
            let exists = FileManager.default.fileExists(atPath: root.path, isDirectory: &isFolder)
            folder = exists && isFolder.boolValue ? .available : .unavailable
            library?.scan(root: root)
        case .covers:
            folder = .available
        }
        updateHint()
    }

    /// The real screensaver's folder is known: scan it if it can be read.
    private func folderResolved(_ status: FolderStatus, _ url: URL?) {
        folder = status
        folderURL = url
        if let library, let url { library.scan(root: url) }
        updateHint()
    }

    /// Lets go of the wall, its images, the hint and the folder. Safe to call
    /// again: what is gone stays gone.
    private func tearDown(cancellingScan: Bool) {
        // A folder still being resolved is let go of when it arrives.
        generation += 1
        DistributedNotificationCenter.default().removeObserver(self, name: Self.willStop, object: nil)
        if let library {
            library.removeObserver(self)
            if cancellingScan { library.cancelScan() }
        }
        library = nil
        engine = nil
        wall = nil
        store = nil
        layout = nil
        phase = .idle
        lastFrame = nil
        showHint(nil)
        if let folderURL { FolderAccess.stopAccessing(folderURL) }
        folderURL = nil
        folder = nil
    }

    /// The host may keep the process, and this view, running after the
    /// screensaver ends; this notification still comes. System Settings'
    /// preview keeps showing.
    @objc private func screensaverWillStop(_ notification: Notification) {
        guard Thread.isMainThread else {
            DispatchQueue.main.async { [weak self] in self?.screensaverWillStop(notification) }
            return
        }
        guard !isPreview else { return }
        Logger.wall.notice("screensaver will stop: wall and scan stopped")
        stopAnimation()
    }

    /// The options sheet saved new settings: a running wall starts over with
    /// them. The scan the sheet started for a new folder goes on.
    private func optionsDone(_ saved: SaverSettings) {
        guard isAnimating else { return }
        start(with: saved)
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
        let store = makeStore()
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
        Logger.wall.notice("""
            wall: \(albums, privacy: .public) albums, \(rows, privacy: .public)×\(columns, privacy: .public) \
            covers of \(edge, privacy: .public) px, seed \(seed, privacy: .public)
            """)
        // The cache's albums start the wall at once; with none (the very
        // first time) it waits in `libraryChanged`.
        fill(from: store.pool, since: now)
    }

    /// The cache of the real screensaver and of `HostOverride.music`; nil for a
    /// folder of cover images.
    private static func cacheDirectory(for host: HostOverride?) -> URL? {
        switch host {
        case nil: return CoverCache.defaultDirectory
        case let .music(_, cache: directory): return directory
        case .covers: return nil
        }
    }

    /// The images to show: a music folder's cache, whose albums arrive while
    /// the library scans, or the TestHost's folder of cover images.
    private func makeStore() -> CoverImageStore {
        library = nil
        guard let directory = Self.cacheDirectory(for: Self.hostOverride) else {
            let covers = Self.coverFiles(for: Self.hostOverride)
            let store = CoverImageStore { covers[$0] }
            store.pool = covers.keys.sorted()
            return store
        }
        let library = LibraryService.shared(cacheDirectory: directory)
        let cache = CoverCache(directory: directory)
        let store = CoverImageStore { cache.coverURL(for: $0) }
        store.pool = library.albums
        library.addObserver(self) { [weak self] in self?.libraryChanged() }
        self.library = library
        return store
    }

    /// New albums join the pool, so the next animations can show them. A black
    /// wall starts once there are enough for every cell, or the scan is done
    /// and found at least one (`WallEngine.start` needs one per cell).
    private func libraryChanged() {
        guard let library, let store, let layout else { return }
        store.pool = library.albums
        if case .idle = phase, library.albums.count >= layout.cellCount || !library.isScanning {
            let readable = store.pool.filter { !store.hasFailed($0) }
            if !readable.isEmpty { fill(from: readable, since: CACurrentMediaTime()) }
        }
        updateHint()
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
            if case .idle = phase { Logger.wall.error("wall: none of the cover images can be read") }
            updateHint()
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
        Logger.wall.notice("wall started after \(waited, format: .fixed(precision: 0), privacy: .public) ms")
    }

    /// A fresh engine and wall after a long pause, from the images already
    /// decoded, so the wall does not replay every tick it missed at once.
    private func restart(at now: TimeInterval, after gap: TimeInterval) {
        guard let host = layer, let layout, let store else { return }
        Logger.wall.notice("wall restarted after a \(gap, format: .fixed(precision: 1), privacy: .public) s pause")
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

    // MARK: - The hint

    /// What a wall that has not started waits for: a folder, the scan, covers.
    /// Gone as soon as the wall has albums to start with, and not shown while
    /// the folder is being resolved. Asked for after the wall's phase, the
    /// library or the folder changed, and once a start has begun its scan.
    private func updateHint() {
        guard case .idle = phase, let library, let layout, let folder else {
            showHint(nil)
            return
        }
        showHint(StatusText.hint(folder: folder, albumCount: library.albums.count, isScanning: library.isScanning,
                                 needed: layout.cellCount))
    }

    /// White at 60 %, centred, at most two lines.
    private func showHint(_ text: String?) {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        defer { CATransaction.commit() }
        guard let text, let host = layer else {
            hint?.removeFromSuperlayer()
            hint = nil
            return
        }
        let hint = self.hint ?? CATextLayer()
        guard hint.string as? String != text else { return }
        Logger.wall.notice("hint: \(text, privacy: .public)")
        let size = max(9, bounds.height / 36)
        let font = NSFont.systemFont(ofSize: size)
        let width = bounds.width * 0.8
        let height = (text as NSString).boundingRect(
            with: CGSize(width: width, height: .greatestFiniteMagnitude),
            options: [.usesLineFragmentOrigin, .usesFontLeading], attributes: [.font: font], context: nil
        ).height.rounded(.up)
        hint.string = text
        hint.font = font
        hint.fontSize = size
        hint.foregroundColor = CGColor(gray: 1, alpha: 0.6)
        hint.alignmentMode = .center
        hint.isWrapped = true
        hint.contentsScale = window?.backingScaleFactor ?? NSScreen.main?.backingScaleFactor ?? 2
        hint.frame = CGRect(x: (bounds.width - width) / 2, y: (bounds.height - height) / 2,
                            width: width, height: height)
        // Above the wall's black layer, however the two were added.
        hint.zPosition = 1
        if hint.superlayer == nil { host.addSublayer(hint) }
        self.hint = hint
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
        Logger.wall.notice("""
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
