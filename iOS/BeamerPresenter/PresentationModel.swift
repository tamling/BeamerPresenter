import SwiftUI
import PDFKit

/// One freehand annotation in *unit* coordinates (0…1 of the slide) so it scales
/// across slide sizes and (later) the external display.
struct InkStroke: Identifiable {
    let id = UUID()
    var points: [CGPoint]
    var color: Color
    var width: CGFloat   // fraction of slide width
}

/// Shared state for the presenter: the open document, the current slide, and the
/// per-slide ink.
@MainActor
final class PresentationModel: ObservableObject {
    @Published private(set) var document: PDFDocument?
    @Published private(set) var pageCount = 0
    @Published private(set) var title = ""
    @Published var index = 0

    // Pen
    @Published var penActive = false
    @Published var penColor: Color = .red
    @Published var penWidth: CGFloat = 0.004   // fraction of slide width
    @Published var strokes: [Int: [InkStroke]] = [:]
    @Published var currentStroke: [CGPoint] = []

    // Laser pointer — a transient dot in unit coords, mirrored to the audience.
    // It is not persisted (not part of `strokes`).
    @Published var laserActive = false
    @Published var laserPoint: CGPoint?

    @Published private(set) var recents: [URL] = RecentStore.load()

    private var scopedURL: URL?
    private var thumbCache: [Int: UIImage] = [:]

    // MARK: - Loading

    func open(url: URL) {
        let scoped = url.startAccessingSecurityScopedResource()
        guard let doc = PDFDocument(url: url), doc.pageCount > 0 else {
            if scoped { url.stopAccessingSecurityScopedResource() }
            return
        }
        scopedURL?.stopAccessingSecurityScopedResource()
        scopedURL = scoped ? url : nil

        document = doc
        pageCount = doc.pageCount
        title = url.deletingPathExtension().lastPathComponent
        index = 0
        strokes = [:]
        currentStroke = []
        thumbCache = [:]
        RecentStore.add(url)
        recents = RecentStore.load()
    }

    func close() {
        scopedURL?.stopAccessingSecurityScopedResource()
        scopedURL = nil
        document = nil
        pageCount = 0
        title = ""
        strokes = [:]
        thumbCache = [:]
    }

    // MARK: - Navigation

    func next()     { go(to: index + 1) }
    func previous() { go(to: index - 1) }
    func go(to i: Int) {
        guard pageCount > 0 else { return }
        let clamped = min(max(0, i), pageCount - 1)
        if clamped != index { currentStroke = [] }
        index = clamped
    }

    func aspect(of page: Int) -> CGFloat {
        guard let p = document?.page(at: page) else { return 16.0 / 9.0 }
        let box = p.bounds(for: .cropBox)
        return box.width / max(box.height, 1)
    }

    // MARK: - Ink

    func beginStroke(at p: CGPoint) { currentStroke = [p] }
    func extendStroke(to p: CGPoint) { currentStroke.append(p) }
    func endStroke() {
        defer { currentStroke = [] }
        guard currentStroke.count > 1 else { return }
        strokes[index, default: []].append(InkStroke(points: currentStroke, color: penColor, width: penWidth))
    }
    func undoInk() {
        guard var s = strokes[index], !s.isEmpty else { return }
        s.removeLast()
        strokes[index] = s.isEmpty ? nil : s
    }
    func clearInk() { strokes[index] = nil; currentStroke = [] }
    var hasInk: Bool { !(strokes[index]?.isEmpty ?? true) }

    // MARK: - Tool selection (pen / laser are mutually exclusive)

    func togglePen() {
        penActive.toggle()
        if penActive { laserActive = false; laserPoint = nil }
    }
    func toggleLaser() {
        laserActive.toggle()
        if laserActive { penActive = false } else { laserPoint = nil }
    }

    // MARK: - Laser

    func moveLaser(to p: CGPoint) { laserPoint = p }
    func endLaser() { laserPoint = nil }

    // MARK: - Thumbnails

    func thumbnail(_ i: Int, height: CGFloat = 90) -> UIImage? {
        guard let page = document?.page(at: i) else { return nil }
        if let cached = thumbCache[i] { return cached }
        let box = page.bounds(for: .cropBox)
        let size = CGSize(width: height * (box.width / max(box.height, 1)), height: height)
        let image = page.thumbnail(of: size, for: .cropBox)
        thumbCache[i] = image
        return image
    }
}

/// Recently-opened files, as security-scoped bookmarks in UserDefaults.
enum RecentStore {
    private static let key = "recentBookmarks"
    private static let maxCount = 10

    static func load() -> [URL] {
        let datas = (UserDefaults.standard.array(forKey: key) as? [Data]) ?? []
        return datas.compactMap { data in
            var stale = false
            return try? URL(resolvingBookmarkData: data, bookmarkDataIsStale: &stale)
        }
    }

    static func add(_ url: URL) {
        guard let bookmark = try? url.bookmarkData() else { return }
        var datas = (UserDefaults.standard.array(forKey: key) as? [Data]) ?? []
        // de-dup by resolved path
        datas.removeAll { data in
            var stale = false
            let u = try? URL(resolvingBookmarkData: data, bookmarkDataIsStale: &stale)
            return u?.path == url.path
        }
        datas.insert(bookmark, at: 0)
        if datas.count > maxCount { datas = Array(datas.prefix(maxCount)) }
        UserDefaults.standard.set(datas, forKey: key)
    }
}
