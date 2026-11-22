import Foundation

/// The scanner's cache folder:
///
///     index.json            the LibraryIndex
///     covers/<AlbumID>.jpg  one square cover per album
///     scan.lock             held (flock) by the one scan writing to the folder
///
/// Files are written atomically, so a reader in another process sees the old
/// or the new file, never half of one. `coverURL(for:)` may be used from any
/// thread; the rest belongs to one thread at a time (the scan's).
final class CoverCache {
    /// `Caches/app.beamerpresenter.AlbumArtworkSaver/`, in the screensaver's
    /// container when sandboxed.
    static var defaultDirectory: URL {
        let caches = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        return caches.appendingPathComponent("app.beamerpresenter.AlbumArtworkSaver", isDirectory: true)
    }

    let directory: URL
    private let coversDirectory: URL
    private let indexURL: URL
    private let lockURL: URL
    /// The open `scan.lock` while this cache holds the lock, else -1.
    private var lockDescriptor: Int32 = -1

    init(directory: URL) {
        self.directory = directory
        coversDirectory = directory.appendingPathComponent("covers", isDirectory: true)
        indexURL = directory.appendingPathComponent("index.json", isDirectory: false)
        lockURL = directory.appendingPathComponent("scan.lock", isDirectory: false)
    }

    deinit {
        unlock()
    }

    func coverURL(for album: AlbumID) -> URL {
        coversDirectory.appendingPathComponent(album + ".jpg", isDirectory: false)
    }

    /// The saved index; an empty one if there is none, it cannot be read, or
    /// it has another format version.
    func loadIndex() -> LibraryIndex {
        guard let data = try? Data(contentsOf: indexURL),
              let index = try? JSONDecoder().decode(LibraryIndex.self, from: data),
              index.version == LibraryIndex.currentVersion
        else { return LibraryIndex() }
        return index
    }

    func saveIndex(_ index: LibraryIndex) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = .sortedKeys
        let data = try encoder.encode(index)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try data.write(to: indexURL, options: .atomic)
    }

    func writeCover(_ jpeg: Data, for album: AlbumID) throws {
        try FileManager.default.createDirectory(at: coversDirectory, withIntermediateDirectories: true)
        try jpeg.write(to: coverURL(for: album), options: .atomic)
    }

    func removeCover(_ album: AlbumID) {
        try? FileManager.default.removeItem(at: coverURL(for: album))
    }

    /// Deletes everything in `covers/` that is not the cover of an album in
    /// `keeping`: covers of albums gone from the index, and leftovers of an
    /// interrupted write.
    func removeOrphanCovers(keeping albums: Set<AlbumID>) {
        let files = (try? FileManager.default.contentsOfDirectory(
            at: coversDirectory, includingPropertiesForKeys: nil)) ?? []
        for file in files {
            let name = file.lastPathComponent
            if name.hasSuffix(".jpg"), albums.contains(String(name.dropLast(4))) { continue }
            try? FileManager.default.removeItem(at: file)
        }
    }

    /// Takes `scan.lock` without waiting: false while another scan (in this
    /// process or another) holds it, or when the cache folder cannot be made.
    /// The system lets go of the lock when the process ends, however it ends.
    func tryLock() -> Bool {
        guard (try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)) != nil
        else { return false }
        let descriptor = lockURL.withUnsafeFileSystemRepresentation { path -> Int32 in
            guard let path else { return -1 }
            return open(path, O_RDWR | O_CREAT | O_CLOEXEC, 0o644)
        }
        guard descriptor >= 0 else { return false }
        // flock locks belong to the open file, so a second open in this
        // process is turned away just like another process.
        guard flock(descriptor, LOCK_EX | LOCK_NB) == 0 else {
            close(descriptor)
            return false
        }
        lockDescriptor = descriptor
        return true
    }

    func unlock() {
        guard lockDescriptor >= 0 else { return }
        flock(lockDescriptor, LOCK_UN)
        close(lockDescriptor)
        lockDescriptor = -1
    }
}
