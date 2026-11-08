import SwiftUI
import PDFKit
import Combine
import BeamerCore

/// Active drawing tool on the slide.
enum Tool { case none, pen, laser }

/// The fixed pen palette, shared by the in-app colour swatches and the menu bar.
enum PenPalette {
    static let colors: [(name: String, color: Color)] =
        [("Red", PenInk.red), ("Yellow", PenInk.yellow),
         ("Green", PenInk.green), ("Blue", PenInk.blue)]
}

/// One freehand annotation, stored in *unit* coordinates (0...1 of the slide
/// rect) and a *relative* width so it scales identically on the small presenter
/// pane and the full audience screen.
struct Stroke: Identifiable {
    let id = UUID()
    var points: [CGPoint]
    var color: Color
    var width: CGFloat   // fraction of slide width
}

/// Remembers the last viewed slide per presentation (keyed by file path), so
/// reopening a deck resumes where you left off instead of starting over.
enum SlidePositions {
    private static let key = "lastSlideByPath"

    static func save(_ index: Int, for url: URL) {
        var map = UserDefaults.standard.dictionary(forKey: key) as? [String: Int] ?? [:]
        map[url.path] = index
        UserDefaults.standard.set(map, forKey: key)
    }

    static func restore(for url: URL, pageCount: Int) -> Int {
        let map = UserDefaults.standard.dictionary(forKey: key) as? [String: Int] ?? [:]
        return min(max(0, map[url.path] ?? 0), max(0, pageCount - 1))
    }

    /// Drops entries whose files no longer exist (run once at launch, so the
    /// map doesn't grow forever).
    static func prune() {
        guard var map = UserDefaults.standard.dictionary(forKey: key) as? [String: Int],
              !map.isEmpty else { return }
        let dead = map.keys.filter { !FileManager.default.fileExists(atPath: $0) }
        guard !dead.isEmpty else { return }
        dead.forEach { map[$0] = nil }
        UserDefaults.standard.set(map, forKey: key)
    }
}

/// Where the current deck's speaker notes come from (shown in the console's
/// notes placeholders).
enum NotesSource: Equatable {
    case none
    case splitPDF                  // right half of a notes-layout PDF
    case tex(fileName: String?)    // `\note{}` text; nil = the exact `.tex` is not known
    case pptx(fileName: String)    // PowerPoint speaker notes
}

/// Single source of truth shared by both windows. A keypress or click mutates
/// state here and the presenter + audience views update in lockstep.
final class PresentationState: ObservableObject {
    @Published private(set) var sourceURL: URL? {        // the opened PDF on disk
        didSet { Self.openDeckURL = sourceURL }
    }
    /// The deck open right now (app-wide), so exporters can refuse to write
    /// over it even when a caller forgets to pass it.
    private(set) static var openDeckURL: URL?
    @Published private(set) var slideDoc: PDFDocument?   // left half (or full page)
    @Published private(set) var notesDoc: PDFDocument?   // right half, nil for plain PDFs

    // Translated twin deck (e.g. the English version of Norwegian slides):
    // shown in the *console* instead of the audience deck while enabled —
    // the audience always sees the primary deck.
    @Published private(set) var referenceDoc: PDFDocument?
    @Published var showReference = false
    var hasReference: Bool { referenceDoc != nil }
    @Published private(set) var textNotes: [Int: String] = [:]   // notes parsed from a sibling .tex
    @Published private(set) var notesSource: NotesSource = .none
    @Published private(set) var pageCount: Int = 0
    @Published private(set) var isLoaded: Bool = false

    /// True when this deck has any notes at all — either a PDF notes column or
    /// `\note{}` text read from the `.tex` source.
    var hasNotes: Bool { notesDoc != nil || !textNotes.isEmpty }
    @Published private(set) var title: String = ""
    @Published private(set) var slideAspect: CGFloat = 16.0 / 9.0

    @Published var index: Int = 0
    @Published var blackout: Bool = false {
        didSet {
            // A deck that opened blacked out starts its clock on the first
            // un-blackout, i.e. when the talk actually begins.
            if oldValue && !blackout && timerAwaitsUnblackout {
                timerAwaitsUnblackout = false
                startDate = Date()
                timerRunning = true
            }
        }
    }
    @Published var showOverview: Bool = false
    @Published var scratch: String = ""          // free-form notes, saved next to the PDF as .txt

