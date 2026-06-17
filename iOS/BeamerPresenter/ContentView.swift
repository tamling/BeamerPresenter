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
    let openPicker: () -> Void

    private let colors: [(String, Color)] = [("Red", .red), ("Orange", .orange),
                                             ("Yellow", .yellow), ("Green", .green),
                                             ("Blue", .blue), ("White", .white)]

    private let widths: [(String, CGFloat)] = [("Thin", 0.0025), ("Medium", 0.004),
                                              ("Thick", 0.007)]

    var body: some View {
        VStack(spacing: 0) {
            toolbar
            SlideView()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            ThumbnailStrip()
                .frame(height: 96)
        }
        .background(Color.black.ignoresSafeArea())
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

            if external.isConnected {
                Image(systemName: "tv.fill")
                    .foregroundStyle(.green)
                    .help("Slide is showing on the external display")
            }

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

            Button { model.undoInk() } label: { Image(systemName: "arrow.uturn.backward") }
                .disabled(!model.hasInk)
            Button { model.clearInk() } label: { Image(systemName: "trash") }
                .disabled(!model.hasInk)
        }
        .font(.title3)
        .padding(.horizontal, 18)
        .padding(.vertical, 10)
        .background(.ultraThinMaterial)
    }
}
