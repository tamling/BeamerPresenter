import SwiftUI
import UIKit
import UniformTypeIdentifiers

struct ContentView: View {
    @EnvironmentObject var model: PresentationModel
    @EnvironmentObject var presenterLink: RemoteLink
    @State private var importing = false

    var body: some View {
        Group {
            if model.document != nil {
                PresenterView(openPicker: { importing = true })
            } else {
                StartView(open: { importing = true })
            }
        }
        .fileImporter(isPresented: $importing, allowedContentTypes: [.pdf]) { result in
            if case .success(let url) = result { model.open(url: url) }
        }
        // Advertise to iPhone remotes while a deck is open; apply their commands.
        .onChange(of: model.document != nil) { hasDoc in
            if hasDoc {
                presenterLink.onCommand = { apply($0) }
                presenterLink.start(title: model.title)
                pushState()
            } else {
                presenterLink.stop()
            }
        }
        .onChange(of: model.index) { _ in pushState() }
        .onChange(of: model.blackout) { _ in pushState() }
        .onChange(of: model.timerRunning) { _ in pushState() }
        .onChange(of: presenterLink.connected) { if $0 { pushState() } }
        .onReceive(Timer.publish(every: 2, on: .main, in: .common).autoconnect()) { _ in
            if presenterLink.connected { pushState() }
        }
    }

    private func apply(_ command: RemoteCommand) {
        switch command {
        case .previous:   model.previous()
        case .next:       model.next()
        case .blackout:   model.toggleBlackout()
        case .toggleTimer: model.toggleTimer()
        case .resetTimer: model.resetTimer()
        }
    }

    private func pushState() {
        guard model.document != nil else { return }
        presenterLink.send(state: PresenterState(
            title: model.title, index: model.index, pageCount: model.pageCount,
            note: model.note(for: model.index) ?? "",
            blackout: model.blackout, timerRunning: model.timerRunning,
            elapsed: Int(model.elapsed)))
    }
}

/// Start screen: branding, open / sample actions, recent files, and a version line.
struct StartView: View {
    @EnvironmentObject var model: PresentationModel
    @State private var showSettings = false
    @State private var showRemote = false
    let open: () -> Void

    var body: some View {
        VStack(spacing: 24) {
            HStack {
                Spacer()
                Button { showSettings = true } label: {
                    Image(systemName: "gearshape").font(.title2)
                }
            }

            Spacer()

            VStack(spacing: 10) {
                Image(systemName: "rectangle.on.rectangle.angled")
                    .font(.system(size: 60)).foregroundStyle(LinearGradient.brand)
                Text("BeamerPresenter")
                    .font(.largeTitle.bold())
                    .foregroundStyle(LinearGradient.brand)
                Text("Present PDF slides on your iPad.").foregroundStyle(.secondary)
            }

            VStack(spacing: 12) {
                Button(action: open) {
                    Label("Open PDF…", systemImage: "folder")
                        .font(.headline).foregroundStyle(.white)
                        .frame(maxWidth: 360).padding(.vertical, 14)
                        .background(LinearGradient.brand, in: RoundedRectangle(cornerRadius: 12))
                }
                .buttonStyle(.plain)

                if let sample = Bundle.main.url(forResource: "sample", withExtension: "pdf") {
                    Button { model.open(url: sample) } label: {
                        Label("Try a sample deck", systemImage: "sparkles").frame(maxWidth: 360)
                    }
                    .buttonStyle(.bordered).controlSize(.large)
                }

                Button { showRemote = true } label: {
                    Label("Use as remote", systemImage: "dot.radiowaves.left.and.right").frame(maxWidth: 360)
                }
                .buttonStyle(.bordered).controlSize(.large)
            }

            if !model.recents.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Recent").font(.headline)
                    ForEach(model.recents.prefix(5), id: \.self) { url in
                        Button { model.open(url: url) } label: {
                            HStack {
                                Image(systemName: "doc.richtext").foregroundStyle(.tint)
                                Text(url.deletingPathExtension().lastPathComponent)
                                    .foregroundStyle(.primary)
                                Spacer()
                                Image(systemName: "chevron.right")
                                    .font(.caption).foregroundStyle(.tertiary)
                            }
                            .padding(.vertical, 10).padding(.horizontal, 14)
                            .background(.quaternary, in: RoundedRectangle(cornerRadius: 10))
                        }
                        .buttonStyle(.plain)
                    }
                }
                .frame(maxWidth: 360)
            }

