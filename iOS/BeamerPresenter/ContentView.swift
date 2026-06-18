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

/// Launcher — Night Console (spec §05): dark identity column with the wordmark,
/// a single solid-lime primary action, ghost secondaries, a recent card, and a
/// quiet version footer.
struct StartView: View {
    @EnvironmentObject var model: PresentationModel
    @State private var showSettings = false
    @State private var showRemote = false
    let open: () -> Void

    var body: some View {
        ZStack {
            Theme.base.ignoresSafeArea()

            VStack(spacing: 26) {
                HStack {
                    Spacer()
                    KeyButton("Settings", systemImage: "gearshape") { showSettings = true }
                }

                Spacer(minLength: 0)

                // Identity
                VStack(spacing: 10) {
                    BrandMark()
                        .padding(22)
                        .frame(width: 92, height: 92)
                        .background(Theme.key, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
                        .overlay(RoundedRectangle(cornerRadius: 22).stroke(Theme.hairline, lineWidth: 1))
                    Text("BeamerPresenter")
                        .font(.display(30)).tracking(-0.3)
                        .foregroundStyle(Theme.textPrimary)
                    Text("Present · Annotate · Two screens")
                        .font(.mono(10)).textCase(.uppercase).tracking(1.6)
                        .foregroundStyle(Theme.accent)
                    Text("Your console on the iPad, clean slides on the projector.")
                        .font(.ui(15)).foregroundStyle(Theme.textSecondary)
                        .multilineTextAlignment(.center)
                }

                // Actions
                VStack(spacing: 12) {
                    Button(action: open) {
                        Label("Open PDF…", systemImage: "folder")
                    }
                    .buttonStyle(PrimaryButtonStyle())

                    if let sample = Bundle.main.url(forResource: "sample", withExtension: "pdf") {
                        Button { model.open(url: sample) } label: {
                            Label("Try a sample deck", systemImage: "sparkles")
                        }
                        .buttonStyle(GhostButtonStyle())
                    }
                    Button { showRemote = true } label: {
                        Label("Use as remote", systemImage: "dot.radiowaves.left.and.right")
                    }
                    .buttonStyle(GhostButtonStyle())
                }
                .frame(maxWidth: 380)

                if !model.recents.isEmpty {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Recent").microLabel()
                        VStack(spacing: 0) {
                            ForEach(Array(model.recents.prefix(5).enumerated()), id: \.element) { i, url in
                                if i > 0 { Divider().overlay(Theme.hairline) }
                                Button { model.open(url: url) } label: {
                                    HStack(spacing: 11) {
                                        Text("PDF").font(.mono(9, bold: true)).foregroundStyle(Theme.accent)
                                            .padding(.horizontal, 7).padding(.vertical, 5)
                                            .background(Theme.accentDim, in: RoundedRectangle(cornerRadius: 6))
                                        Text(url.deletingPathExtension().lastPathComponent)
                                            .font(.ui(15, "Medium")).foregroundStyle(Theme.textPrimary)
                                        Spacer()
                                        Image(systemName: "chevron.right")
                                            .font(.caption).foregroundStyle(Theme.textFaint)
                                    }
                                    .padding(.vertical, 11).padding(.horizontal, 14)
                                    .contentShape(Rectangle())
                                }
                                .buttonStyle(.plain)
                            }
                        }
                        .nightCard()
                    }
                    .frame(maxWidth: 380)
                }

                Spacer(minLength: 0)

                VStack(spacing: 4) {
                    Text("BeamerPresenter \(Self.version)")
                        .font(.ui(13.5, "Medium")).foregroundStyle(Theme.textSecondary)
                    Text("\(Self.releaseDate) · by \(Self.author)").microLabel()
                }
            }
            .padding(34)
        }
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
    @AppStorage("showThumbnails") private var showThumbnails = true
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
    @State private var showTablePicker = false
    @AppStorage("doNotDisturb") private var doNotDisturb = false
    @Environment(\.horizontalSizeClass) private var sizeClass
    @State private var landscape = false
    let openPicker: () -> Void

    /// The full console (current slide + next + notes + own notes) is used on a
    /// wide landscape iPad; portrait keeps the big single-slide layout.
    private var useConsole: Bool { landscape && sizeClass == .regular }

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
                        PresenterConsole()
                    } else {
                        // Portrait / narrow: the big single slide, notes on demand.
                        HStack(spacing: 0) {
                            SlideView()
                                .frame(maxWidth: .infinity, maxHeight: .infinity)
                            if showNotes {
                                NotesPanel()
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
            if showThumbnails {
                ThumbnailStrip()
                    .frame(height: 96)
                    .transition(.move(edge: .bottom))
            }
        }
        .background(Theme.base.ignoresSafeArea())
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

            Button { model.penActive = false; model.laserActive = false } label: { Image(systemName: "cursorarrow") }
                .foregroundStyle(!model.penActive && !model.laserActive ? Color.accentColor : .primary)
            Button { model.toggleLaser() } label: { Image(systemName: "dot.radiowaves.left.and.right") }
                .foregroundStyle(model.laserActive ? .red : .primary)

            penMenu   // pen toggle + weight (portrait)
            ColorPicker("", selection: penColorBinding, supportsOpacity: false)
                .labelsHidden()

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
        .background(Theme.raised)
        .overlay(alignment: .bottom) { Rectangle().fill(Theme.hairline).frame(height: 1) }
    }

    // MARK: - Captioned control bar (macOS-style, landscape)

    /// A wide control bar matching the macOS app: every control is an icon with a
    /// small caption beneath it, grouped with whitespace. Horizontally scrollable
    /// so nothing is ever clipped on narrower iPads.
    private var controlBar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(alignment: .top, spacing: 30) {
                group {
                    captionedButton("Exit", "rectangle.portrait.and.arrow.right") { model.close() }
                    captioned("More") {
                        Menu { overflowMenuContent } label: { keyGlyph("ellipsis.circle") }
                    }
                }

                group {
                    captionedButton("Prev", "chevron.left", disabled: model.index == 0) { model.previous() }
                    captioned("Slide") {
                        Text(String(format: "%02d / %02d", model.index + 1, model.pageCount))
                            .font(.mono(14, bold: true)).foregroundStyle(Theme.textPrimary)
                            .lineLimit(1).fixedSize()
                            .padding(.horizontal, 11).frame(height: 36)
                            .background(Theme.inset, in: RoundedRectangle(cornerRadius: 9))
                            .overlay(RoundedRectangle(cornerRadius: 9).stroke(Theme.hairline, lineWidth: 1))
                    }
                    captionedButton("Next", "chevron.right",
                                    disabled: model.index + 1 >= model.pageCount) { model.next() }
                }

                group {
                    captionedButton("Grid", "square.grid.2x2") { showOverview = true }
                    captioned("Black") {
                        Menu { blackoutMenuContent } label: {
                            keyGlyph(model.blackout ? "eye.slash.fill" : "eye.slash", active: model.blackout)
                        }
                    }
                    captioned("Board") {
                        Menu { boardMenuContent } label: {
                            keyGlyph(model.isBoardActive ? "square.and.pencil.circle.fill" : "square.and.pencil",
                                     active: model.isBoardActive)
                        }
                    }
                    if external.isConnected {
                        captioned("Display") { keyGlyph("tv.fill", active: true) }
                    }
                }

                group {
                    captionedButton("Cursor", "cursorarrow",
                                    active: !model.penActive && !model.laserActive) {
                        model.penActive = false; model.laserActive = false
                    }
                    captioned("Pen") {
                        Menu {
                            Section("Line weight") {
                                ForEach(widths, id: \.0) { name, w in
                                    Button { model.penWidth = w; model.penActive = true } label: {
                                        Label(name, systemImage: model.penWidth == w ? "checkmark" : "scribble")
                                    }
                                }
                            }
                            Toggle("Apple Pencil only", isOn: $pencilOnly)
                        } label: {
                            keyGlyph("pencil.tip", active: model.penActive)
                        } primaryAction: { model.togglePen() }
                    }
                    captionedButton("Laser", "dot.circle.and.cursorarrow", active: model.laserActive) { model.toggleLaser() }
                    colourStrip
                    captionedButton("Undo", "arrow.uturn.backward",
                                    disabled: model.isBoardActive ? !model.hasBoardInk : !model.hasInk) {
                        model.isBoardActive ? model.boardUndoInk() : model.undoInk()
                    }
                    captionedButton("Clear", "trash",
                                    disabled: model.isBoardActive ? !model.hasBoardInk : !model.hasInk) {
                        model.isBoardActive ? model.boardClearInk() : model.clearInk()
                    }
                }

                TimelineView(.periodic(from: .now, by: 1)) { _ in
                    group {
                        captionedButton(model.timerRunning ? "Pause" : "Start",
                                        model.timerRunning ? "pause" : "play",
                                        active: !model.timerRunning) { model.toggleTimer() }
                        captionedButton("Reset", "arrow.counterclockwise") { model.resetTimer() }
                        captioned("Elapsed") { elapsedChip }
                        captioned("Time") {
                            Text(TimerControls.clockString())
                                .font(.mono(15, bold: true)).foregroundStyle(Theme.textSecondary)
                                .lineLimit(1).fixedSize().frame(height: 36)
                        }
                    }
                }
            }
            .padding(.horizontal, 22)
        }
        .padding(.vertical, 9)
        .background(Theme.raised)
        .overlay(alignment: .bottom) { Rectangle().fill(Theme.hairline).frame(height: 1) }
    }

    /// A tactile key glyph (the Night Console toolbar button surface).
    private func keyGlyph(_ icon: String, active: Bool = false) -> some View {
        Image(systemName: icon)
            .font(.system(size: 16, weight: .medium))
            .foregroundStyle(active ? Theme.accent : Theme.textPrimary)
            .frame(width: 46, height: 36)
            .background(Theme.key, in: RoundedRectangle(cornerRadius: 9))
            .overlay(RoundedRectangle(cornerRadius: 9)
                .stroke(active ? Theme.accent : Theme.hairline, lineWidth: 1))
            .shadow(color: active ? Theme.accent.opacity(0.5) : .clear, radius: 6)
    }

    /// The running timer — the only solid-lime fill in the chrome.
    @ViewBuilder private var elapsedChip: some View {
        if model.timerRunning {
            Text(TimerControls.elapsedString(model.elapsed))
                .font(.mono(15, bold: true)).foregroundStyle(Theme.onAccent)
                .lineLimit(1).fixedSize()
                .padding(.horizontal, 11).frame(height: 36)
                .background(Theme.accent, in: RoundedRectangle(cornerRadius: 9))
                .shadow(color: Theme.accent.opacity(0.5), radius: 8)
        } else {
            Text(TimerControls.elapsedString(model.elapsed))
                .font(.mono(15, bold: true)).foregroundStyle(Theme.textPrimary)
                .lineLimit(1).fixedSize()
                .padding(.horizontal, 11).frame(height: 36)
                .background(Theme.inset, in: RoundedRectangle(cornerRadius: 9))
                .overlay(RoundedRectangle(cornerRadius: 9).stroke(Theme.hairline, lineWidth: 1))
        }
    }

    /// A cluster of related controls, spaced for breathing room (Keynote-style).
    private func group<C: View>(@ViewBuilder _ content: () -> C) -> some View {
        HStack(alignment: .top, spacing: 18) { content() }
    }

    /// The pen colours as a tidy dot row under a single caption, plus the system
    /// colour picker (the native iPad overlay) for any custom colour.
    private var colourStrip: some View {
        captioned("Colour") {
            HStack(spacing: 11) {
                ForEach(colors, id: \.0) { _, color in
                    Button {
                        model.penColor = color; model.penActive = true; model.laserActive = false
                    } label: {
                        Circle().fill(color).frame(width: 26, height: 26)
                            .overlay(Circle().strokeBorder(
                                model.penColor == color ? Theme.accent : Theme.hairlineStrong,
                                lineWidth: model.penColor == color ? 3 : 1))
                            .shadow(color: model.penColor == color ? Theme.accent.opacity(0.4) : .clear, radius: 4)
                    }
                    .buttonStyle(.plain)
                }
                ColorPicker("", selection: penColorBinding, supportsOpacity: false)
                    .labelsHidden().frame(width: 30)
            }
            .frame(height: 36)
        }
    }

    /// Binding that also activates the pen when a colour is picked.
    private var penColorBinding: Binding<Color> {
        Binding(get: { model.penColor },
                set: { model.penColor = $0; model.penActive = true; model.laserActive = false })
    }

    /// A control stacked above a mono uppercase caption (Night Console).
    private func captioned<C: View>(_ caption: String, @ViewBuilder _ content: () -> C) -> some View {
        VStack(spacing: 6) {
            content().frame(height: 36)
            Text(caption).font(.mono(9)).textCase(.uppercase).tracking(0.6)
                .foregroundStyle(Theme.textMuted)
        }
    }

    private func captionedButton(_ caption: String, _ icon: String,
                                 active: Bool = false, disabled: Bool = false,
                                 action: @escaping () -> Void) -> some View {
        captioned(caption) {
            Button(action: action) { keyGlyph(icon, active: active) }
                .buttonStyle(.plain)
                .disabled(disabled)
                .opacity(disabled ? 0.4 : 1)
        }
    }

    /// Less-frequent actions, tucked away to keep the bar narrow.
    private var overflowMenu: some View {
        Menu { overflowMenuContent } label: { Image(systemName: "ellipsis.circle") }
    }

    @ViewBuilder private var overflowMenuContent: some View {
        Button { openPicker() } label: { Label("Open PDF…", systemImage: "folder") }
        Button { exportAndShare() } label: { Label("Export & Share…", systemImage: "square.and.arrow.up") }
        Toggle(isOn: $showThumbnails.animation()) { Label("Slide strip", systemImage: "rectangle.grid.1x2") }
        Toggle(isOn: $doNotDisturb) { Label("Keep screen awake", systemImage: "moon") }
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
        HStack(spacing: 12) {
            Label(model.activeBoard?.name ?? "Board", systemImage: "rectangle")
                .font(.subheadline).foregroundStyle(.secondary)
            Divider().frame(height: 22)

            insertButton("Text", "textformat") { model.addItem(.text) }
            insertButton("Table", "tablecells") { showTablePicker = true }
                .popover(isPresented: $showTablePicker) {
                    TableSizePicker { rows, cols in
                        model.addTable(rows: rows, columns: cols)
                        showTablePicker = false
                    }
                }
            insertButton("QR", "qrcode") { model.addItem(.qr) }

            if let item = model.selectedItem(), item.kind != .table {
                Divider().frame(height: 22)
                TextField(item.kind == .qr ? "URL / text to encode" : "Text",
                          text: Binding(
                            get: { model.selectedItem()?.text ?? "" },
                            set: { model.updateItemText(item.id, $0) }))
                    .textFieldStyle(.roundedBorder)
                    .frame(maxWidth: 340)
                Button { model.selectedItemID = nil } label: { Image(systemName: "checkmark") }
            }
            Spacer()
            Text(model.selectedItem()?.kind == .table
                 ? "Tap a cell to type · drag the grip to move · pinch to resize"
                 : "Drag to move · pinch to resize")
                .font(.caption).foregroundStyle(.secondary)
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 8)
        .background(Theme.raised)
        .overlay(alignment: .bottom) { Rectangle().fill(Theme.hairline).frame(height: 1) }
        .foregroundStyle(Theme.textPrimary)
    }

    /// A larger, thumb-friendly insert button for the board bar.
    private func insertButton(_ title: String, _ icon: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Label(title, systemImage: icon)
                .font(.body.weight(.medium))
                .padding(.horizontal, 14).padding(.vertical, 8)
                .background(Color.white.opacity(0.12), in: RoundedRectangle(cornerRadius: 10))
        }
        .buttonStyle(.plain)
    }
}