    // Elapsed timer with start/stop/reset.
    @Published private(set) var timerRunning = true
    @Published private(set) var startDate = Date()   // start of the current running segment
    private var accumulated: TimeInterval = 0        // time banked from previous segments
    /// The deck opened blacked out and the timer waits for the first un-blackout.
    /// Cleared once that happens, or as soon as the user starts/resets the timer.
    private var timerAwaitsUnblackout = false

    /// Total elapsed presentation time, accounting for pauses.
    var elapsedSeconds: TimeInterval {
        timerRunning ? accumulated + Date().timeIntervalSince(startDate) : accumulated
    }

    /// Optional lecture target in minutes (0 = off). A normal lecture slot is
    /// 45 min; a double slot is 90 min (2 × 45). Persisted across launches.
    @Published var lectureMinutes: Int = UserDefaults.standard.integer(forKey: "lectureMinutes") {
        didSet { UserDefaults.standard.set(lectureMinutes, forKey: "lectureMinutes") }
    }

    /// Seconds left until the lecture target (negative once over), or nil if off.
    var remainingSeconds: TimeInterval? {
        lectureMinutes > 0 ? TimeInterval(lectureMinutes * 60) - elapsedSeconds : nil
    }

    /// Whiteboard appearance on screen: a white board or the dark Night board.
    /// Persisted across launches. The PDF/board export always stays light.
    @Published var boardLight: Bool = UserDefaults.standard.bool(forKey: "boardLight") {
        didSet { UserDefaults.standard.set(boardLight, forKey: "boardLight") }
    }

    /// The style the on-screen board renders in (presenter + audience).
    var boardStyle: BoardStyle { boardLight ? .light : .dark }

    // Mentimeter: when active, the audience screen shows the live present view.
    @Published var mentiActive = false
    @Published var mentiPresentURL: URL?

    func startMenti(_ url: URL) { mentiPresentURL = url; mentiActive = true }
    func stopMenti() { mentiActive = false }

    // Annotation / laser
    @Published var tool: Tool = .none
    @Published var penColor: Color = .red
    @Published var strokes: [Int: [Stroke]] = [:] { didSet { hasUnsavedChanges = true } }
    /// Ink removed by the last Clear, per slide: the next Undo on that slide
    /// brings it all back, as long as nothing new was drawn there since.
    private var clearedStrokes: [Int: [Stroke]] = [:]
    @Published var currentStroke: [CGPoint] = []
    @Published var laserPoint: CGPoint?

    // Whiteboards (blank scratch slides). `activeBoardIndex == nil` means the
    // deck is showing; a non-nil index overlays that board on both screens.
    @Published var boards: [Whiteboard] = [] { didSet { hasUnsavedChanges = true } }
    @Published var activeBoardIndex: Int?
    @Published var selectedItemID: UUID?
    @Published var boardStroke: [CGPoint] = []   // in-progress ink on the board

    /// True once the deck has unexported ink or whiteboard edits. Set whenever the
    /// strokes/boards change, cleared on load, unload, and a successful export — so
    /// the app can offer to save before the deck is closed or discarded.
    @Published private(set) var hasUnsavedChanges = false

    /// Call after the deck has been exported to a PDF: the edits are now saved.
    func markSaved() { hasUnsavedChanges = false }

    /// Bounded thumbnail cache (pages × size buckets would otherwise pile up
    /// across zoom levels for the whole session).
    private let thumbCache: NSCache<NSString, NSImage> = {
        let cache = NSCache<NSString, NSImage>()
        cache.countLimit = 600
        return cache
    }()

    // MARK: - Loading