            Spacer()

            VStack(spacing: 2) {
                Text("BeamerPresenter \(Self.version)").font(.headline)
                Text("\(Self.releaseDate) · by \(Self.author)")
                    .font(.caption).foregroundStyle(.secondary)
            }
            .padding(.bottom, 8)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(40)
        .sheet(isPresented: $showSettings) { SettingsView() }
        .sheet(isPresented: $showRemote) { RemoteView() }
    }

    static let author = "Timo Amling"
    static let releaseDate = "2026-06-17"
    static var version: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "2.0"
    }
}

/// The presenter console: a toolbar, the current slide, and a thumbnail strip.
struct PresenterView: View {
    @EnvironmentObject var model: PresentationModel
    @EnvironmentObject var external: ExternalDisplayManager
    @State private var showOverview = false
    @State private var showNotes = false
    @State private var importingNotes = false
    @State private var exportURL: URL?
    @State private var showShare = false
    @State private var showSettings = false
    @AppStorage("pencilOnly") private var pencilOnly = false
    @AppStorage("blackoutMessage") private var blackoutMessage = ""
    @AppStorage("blackoutShowClock") private var blackoutShowClock = true
    @AppStorage("blackoutImagePath") private var blackoutImagePath = ""
    @State private var importingBlackImage = false
    @State private var showCustomMessage = false
    @State private var customMessage = ""
    @AppStorage("doNotDisturb") private var doNotDisturb = false
    @Environment(\.horizontalSizeClass) private var sizeClass
    @State private var landscape = false
    let openPicker: () -> Void

    /// The full console (current slide + next + notes + own notes) is used on a
    /// wide landscape iPad; portrait keeps the big single-slide layout.
    private var useConsole: Bool { landscape && sizeClass == .regular }

    private var texTypes: [UTType] {
        [UTType(filenameExtension: "tex"), .plainText, .text].compactMap { $0 }
    }

    private var colors: [(String, Color)] { AppColors.palette.map { ($0.name, $0.color) } }

    private let widths: [(String, CGFloat)] = [("Thin", 0.0025), ("Medium", 0.004),
                                              ("Thick", 0.007)]

