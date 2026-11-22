import Foundation

/// The albums of one cover cache, shared by every view in the process (one per
/// screen, plus the preview), and the one scan that keeps it up to date.
///
/// Main thread only. The scan runs on a background queue at utility priority;
/// what it finds is published here on the main thread, and observers are told.
final class LibraryService {
    private static var services: [String: LibraryService] = [:]

    /// The service for `cacheDirectory`, made on first use with the albums its
    /// index already knows, so a wall can start from the cache at once.
    static func shared(cacheDirectory: URL) -> LibraryService {
        dispatchPrecondition(condition: .onQueue(.main))
        let key = cacheDirectory.standardizedFileURL.path
        if let service = services[key] { return service }
        let service = LibraryService(cache: CoverCache(directory: cacheDirectory))
        services[key] = service
        return service
    }

    /// Every album with a cover in the cache: the index's at first, then each
    /// new one as the scan writes its cover, then the index's again after a scan.
    private(set) var albums: [AlbumID]
    private(set) var isScanning = false
    private(set) var lastCompleteScan: Date?

    private struct Observer {
        weak var owner: AnyObject?
        let onChange: () -> Void
    }

    private let cache: CoverCache
    private let queue = DispatchQueue(label: "app.beamerpresenter.AlbumArtworkSaver.scan", qos: .utility,
                                      autoreleaseFrequency: .workItem)
    private var observers: [Observer] = []
    /// The running scan's stop flag.
    private var stop: StopFlag?

    private init(cache: CoverCache) {
        self.cache = cache
        let index = cache.loadIndex()
        albums = index.albumIDs
        lastCompleteScan = index.lastCompleteScan
    }

    /// Calls `onChange` on the main thread whenever `albums`, `isScanning` or
    /// `lastCompleteScan` change, until `owner` goes away. One entry per owner:
    /// adding again replaces it. `owner` is held weakly; `onChange` must not
    /// hold it strongly either.
    func addObserver(_ owner: AnyObject, onChange: @escaping () -> Void) {
        dispatchPrecondition(condition: .onQueue(.main))
        observers.removeAll { $0.owner == nil || $0.owner === owner }
        observers.append(Observer(owner: owner, onChange: onChange))
    }

    /// Stops calling `owner`'s `onChange`; does nothing if `owner` is not observing.
    func removeObserver(_ owner: AnyObject) {
        dispatchPrecondition(condition: .onQueue(.main))
        observers.removeAll { $0.owner == nil || $0.owner === owner }
    }

    /// Scans `root` in the background. Does nothing while a scan runs, so the
    /// views of a process, which share this service, start one scan between
    /// them; scans in other processes are kept out by the cache's lock.
    func scan(root: URL) {
        dispatchPrecondition(condition: .onQueue(.main))
        guard !isScanning else { return }
        isScanning = true
        let stop = StopFlag()
        self.stop = stop
        notify()
        let scanner = LibraryScanner(root: root, cache: cache)
        // The scan keeps the service; services live as long as the process anyway.
        queue.async {
            // The scanner logs its summary.
            _ = scanner.run(isCancelled: { stop.isSet }, onNewAlbums: { albums in
                DispatchQueue.main.async { self.add(albums) }
            })
            // What the scan left: removed albums disappear, the date is set.
            let index = self.cache.loadIndex()
            DispatchQueue.main.async { self.finish(index) }
        }
    }

    /// Asks the running scan to stop after the file it is reading; what it
    /// read so far is kept.
    func cancelScan() {
        dispatchPrecondition(condition: .onQueue(.main))
        stop?.set()
    }

    // MARK: - Main thread

    private func add(_ new: [AlbumID]) {
        let known = Set(albums)
        let added = new.filter { !known.contains($0) }
        guard !added.isEmpty else { return }
        albums += added
        notify()
    }

    private func finish(_ index: LibraryIndex) {
        albums = index.albumIDs
        lastCompleteScan = index.lastCompleteScan
        isScanning = false
        stop = nil
        notify()
    }

    private func notify() {
        observers.removeAll { $0.owner == nil }
        for observer in observers { observer.onChange() }
    }
}

/// A flag set on the main thread and read by the scan.
private final class StopFlag {
    private let lock = NSLock()
    private var value = false

    var isSet: Bool {
        lock.lock()
        defer { lock.unlock() }
        return value
    }

    func set() {
        lock.lock()
        value = true
        lock.unlock()
    }
}