    @discardableResult
    func load(url: URL) -> Bool {
        // Validate everything *before* touching any state, so a failed load of
        // a second deck can't leave half-mutated state behind (wrong sourceURL
        // would also mis-key the saved slide positions).
        guard let probe = PDFDocument(url: url), probe.pageCount > 0 else { return false }
        let split = PDFModel.isNotesLayout(probe)
        guard let doc = PDFModel.croppedDocument(url: url, half: split ? .left : .full),
              let first = doc.page(at: 0) else { return false }
        let notes = split ? PDFModel.croppedDocument(url: url, half: .right) : nil

        if isLoaded { recordCurrentSession(); saveScratch() }   // finish the previous deck first
        sourceURL = url
        slideDoc = doc
        notesDoc = notes

        let box = first.bounds(for: .cropBox)
        slideAspect = box.width / max(box.height, 1)
        pageCount = doc.pageCount
        // A split deck already carries its notes in the right half; for a plain
        // PDF, fall back to `\note{}` text from a sibling `.tex`, then to
        // PowerPoint speaker notes from a sibling `.pptx` (converted decks).
        if split {
            textNotes = [:]
            notesSource = .splitPDF
        } else {
            let tex = TexNotes.load(forPDF: url, pageCount: doc.pageCount)
            if !tex.isEmpty {
                textNotes = tex
                // TexNotes may fall back to another `.tex` in the folder and
                // doesn't say which one it used, so no file name is claimed.
                notesSource = .tex(fileName: nil)
            } else {
                textNotes = PptxNotes.load(forPDF: url, pageCount: doc.pageCount)
                notesSource = textNotes.isEmpty ? .none : .pptx(fileName:
                    url.deletingPathExtension().appendingPathExtension("pptx").lastPathComponent)
            }
        }
        title = url.deletingPathExtension().lastPathComponent
        loadScratch()
        thumbCache.removeAllObjects()
        strokes.removeAll()
        clearedStrokes.removeAll()
        currentStroke = []
        laserPoint = nil
        tool = .none
        boards.removeAll()
        activeBoardIndex = nil
        selectedItemID = nil
        boardStroke = []
        // Resume where this deck was left last time (first slide for new decks).
        index = SlidePositions.restore(for: url, pageCount: doc.pageCount)
        // A translated twin deck next to the file (talk-no.pdf ↔ talk-en.pdf)
        // is picked up automatically; `E` toggles it in the console.
        referenceDoc = nil
        showReference = false
        if let twin = ReferenceDeck.autoDetect(for: url, pageCount: doc.pageCount) {
            loadReference(url: twin)
        }
        // Start blacked out (per Settings) only when starting fresh — when the
        // deck resumes mid-presentation, jump straight to the slide instead of
        // the clock screen.
        timerAwaitsUnblackout = false   // (before touching blackout: no stale start)
        blackout = index == 0
            && (UserDefaults.standard.object(forKey: "startBlackedOut") as? Bool ?? true)
        showOverview = false
        accumulated = 0
        startDate = Date()
        // Opening blacked out holds the timer until the talk starts (first
        // un-blackout); otherwise it runs from the moment the deck is loaded.
        timerRunning = !blackout
        timerAwaitsUnblackout = blackout
        isLoaded = true
        hasUnsavedChanges = false   // a freshly loaded deck has nothing to save yet
        return true
    }

    func unload() {
        recordCurrentSession()
        saveScratch()
        scratch = ""
        sourceURL = nil
        slideDoc = nil
        notesDoc = nil
        referenceDoc = nil
        showReference = false
        textNotes = [:]
        notesSource = .none
        pageCount = 0
        title = ""
        thumbCache.removeAllObjects()
        strokes.removeAll()
        clearedStrokes.removeAll()
        currentStroke = []
        laserPoint = nil
        tool = .none
        boards.removeAll()
        activeBoardIndex = nil
        selectedItemID = nil
        boardStroke = []
        index = 0
        timerAwaitsUnblackout = false
        blackout = false
        showOverview = false
        isLoaded = false
        hasUnsavedChanges = false
        mentiActive = false
        mentiPresentURL = nil
    }

    // MARK: - Reference (translated twin) deck

    /// Loads a translated twin deck shown in the console while `showReference`
    /// is on. Split-notes twins contribute their slide half only.
    @discardableResult
    func loadReference(url: URL) -> Bool {
        guard let probe = PDFDocument(url: url), probe.pageCount > 0 else { return false }
        let split = PDFModel.isNotesLayout(probe)
        referenceDoc = PDFModel.croppedDocument(url: url, half: split ? .left : .full)
        showReference = referenceDoc != nil
        return showReference
    }

    func clearReference() {
        referenceDoc = nil
        showReference = false
    }