    var body: some View {
        VStack(spacing: 0) {
            if landscape { controlBar } else { toolbar }
            if model.isBoardActive { boardInsertBar }
            GeometryReader { geo in
                Group {
                    if useConsole {
                        // Wide landscape iPad: the full macOS-style presenter console.
                        PresenterConsole(loadTex: { importingNotes = true })
                    } else {
                        // Portrait / narrow: the big single slide, notes on demand.
                        HStack(spacing: 0) {
                            SlideView()
                                .frame(maxWidth: .infinity, maxHeight: .infinity)
                            if showNotes {
                                NotesPanel(loadTex: { importingNotes = true })
                                    .frame(width: 340)
                                    .transition(.move(edge: .trailing))
                            }
                        }
                    }
                }
                .frame(width: geo.size.width, height: geo.size.height)
                .onAppear { landscape = geo.size.width > geo.size.height }
                .onChange(of: geo.size) { s in landscape = s.width > s.height }
            }
            ThumbnailStrip()
                .frame(height: 96)
        }
        .background(Color.black.ignoresSafeArea())
        .background(
            KeyCommandView(
                onNext: { model.next() },
                onPrevious: { model.previous() },
                onBlackout: { model.toggleBlackout() },
                onEscape: { if model.isBoardActive { model.closeBoard() } })
        )
        .sheet(isPresented: $showOverview) {
            OverviewGrid(isPresented: $showOverview)
        }
        .fileImporter(isPresented: $importingNotes, allowedContentTypes: texTypes) { result in
            if case .success(let url) = result { model.loadTexNotes(url: url) }
        }
        .sheet(isPresented: $showShare) {
            if let url = exportURL { ShareSheet(items: [url]) }
        }
        .sheet(isPresented: $showSettings) { SettingsView() }
        .onAppear { UIApplication.shared.isIdleTimerDisabled = doNotDisturb }
        .onDisappear { UIApplication.shared.isIdleTimerDisabled = false }
        .onChange(of: doNotDisturb) { UIApplication.shared.isIdleTimerDisabled = $0 }
        .fileImporter(isPresented: $importingBlackImage, allowedContentTypes: [.image]) { result in
            if case .success(let url) = result { importBlackImage(url) }
        }
        .alert("Black-out message", isPresented: $showCustomMessage) {
            TextField("Message", text: $customMessage)
            Button("Set") {
                blackoutMessage = customMessage
                if !model.blackout { model.toggleBlackout() }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Shown centred on the audience screen.")
        }
    }

    /// Bake ink + boards into a new PDF in the temp dir and present the share sheet.
    private func exportAndShare() {
        let name = (model.title.isEmpty ? "Presentation" : model.title) + " (annotated).pdf"
        let dest = FileManager.default.temporaryDirectory.appendingPathComponent(name)
        try? FileManager.default.removeItem(at: dest)
        if DeckExporter.export(model: model, to: dest) != nil {
            exportURL = dest
            showShare = true
        }
    }

    private var toolbar: some View {
        HStack(spacing: 14) {
            // Exit to the start screen (distinct icon so it's not confused with
            // the previous-slide arrow).
            Button { model.close() } label: { Image(systemName: "xmark") }

            overflowMenu

            Divider().frame(height: 20)

            // Slide navigation: back / forward.
            Button { model.previous() } label: { Image(systemName: "chevron.left.circle.fill") }
                .disabled(model.index == 0)
            Text("\(model.index + 1) / \(model.pageCount)")
                .font(.headline.monospacedDigit()).frame(minWidth: 72)
            Button { model.next() } label: { Image(systemName: "chevron.right.circle.fill") }
                .disabled(model.index + 1 >= model.pageCount)

            Button { showOverview = true } label: { Image(systemName: "square.grid.2x2") }

            if !landscape {
                Button { withAnimation(.easeInOut(duration: 0.2)) { showNotes.toggle() } } label: {
                    Image(systemName: showNotes ? "note.text.badge.plus" : "note.text")
                }
                .foregroundStyle(showNotes ? Color.accentColor
                                 : (model.hasNotes ? .primary : .secondary))
            }

            blackoutButton
            boardMenu

            Button { doNotDisturb.toggle() } label: {
                Image(systemName: doNotDisturb ? "moon.fill" : "moon")
            }
            .foregroundStyle(doNotDisturb ? Color.accentColor : .primary)

            if external.isConnected {
                Image(systemName: "tv.fill").foregroundStyle(.green)
            }

            Spacer(minLength: 8)
            TimerControls()
            Spacer(minLength: 8)

            Button { model.toggleLaser() } label: { Image(systemName: "dot.radiowaves.left.and.right") }
                .foregroundStyle(model.laserActive ? .red : .primary)

            penMenu   // colours/weight collapsed into one control (portrait)

            Button {
                model.isBoardActive ? model.boardUndoInk() : model.undoInk()
            } label: { Image(systemName: "arrow.uturn.backward") }
                .disabled(model.isBoardActive ? !model.hasBoardInk : !model.hasInk)
            Button {
                model.isBoardActive ? model.boardClearInk() : model.clearInk()
            } label: { Image(systemName: "trash") }
                .disabled(model.isBoardActive ? !model.hasBoardInk : !model.hasInk)
        }
        .font(.title3)
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(.ultraThinMaterial)
    }

    // MARK: - Captioned control bar (macOS-style, landscape)

    /// A wide control bar matching the macOS app: every control is an icon with a
    /// small caption beneath it, grouped with spacers.
    private var controlBar: some View {
        HStack(alignment: .top, spacing: 0) {
            group {
                captionedButton("Exit", "rectangle.portrait.and.arrow.right") { model.close() }
                captioned("More") {
                    Menu { overflowMenuContent } label: { Image(systemName: "ellipsis.circle") }
                }
            }

            Spacer(minLength: 14)

            group {
                captionedButton("Prev", "chevron.left", disabled: model.index == 0) { model.previous() }
                captioned("Slide") {
                    Text("\(model.index + 1) / \(model.pageCount)")
                        .font(.callout.monospacedDigit().weight(.semibold))
                }
                captionedButton("Next", "chevron.right",
                                disabled: model.index + 1 >= model.pageCount) { model.next() }
            }

            Spacer(minLength: 14)

            group {
                captionedButton("Overview", "square.grid.2x2") { showOverview = true }
                captioned("Blackout") {
                    Menu { blackoutMenuContent } label: {
                        Image(systemName: model.blackout ? "eye.slash.fill" : "eye.slash")
                    }
                    .foregroundStyle(model.blackout ? Color.accentColor : .primary)
                }
                captioned("Board") {
                    Menu { boardMenuContent } label: {
                        Image(systemName: model.isBoardActive ? "square.and.pencil.circle.fill" : "square.and.pencil")
                    }
                    .foregroundStyle(model.isBoardActive ? Color.accentColor : .primary)
                }
                captionedButton("Awake", doNotDisturb ? "moon.fill" : "moon",
                                active: doNotDisturb) { doNotDisturb.toggle() }
                if external.isConnected {
                    captioned("Display") { Image(systemName: "tv.fill").foregroundStyle(.green) }
                }
            }

            Spacer(minLength: 14)

            group {
                captionedButton("Pen", "pencil.tip", active: model.penActive) { model.togglePen() }
                captionedButton("Laser", "dot.circle.and.cursorarrow", active: model.laserActive) { model.toggleLaser() }
                colourStrip
                captioned("Weight") {
                    Menu {
                        Section("Line weight") {
                            ForEach(widths, id: \.0) { name, w in
                                Button { model.penWidth = w; model.penActive = true } label: {
                                    Label(name, systemImage: model.penWidth == w ? "checkmark" : "scribble")
                                }
                            }
                        }
                        Toggle("Apple Pencil only", isOn: $pencilOnly)
                    } label: { Image(systemName: "lineweight") }
                }
                captionedButton("Undo", "arrow.uturn.backward",
                                disabled: model.isBoardActive ? !model.hasBoardInk : !model.hasInk) {
                    model.isBoardActive ? model.boardUndoInk() : model.undoInk()
                }
                captionedButton("Clear", "trash",
                                disabled: model.isBoardActive ? !model.hasBoardInk : !model.hasInk) {
                    model.isBoardActive ? model.boardClearInk() : model.clearInk()
                }
            }

            Spacer(minLength: 14)

            TimelineView(.periodic(from: .now, by: 1)) { _ in
                group {
                    captionedButton(model.timerRunning ? "Pause" : "Start",
                                    model.timerRunning ? "pause" : "play",
                                    active: !model.timerRunning) { model.toggleTimer() }
                    captionedButton("Reset", "arrow.counterclockwise") { model.resetTimer() }
                    captioned("Elapsed") {
                        Text(TimerControls.elapsedString(model.elapsed))
                            .font(.callout.monospacedDigit().weight(.semibold))
                    }
                    captioned("Time") {
                        Text(TimerControls.clockString())
                            .font(.callout.monospacedDigit()).foregroundStyle(.secondary)
                    }
                }
            }
        }
        .font(.system(size: 18, weight: .regular))
        .padding(.horizontal, 20)
        .padding(.vertical, 8)
        .background(.ultraThinMaterial)
    }

    /// A cluster of related controls, spaced for breathing room (Keynote-style).
    private func group<C: View>(@ViewBuilder _ content: () -> C) -> some View {
        HStack(alignment: .top, spacing: 20) { content() }
    }

    /// The pen colours as one tidy dot row under a single caption (no six labels).
    private var colourStrip: some View {
        captioned("Colour") {
            HStack(spacing: 8) {
                ForEach(colors, id: \.0) { _, color in
                    Button {
                        model.penColor = color; model.penActive = true; model.laserActive = false
                    } label: {
                        Circle().fill(color).frame(width: 17, height: 17)
                            .overlay(Circle().strokeBorder(
                                .white.opacity(model.penColor == color ? 0.95 : 0.25),
                                lineWidth: model.penColor == color ? 2 : 1))
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private func captioned<C: View>(_ caption: String, @ViewBuilder _ content: () -> C) -> some View {
        VStack(spacing: 4) {
            content().frame(height: 24)
            Text(caption).font(.system(size: 9)).foregroundStyle(.secondary)
        }
    }

    private func captionedButton(_ caption: String, _ icon: String,
                                 active: Bool = false, disabled: Bool = false,
                                 action: @escaping () -> Void) -> some View {
        captioned(caption) {
            Button(action: action) { Image(systemName: icon) }
                .foregroundStyle(active ? Color.accentColor : .primary)
                .disabled(disabled)
        }
    }

    /// Less-frequent actions, tucked away to keep the bar narrow.
    private var overflowMenu: some View {
        Menu { overflowMenuContent } label: { Image(systemName: "ellipsis.circle") }
    }

    @ViewBuilder private var overflowMenuContent: some View {
        Button { openPicker() } label: { Label("Open PDF…", systemImage: "folder") }
        Button { exportAndShare() } label: { Label("Export & Share…", systemImage: "square.and.arrow.up") }
        Button { showSettings = true } label: { Label("Settings…", systemImage: "gearshape") }
        Divider()
        Button { model.close() } label: { Label("Back to start", systemImage: "house") }
    }

    private var blackoutButton: some View {
        Menu {
            blackoutMenuContent
        } label: {
            Image(systemName: model.blackout ? "eye.slash.fill" : "eye.slash")
        }
        .foregroundStyle(model.blackout ? Color.accentColor : .primary)
    }

    /// The full macOS-style "Black Screen" menu: toggle, clock, preset / custom
    /// messages, and a background image.
    @ViewBuilder private var blackoutMenuContent: some View {
        Button(model.blackout ? "Show slide" : "Black out audience") { model.toggleBlackout() }
        Toggle("Show clock", isOn: $blackoutShowClock)
        Section("Message") {
            ForEach(BlackoutView.presets, id: \.self) { preset in
                Button {
                    blackoutMessage = preset
                    if !model.blackout { model.toggleBlackout() }
                } label: {
                    Label(preset, systemImage: blackoutMessage == preset ? "checkmark" : "text.bubble")
                }
            }
            Button { customMessage = blackoutMessage; showCustomMessage = true } label: {
                Label("Custom Message…", systemImage: "square.and.pencil")
            }
            Button(role: .destructive) { blackoutMessage = "" } label: {
                Label("Clear Message", systemImage: "xmark")
            }
        }
        Section("Background") {
            Button { importingBlackImage = true } label: {
                Label("Choose Background Image…", systemImage: "photo")
            }
            if !blackoutImagePath.isEmpty {
                Button(role: .destructive) { clearBlackImage() } label: {
                    Label("Clear Background Image", systemImage: "xmark")
                }
            }
        }
    }

    private func importBlackImage(_ url: URL) {
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }
        guard let data = try? Data(contentsOf: url) else { return }
        let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let dest = dir.appendingPathComponent("blackout-bg.img")
        if (try? data.write(to: dest)) != nil { blackoutImagePath = dest.path }
    }
    private func clearBlackImage() {
        if !blackoutImagePath.isEmpty { try? FileManager.default.removeItem(atPath: blackoutImagePath) }
        blackoutImagePath = ""
    }

    private var boardMenu: some View {
        Menu { boardMenuContent } label: {
            Image(systemName: model.isBoardActive ? "rectangle.fill.badge.plus" : "rectangle.badge.plus")
        }
        .foregroundStyle(model.isBoardActive ? Color.accentColor : .primary)
    }

    @ViewBuilder private var boardMenuContent: some View {
        Button { withAnimation { model.addBoard() } } label: {
            Label("New board", systemImage: "plus.rectangle")
        }
        if model.isBoardActive {
            Button { withAnimation { model.closeBoard() } } label: {
                Label("Back to slides", systemImage: "rectangle.on.rectangle")
            }
            Button(role: .destructive) { withAnimation { model.deleteActiveBoard() } } label: {
                Label("Delete this board", systemImage: "trash")
            }
        }
        if !model.boards.isEmpty {
            Divider()
            ForEach(Array(model.boards.enumerated()), id: \.element.id) { i, board in
                Button { withAnimation { model.showBoard(i) } } label: {
                    Label(board.name, systemImage: model.activeBoardIndex == i ? "checkmark" : "square")
                }
            }
        }
    }

    /// Pen toggle (tap) plus colour / weight / Pencil-only options (long-press),
    /// collapsing the old inline palette into one control.
    private var penMenu: some View {
        Menu {
            Section("Colour") {
                ForEach(colors, id: \.0) { name, color in
                    Button {
                        model.penColor = color; model.penActive = true; model.laserActive = false
                    } label: {
                        Label(name, systemImage: model.penColor == color ? "checkmark" : "circle.fill")
                    }
                }
            }
            Section("Line weight") {
                ForEach(widths, id: \.0) { name, w in
                    Button {
                        model.penWidth = w; model.penActive = true; model.laserActive = false
                    } label: {
                        Label(name, systemImage: model.penWidth == w ? "checkmark" : "scribble")
                    }
                }
            }
            Toggle("Apple Pencil only", isOn: $pencilOnly)
        } label: {
            Image(systemName: "pencil.tip")
                .foregroundStyle(model.penActive ? model.penColor : .primary)
        } primaryAction: {
            model.togglePen()
        }
    }

    /// Secondary row while a board is active: insert items and edit the selection.
    private var boardInsertBar: some View {
        HStack(spacing: 14) {
            Label(model.activeBoard?.name ?? "Board", systemImage: "rectangle")
                .font(.subheadline).foregroundStyle(.secondary)
            Divider().frame(height: 18)
            Button { model.addItem(.text) } label: { Label("Text", systemImage: "textformat") }
            Button { model.addItem(.table) } label: { Label("Table", systemImage: "tablecells") }
            Button { model.addItem(.qr) } label: { Label("QR", systemImage: "qrcode") }

            if let item = model.selectedItem() {
                Divider().frame(height: 18)
                TextField(item.kind == .qr ? "URL / text to encode"
                          : (item.kind == .table ? "Rows on lines, columns by |" : "Text"),
                          text: Binding(
                            get: { model.selectedItem()?.text ?? "" },
                            set: { model.updateItemText(item.id, $0) }))
                    .textFieldStyle(.roundedBorder)
                    .frame(maxWidth: 320)
                    .font(item.kind == .table ? .system(.footnote, design: .monospaced) : .body)
                Button { model.selectedItemID = nil } label: { Image(systemName: "checkmark") }
            }
            Spacer()
        }
        .font(.subheadline)
        .padding(.horizontal, 18)
        .padding(.vertical, 8)
        .background(Color(white: 0.12))
        .foregroundStyle(.white)
    }
}