/// Apple Notes-style table size grid: drag across the cells to size, release (or
/// tap) to insert a table of that size.
struct TableSizePicker: View {
    let onPick: (_ rows: Int, _ columns: Int) -> Void
    private let maxRows = 8, maxCols = 8
    private let cell: CGFloat = 30
    private let gap: CGFloat = 4
    @State private var rows = 1
    @State private var cols = 1

    var body: some View {
        VStack(spacing: 10) {
            Text("\(rows) × \(cols)").font(.headline.monospacedDigit())
            grid
                .contentShape(Rectangle())
                .gesture(
                    DragGesture(minimumDistance: 0, coordinateSpace: .local)
                        .onChanged { v in
                            cols = min(max(Int(v.location.x / (cell + gap)) + 1, 1), maxCols)
                            rows = min(max(Int(v.location.y / (cell + gap)) + 1, 1), maxRows)
                        }
                        .onEnded { _ in onPick(rows, cols) }
                )
        }
        .padding(18)
    }

    private var grid: some View {
        VStack(spacing: gap) {
            ForEach(1...maxRows, id: \.self) { r in
                HStack(spacing: gap) {
                    ForEach(1...maxCols, id: \.self) { c in
                        RoundedRectangle(cornerRadius: 4)
                            .fill((r <= rows && c <= cols) ? Color.accentColor
                                                           : Color.secondary.opacity(0.25))
                            .frame(width: cell, height: cell)
                    }
                }
            }
        }
    }
}