    func toggleReference() {
        guard hasReference else { return }
        showReference.toggle()
    }

    // MARK: - Scratch notes & session stats

    /// Free-form scratch notes are stored as `<pdf-name>.notes.txt` next to the PDF.
    private var scratchURL: URL? {
        sourceURL?.deletingPathExtension().appendingPathExtension("notes").appendingPathExtension("txt")
    }

    /// The notes file existed when the deck was loaded (and was read).
    private var scratchExisted = false
    /// The notes file existed but could not be read — it is never written or removed.
    private var scratchUnreadable = false
    /// The app created the notes file in this session, so it may remove it again
    /// once the notes are emptied. A file that existed before is never deleted.
    private var scratchCreatedHere = false
    /// Encoding the existing file was read with; saving keeps it when possible.
    private var scratchEncoding: String.Encoding = .utf8

    private func loadScratch() {
        scratch = ""
        scratchExisted = false
        scratchUnreadable = false
        scratchCreatedHere = false
        scratchEncoding = .utf8
        guard let url = scratchURL, FileManager.default.fileExists(atPath: url.path) else { return }
        guard let data = try? Data(contentsOf: url) else {
            scratchUnreadable = true
            return
        }
        if let text = String(data: data, encoding: .utf8) {
            scratch = text
        } else if let text = String(data: data, encoding: .isoLatin1) {   // older, non-UTF-8 notes
            scratch = text
            scratchEncoding = .isoLatin1
        } else {
            scratchUnreadable = true
            return
        }
        scratchExisted = true
    }

    func saveScratch() {
        guard let url = scratchURL, !scratchUnreadable else { return }
        let fm = FileManager.default
        if scratch.isEmpty {
            if scratchCreatedHere {
                try? fm.removeItem(at: url)
                scratchCreatedHere = false
            } else if scratchExisted {
                // The user cleared notes they had before: empty the file, keep it.
                try? scratch.write(to: url, atomically: true, encoding: scratchEncoding)
            }
        } else {
            let existed = fm.fileExists(atPath: url.path)
            var saved = (try? scratch.write(to: url, atomically: true, encoding: scratchEncoding)) != nil
            if !saved, scratchEncoding != .utf8 {
                // Text the original encoding can't hold is saved as UTF-8 instead.
                saved = (try? scratch.write(to: url, atomically: true, encoding: .utf8)) != nil
                if saved { scratchEncoding = .utf8 }
            }
            if saved && !existed && !scratchExisted { scratchCreatedHere = true }
        }
    }

    /// Records the elapsed time of the current deck into the usage stats.
    func recordCurrentSession() {
        guard isLoaded else { return }
        Stats.record(seconds: elapsedSeconds)
        accumulated = 0           // so a later call doesn't double-count
        startDate = Date()
    }

    // MARK: - Navigation

    func next()      { go(to: index + 1) }
    func previous()  { go(to: index - 1) }
    func goToFirst() { go(to: 0) }
    func goToLast()  { go(to: pageCount - 1) }

    func go(to i: Int) {
        guard pageCount > 0 else { return }
        if activeBoardIndex != nil { hideBoard() }   // navigating slides leaves the board
        let clamped = min(max(0, i), pageCount - 1)
        if clamped != index {
            currentStroke = []
            laserPoint = nil
            index = clamped
            // Persist only on an actual change — not on every key repeat at
            // the first/last slide.
            if let url = sourceURL { SlidePositions.save(clamped, for: url) }
        }
    }

    func resetTimer() {
        timerAwaitsUnblackout = false   // a manual reset overrides the auto-start
        accumulated = 0
        startDate = Date()
    }

    /// Pauses or resumes the elapsed timer.
    func toggleTimer() {
        timerAwaitsUnblackout = false   // the user took over the timer
        if timerRunning {
            accumulated += Date().timeIntervalSince(startDate)
            timerRunning = false
        } else {
            startDate = Date()
            timerRunning = true
        }
    }

    // MARK: - Tools / annotations

    func toggleTool(_ t: Tool) {
        tool = (tool == t) ? .none : t
        if tool != .laser { laserPoint = nil }
        if tool != .pen { currentStroke = [] }
    }

    func beginStroke(at p: CGPoint) { currentStroke = [p] }
    func extendStroke(to p: CGPoint) { currentStroke.append(p) }

