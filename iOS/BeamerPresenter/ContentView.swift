import SwiftUI
import UniformTypeIdentifiers

struct ContentView: View {
    @EnvironmentObject var model: PresentationModel
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
    }
}

/// Start screen: branding, an open button, and recent files.
struct StartView: View {
    @EnvironmentObject var model: PresentationModel
    let open: () -> Void

    var body: some View {
        VStack(spacing: 22) {
            Image(systemName: "rectangle.on.rectangle.angled")
                .font(.system(size: 60)).foregroundStyle(.tint)
            Text("BeamerPresenter").font(.largeTitle.bold())
            Text("Present PDF slides on your iPad.").foregroundStyle(.secondary)

            Button(action: open) {
                Label("Open PDF…", systemImage: "folder").frame(maxWidth: 320)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)

            if let sample = Bundle.main.url(forResource: "sample", withExtension: "pdf") {
                Button { model.open(url: sample) } label: {
                    Label("Try a sample deck", systemImage: "sparkles").frame(maxWidth: 320)
                }
                .buttonStyle(.bordered)
                .controlSize(.large)
            }

            if !model.recents.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Recent").font(.headline)
                    ForEach(model.recents, id: \.self) { url in
                        Button { model.open(url: url) } label: {
                            Label(url.deletingPathExtension().lastPathComponent,
                                  systemImage: "doc.richtext")
                        }
                        .buttonStyle(.plain)
                    }
                }
                .frame(maxWidth: 320, alignment: .leading)
                .padding(.top, 8)
            }
            Spacer()
        }
        .padding(40)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
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
    let openPicker: () -> Void

    private var texTypes: [UTType] {
        [UTType(filenameExtension: "tex"), .plainText, .text].compactMap { $0 }
    }

    private let colors: [(String, Color)] = [("Red", .red), ("Orange", .orange),
                                             ("Yellow", .yellow), ("Green", .green),
                                             ("Blue", .blue), ("White", .white)]

    private let widths: [(String, CGFloat)] = [("Thin", 0.0025), ("Medium", 0.004),
                                              ("Thick", 0.007)]

    var body: some View {
        VStack(spacing: 0) {
            toolbar
            if model.isBoardActive { boardInsertBar }
            HStack(spacing: 0) {
                SlideView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                if showNotes {
                    NotesPanel(loadTex: { importingNotes = true })
                        .frame(width: 340)
                        .transition(.move(edge: .trailing))
                }
            }
            ThumbnailStrip()
                .frame(height: 96)
        }
        .background(Color.black.ignoresSafeArea())
        .sheet(isPresented: $showOverview) {
            OverviewGrid(isPresented: $showOverview)
        }
        .fileImporter(isPresented: $importingNotes, allowedContentTypes: texTypes) { result in
            if case .success(let url) = result { model.loadTexNotes(url: url) }
        }
        .sheet(isPresented: $showShare) {
            if let url = exportURL { ShareSheet(items: [url]) }
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
        HStack(spacing: 16) {
            Button { model.close() } label: { Image(systemName: "house") }
            Button(action: openPicker) { Image(systemName: "folder") }

            Divider().frame(height: 20)

            Button { model.previous() } label: { Image(systemName: "chevron.left") }
                .disabled(model.index == 0)
            Text("\(model.index + 1) / \(model.pageCount)")
                .font(.headline.monospacedDigit()).frame(minWidth: 90)
            Button { model.next() } label: { Image(systemName: "chevron.right") }
                .disabled(model.index + 1 >= model.pageCount)

            Button { showOverview = true } label: { Image(systemName: "square.grid.2x2") }

            Button { withAnimation(.easeInOut(duration: 0.2)) { showNotes.toggle() } } label: {
                Image(systemName: showNotes ? "note.text.badge.plus" : "note.text")
            }
            .foregroundStyle(showNotes ? Color.accentColor
                             : (model.hasNotes ? .primary : .secondary))

            Menu {
                Button(model.blackout ? "Show slide" : "Black out audience") {
                    model.toggleBlackout()
                }
                Toggle("Show clock", isOn: $model.blackoutShowClock)
                Picker("Message", selection: $model.blackoutMessage) {
                    Text("None").tag("")
                    ForEach(BlackoutView.presets, id: \.self) { Text($0).tag($0) }
                }
            } label: {
                Image(systemName: model.blackout ? "eye.slash.fill" : "eye.slash")
            } primaryAction: {
                model.toggleBlackout()
            }
            .foregroundStyle(model.blackout ? Color.accentColor : .primary)

            Menu {
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
            } label: {
                Image(systemName: model.isBoardActive ? "rectangle.fill.badge.plus" : "rectangle.badge.plus")
            }
            .foregroundStyle(model.isBoardActive ? Color.accentColor : .primary)

            Button { exportAndShare() } label: { Image(systemName: "square.and.arrow.up") }

            if external.isConnected {
                Image(systemName: "tv.fill")
                    .foregroundStyle(.green)
                    .help("Slide is showing on the external display")
            }

            Spacer()

            TimerControls()

            Spacer()

            Button { model.toggleLaser() } label: { Image(systemName: "dot.radiowaves.left.and.right") }
                .foregroundStyle(model.laserActive ? .red : .primary)

            Button { model.togglePen() } label: { Image(systemName: "pencil.tip") }
                .foregroundStyle(model.penActive ? Color.accentColor : .primary)
            ForEach(colors, id: \.0) { name, color in
                Button {
                    model.penColor = color
                    model.penActive = true
                    model.laserActive = false
                } label: {
                    Circle().fill(color).frame(width: 22, height: 22)
                        .overlay(Circle().strokeBorder(
                            .white.opacity(model.penColor == color ? 0.9 : 0.3),
                            lineWidth: model.penColor == color ? 2 : 1))
                }
            }
            Menu {
                ForEach(widths, id: \.0) { name, w in
                    Button {
                        model.penWidth = w
                        model.penActive = true
                        model.laserActive = false
                    } label: {
                        Label(name, systemImage: model.penWidth == w ? "checkmark" : "scribble")
                    }
                }
            } label: { Image(systemName: "lineweight") }

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
        .padding(.horizontal, 18)
        .padding(.vertical, 10)
        .background(.ultraThinMaterial)
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
