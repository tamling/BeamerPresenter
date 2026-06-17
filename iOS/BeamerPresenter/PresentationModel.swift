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

    // Speaker notes
    @Published private(set) var notesByPage: [Int: String] = [:]
    @Published private(set) var splitNotes = false   // double-wide "notes on second screen" deck
    @Published private(set) var notesSourceName: String?

    // Presentation timer (stopwatch)
    @Published private(set) var timerRunning = false
    private var timerStartedAt: Date?
    private var timerAccumulated: TimeInterval = 0

    @Published private(set) var recents: [URL] = RecentStore.load()

    /// Seconds elapsed on the presentation timer (live while running).
    var elapsed: TimeInterval {
        timerAccumulated + (timerStartedAt.map { Date().timeIntervalSince($0) } ?? 0)
    }

    func toggleTimer() {
        if timerRunning {
            timerAccumulated = elapsed
            timerStartedAt = nil
        } else {
            timerStartedAt = Date()
        }
        timerRunning.toggle()
    }

    /// Reset to zero; keeps running if it was running.
    func resetTimer() {
        timerAccumulated = 0
        timerStartedAt = timerRunning ? Date() : nil
        objectWillChange.send()
    }

    private var scopedURL: URL?
    private var thumbCache: [Int: UIImage] = [:]

    /// Whether the current deck has any notes to show (parsed `.tex` or a split deck).
    var hasNotes: Bool { splitNotes || !notesByPage.isEmpty }

    /// The note text for a page, if any (split decks carry their notes as the
    /// right-hand image, so they return nil here).
    func note(for i: Int) -> String? { notesByPage[i] }

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
        notesByPage = [:]
        notesSourceName = nil

        detectSplitNotes(doc)
        if !splitNotes {
            // Best-effort: a sibling `.tex` is only reachable when the PDF was
            // opened in place with folder access; otherwise the user can attach
            // one via `loadTexNotes(url:)`.
            let parsed = TexNotes.load(forPDF: url, pageCount: doc.pageCount)
            if !parsed.isEmpty {
                notesByPage = parsed
                notesSourceName = "\(url.deletingPathExtension().lastPathComponent).tex"
            }
        }

        RecentStore.add(url)
        recents = RecentStore.load()
    }

    /// A Beamer "show notes on second screen" deck has double-wide pages (slide on
    /// the left, notes on the right). Detect it from the first page's aspect ratio
    /// and carve the left/right halves into the bleed/trim boxes so PDFView can
    /// display each half independently.
    private func detectSplitNotes(_ doc: PDFDocument) {
        splitNotes = false
        guard let first = doc.page(at: 0) else { return }
        let b = first.bounds(for: .cropBox)
        guard b.height > 0, b.width / b.height > 2.3 else { return }
        splitNotes = true
        notesSourceName = "Embedded notes (split PDF)"
        for i in 0..<doc.pageCount {
            guard let page = doc.page(at: i) else { continue }
            let c = page.bounds(for: .cropBox)
            page.setBounds(CGRect(x: c.minX, y: c.minY, width: c.width / 2, height: c.height), for: .bleedBox)
            page.setBounds(CGRect(x: c.midX, y: c.minY, width: c.width / 2, height: c.height), for: .trimBox)
        }
    }

    /// Attach speaker notes from a `.tex` the user picks explicitly (handles the
    /// sandbox case where the sibling file isn't reachable automatically).
    func loadTexNotes(url: URL) {
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }
        let parsed = TexNotes.load(forPDF: url, pageCount: max(pageCount, 1))
        guard !parsed.isEmpty else { return }
        notesByPage = parsed
        notesSourceName = url.lastPathComponent
    }

    func close() {
        scopedURL?.stopAccessingSecurityScopedResource()
        scopedURL = nil
        document = nil
        pageCount = 0
        title = ""
        strokes = [:]
        thumbCache = [:]
        notesByPage = [:]
        splitNotes = false
        notesSourceName = nil
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

    /// The display box used for the on-screen slide — the left half for split decks.
    var slideBox: PDFDisplayBox { splitNotes ? .bleedBox : .cropBox }

    func aspect(of page: Int) -> CGFloat {
        guard let p = document?.page(at: page) else { return 16.0 / 9.0 }
        let box = p.bounds(for: slideBox)
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
        let box = page.bounds(for: slideBox)
        let size = CGSize(width: height * (box.width / max(box.height, 1)), height: height)
        let image = page.thumbnail(of: size, for: slideBox)
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