    func endStroke(width: CGFloat = 0.004) {
        defer { currentStroke = [] }
        guard currentStroke.count > 1 else { return }
        strokes[index, default: []].append(Stroke(points: currentStroke, color: penColor, width: width))
        clearedStrokes[index] = nil   // new ink: the cleared strokes can't come back
    }

    func setLaser(_ p: CGPoint?) { laserPoint = p }

    /// Undo / clear / "has ink" route to the active board when one is showing,
    /// so the control bar and keyboard shortcuts work in both contexts.
    func undoStroke() {
        if activeBoardIndex != nil { boardUndo(); return }
        // Right after a Clear, Undo restores everything it removed.
        if let restored = clearedStrokes.removeValue(forKey: index) {
            strokes[index] = restored
            return
        }
        guard var s = strokes[index], !s.isEmpty else { return }
        s.removeLast()
        strokes[index] = s.isEmpty ? nil : s
    }

    func clearStrokes() {
        if activeBoardIndex != nil { boardClearInk(); return }
        if let s = strokes[index], !s.isEmpty { clearedStrokes[index] = s }
        strokes[index] = nil
        currentStroke = []
    }

    var hasInkOnCurrentSlide: Bool {
        if let board = activeBoard { return !board.strokes.isEmpty }
        return !(strokes[index]?.isEmpty ?? true)
    }

    /// Undo has something to do: ink to remove, or a Clear on this slide to revert.
    var canUndoInk: Bool {
        hasInkOnCurrentSlide || (activeBoardIndex == nil && clearedStrokes[index] != nil)
    }

    // MARK: - Whiteboards

    var activeBoard: Whiteboard? {
        guard let i = activeBoardIndex, boards.indices.contains(i) else { return nil }
        return boards[i]
    }

    var isBoardActive: Bool { activeBoardIndex != nil }

    /// True when there's nothing drawn or placed on the active board yet.
    var activeBoardIsEmpty: Bool {
        guard let board = activeBoard else { return true }
        return board.strokes.isEmpty && board.items.isEmpty
    }

    /// True when the deck has any ink or whiteboards worth exporting.
    var hasAnnotations: Bool {
        !boards.isEmpty || strokes.values.contains { !$0.isEmpty }
    }

    var selectedItem: BoardItem? {
        guard let id = selectedItemID else { return nil }
        return activeBoard?.items.first { $0.id == id }
    }

    func toggleBoard() { isBoardActive ? hideBoard() : showBoards() }

    /// Shows a board, creating the first one on demand.
    func showBoards() {
        if boards.isEmpty {
            addBoard()
        } else {
            activeBoardIndex = min(activeBoardIndex ?? boards.count - 1, boards.count - 1)
        }
    }

    func hideBoard() {
        activeBoardIndex = nil
        selectedItemID = nil
        boardStroke = []
    }

    func addBoard() {
        boards.append(Whiteboard(name: "Whiteboard \(boards.count + 1)", slideIndex: index))
        activeBoardIndex = boards.count - 1
        selectedItemID = nil
        boardStroke = []
    }

    func nextBoard() {
        guard let i = activeBoardIndex, i + 1 < boards.count else { return }
        activeBoardIndex = i + 1
        selectedItemID = nil
    }

    func previousBoard() {
        guard let i = activeBoardIndex, i > 0 else { return }
        activeBoardIndex = i - 1
        selectedItemID = nil
    }

    func deleteActiveBoard() {
        guard let i = activeBoardIndex else { return }
        boards.remove(at: i)
        activeBoardIndex = boards.isEmpty ? nil : min(i, boards.count - 1)
        selectedItemID = nil
        boardStroke = []
    }

    private func mutateActiveBoard(_ change: (inout Whiteboard) -> Void) {
        guard let i = activeBoardIndex, boards.indices.contains(i) else { return }
        change(&boards[i])
    }

    // Items
    func addItem(_ kind: BoardItem.Kind) {
        let item = BoardItem.makeDefault(kind)
        mutateActiveBoard { $0.items.append(item) }
        selectedItemID = item.id
    }

