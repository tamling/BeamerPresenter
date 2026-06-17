import SwiftUI
import UniformTypeIdentifiers

/// Start screen shown before a presentation is loaded: title, open button,
/// drag-and-drop target, and a list of recently opened files.
struct WelcomeView: View {
    let onOpen: () -> Void
    let onOpenURL: (URL) -> Void

    @State private var recents: [URL] = RecentFiles.load()
    @State private var dropTargeted = false

    var body: some View {
        HStack(spacing: 0) {
            // Left: branding + actions
            VStack(alignment: .leading, spacing: 20) {
                VStack(alignment: .leading, spacing: 6) {
                    Image(systemName: "rectangle.on.rectangle.angled")
                        .font(.system(size: 44))
                        .foregroundStyle(.tint)
                    Text("BeamerPresenter").font(.largeTitle.bold())
                    Text("Present LaTeX Beamer PDFs with speaker notes.")
                        .foregroundStyle(.secondary)
                }

                Button(action: onOpen) {
                    Label("Open Presentation…", systemImage: "folder")
                        .frame(maxWidth: .infinity)
                }
                .controlSize(.large)
                .keyboardShortcut("o", modifiers: .command)

                dropZone

                Spacer()
                Text("Tip: compile with \\setbeameroption{show notes on second screen=right}")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding(28)
            .frame(width: 360)

            Divider()

            // Right: recents
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("Recent").font(.headline)
                    Spacer()
                    if !recents.isEmpty {
                        Button("Clear") {
                            RecentFiles.clear()
                            recents = []
                        }
                        .buttonStyle(.link)
                    }
                }
                if recents.isEmpty {
                    Spacer()
                    Text("No recent presentations")
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity)
                    Spacer()
                } else {
                    List(recents, id: \.self) { url in
                        Button { onOpenURL(url) } label: {
                            HStack {
                                Image(systemName: "doc.richtext")
                                VStack(alignment: .leading) {
                                    Text(url.deletingPathExtension().lastPathComponent)
                                    Text(url.deletingLastPathComponent().path)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                        .lineLimit(1)
                                        .truncationMode(.middle)
                                }
                            }
                        }
                        .buttonStyle(.plain)
                    }
                    .listStyle(.inset)
                }
            }
            .padding(20)
            .frame(maxWidth: .infinity)
        }
        .frame(minWidth: 760, minHeight: 460)
    }

    private var dropZone: some View {
        RoundedRectangle(cornerRadius: 12)
            .strokeBorder(style: StrokeStyle(lineWidth: 2, dash: [8]))
            .foregroundStyle(dropTargeted ? Color.accentColor : Color.secondary.opacity(0.5))
            .overlay(
                VStack(spacing: 6) {
                    Image(systemName: "square.and.arrow.down")
                    Text("Drop a PDF here")
                }
                .foregroundStyle(.secondary)
            )
            .frame(height: 110)
            .onDrop(of: [UTType.fileURL], isTargeted: $dropTargeted) { providers in
                guard let provider = providers.first else { return false }
                _ = provider.loadDataRepresentation(forTypeIdentifier: UTType.fileURL.identifier) { data, _ in
                    guard let data,
                          let url = URL(dataRepresentation: data, relativeTo: nil),
                          url.pathExtension.lowercased() == "pdf" else { return }
                    DispatchQueue.main.async { onOpenURL(url) }
                }
                return true
            }
    }
}