    /// Inserts a text item pre-filled with `text` (used by the quick commands).
    func addTextItem(_ text: String) {
        var item = BoardItem.makeDefault(.text)
        item.text = text
        mutateActiveBoard { $0.items.append(item) }
        selectedItemID = item.id
    }

    func deleteItem(_ id: UUID) {
        mutateActiveBoard { $0.items.removeAll { $0.id == id } }
        if selectedItemID == id { selectedItemID = nil }
    }

    /// Adds an empty table of the chosen size (rows × columns), like the grid
    /// picker in Apple Notes.
    func addTable(rows: Int, columns: Int) {
        let r = max(1, rows), c = max(1, columns)
        let line = Array(repeating: "", count: c).joined(separator: " | ")
        let text = Array(repeating: line, count: r).joined(separator: "\n")
        let width = min(0.9, max(0.3, CGFloat(c) * 0.14))
        let item = BoardItem(kind: .table, center: CGPoint(x: 0.5, y: 0.4), width: width, text: text)
        mutateActiveBoard { $0.items.append(item) }
        selectedItemID = item.id
    }

    func updateItemText(_ id: UUID, _ text: String) {
        mutateActiveBoard { board in
            if let k = board.items.firstIndex(where: { $0.id == id }) { board.items[k].text = text }
        }
    }

    func moveItem(_ id: UUID, to center: CGPoint) {
        mutateActiveBoard { board in
            if let k = board.items.firstIndex(where: { $0.id == id }) {
                board.items[k].center = CGPoint(x: clamp01(center.x), y: clamp01(center.y))
            }
        }
    }

    func scaleItem(_ id: UUID, by factor: CGFloat) {
        mutateActiveBoard { board in
            if let k = board.items.firstIndex(where: { $0.id == id }) {
                board.items[k].width = min(max(0.05, board.items[k].width * factor), 1)
                board.items[k].fontScale = min(max(0.02, board.items[k].fontScale * factor), 0.2)
            }
        }
    }

    /// Sets an item's width (e.g. from a drag handle), scaling its font to match.
    func setItemWidth(_ id: UUID, _ width: CGFloat) {
        mutateActiveBoard { board in
            guard let k = board.items.firstIndex(where: { $0.id == id }) else { return }
            let old = max(board.items[k].width, 0.0001)
            let w = min(max(width, 0.05), 1)
            board.items[k].width = w
            board.items[k].fontScale = min(max(board.items[k].fontScale * (w / old), 0.02), 0.2)
        }
    }

    func deleteSelectedItem() {
        guard let id = selectedItemID else { return }
        mutateActiveBoard { $0.items.removeAll { $0.id == id } }
        selectedItemID = nil
    }

    // Board ink
    func boardBeginStroke(at p: CGPoint) { boardStroke = [p] }
    func boardExtendStroke(to p: CGPoint) { boardStroke.append(p) }

    func boardEndStroke(width: CGFloat = 0.004) {
        defer { boardStroke = [] }
        guard boardStroke.count > 1 else { return }
        let stroke = Stroke(points: boardStroke, color: penColor, width: width)
        mutateActiveBoard { $0.strokes.append(stroke) }
    }

    func boardUndo() {
        mutateActiveBoard { if !$0.strokes.isEmpty { $0.strokes.removeLast() } }
    }

    func boardClearInk() {
        mutateActiveBoard { $0.strokes.removeAll() }
        boardStroke = []
    }

    private func clamp01(_ v: CGFloat) -> CGFloat { min(max(0, v), 1) }

    // MARK: - Thumbnails

    /// Lazily renders and caches a thumbnail of the slide half for the strip and
    /// the overview grid. The cache is keyed by page *and* height, since the
    /// strip's thumbnails are zoomable while the overview uses its own size.
    func thumbnail(at i: Int, height: CGFloat = 110) -> NSImage? {
        guard let doc = slideDoc, i >= 0, i < doc.pageCount, let page = doc.page(at: i) else { return nil }
        let key = "\(i)@\(Int(height))" as NSString
        if let cached = thumbCache.object(forKey: key) { return cached }
        let box = page.bounds(for: .cropBox)
        let aspect = box.width / max(box.height, 1)
        let size = NSSize(width: height * aspect, height: height)
        let image = page.thumbnail(of: size, for: .cropBox)
        thumbCache.setObject(image, forKey: key)
        return image
    }
}
