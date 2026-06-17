import SwiftUI
import AppKit
import UniformTypeIdentifiers

/// Start screen shown before a presentation is loaded: title, open button,
/// drag-and-drop target, and a list of recently opened files.
struct WelcomeView: View {
    let onOpen: () -> Void
    let onOpenURL: (URL) -> Void

    @State private var recents: [URL] = RecentFiles.load()
    @State private var favorites: [URL] = Favorites.load()
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
                Text("Tip: compile with \\setbeameroption{show notes on second screen=right}, or keep the .tex with \\note{…} next to the PDF.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding(28)
            .frame(width: 360)

            Divider()

            // Right: favourite folders + recent files
            List {
                Section {
                    if favorites.isEmpty {
                        Text("No favorite folders yet")
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(favorites, id: \.self) { folder in
                            favoriteRow(folder)
                        }
                    }
                } header: {
                    HStack {
                        Text("Favorite Folders")
                        Spacer()
                        Button { addFavoriteFolder() } label: {
                            Image(systemName: "plus")
                        }
                        .buttonStyle(.borderless)
                        .help("Add a folder of presentations")
                    }
                }

                Section {
                    if recents.isEmpty {
                        Text("No recent presentations")
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(recents, id: \.self) { url in
                            recentRow(url)
                        }
                    }
                } header: {
                    HStack {
                        Text("Recent")
                        Spacer()
                        if !recents.isEmpty {
                            Button("Clear") {
                                RecentFiles.clear()
                                recents = []
                            }
                            .buttonStyle(.borderless)
                        }
                    }
                }
            }
            .listStyle(.sidebar)
            .frame(maxWidth: .infinity)
        }
        .frame(minWidth: 760, minHeight: 460)
        .onReceive(NotificationCenter.default.publisher(for: Favorites.didChange)) { _ in
            favorites = Favorites.load()
        }
    }

    /// A favourite folder that expands to the PDFs inside it.
    private func favoriteRow(_ folder: URL) -> some View {
        DisclosureGroup {
            let pdfs = Favorites.pdfs(in: folder)
            if pdfs.isEmpty {
                Text("No PDFs in this folder")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                ForEach(pdfs, id: \.self) { pdf in
                    Button { onOpenURL(pdf) } label: {
                        Label(pdf.deletingPathExtension().lastPathComponent,
                              systemImage: "doc.richtext")
                    }
                    .buttonStyle(.plain)
                }
            }
        } label: {
            HStack {
                Image(systemName: "folder.fill").foregroundStyle(.tint)
                Text(folder.lastPathComponent).lineLimit(1)
                Spacer()
                Button { Favorites.remove(folder) } label: {
                    Image(systemName: "minus.circle")
                }
                .buttonStyle(.borderless)
                .foregroundStyle(.secondary)
                .help("Remove from favorites")
            }
        }
    }

    private func recentRow(_ url: URL) -> some View {
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

    private func addFavoriteFolder() {
        let panel = NSOpenPanel()
        panel.title = "Add Folder to Favorites"
        panel.prompt = "Add"
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        if panel.runModal() == .OK, let url = panel.url {
            Favorites.add(url)   // posts didChange → refreshes the list
        }
    }

    private var dropZone: some View {
        RoundedRectangle(cornerRadius: 12)
            .strokeBorder(style: StrokeStyle(lineWidth: 2, dash: [8]))
            .foregroundStyle(dropTargeted ? Color.accentColor : Color.secondary.opacity(0.5))
            .overlay(
                VStack(spacing: 6) {
                    Image(systemName: "square.and.arrow.down")
                    Text("Drop a PDF or .tex here")
                }
                .foregroundStyle(.secondary)
            )
            .frame(height: 110)
            .onDrop(of: [UTType.fileURL], isTargeted: $dropTargeted) { providers in
                guard let provider = providers.first else { return false }
                _ = provider.loadDataRepresentation(forTypeIdentifier: UTType.fileURL.identifier) { data, _ in
                    guard let data,
                          let url = URL(dataRepresentation: data, relativeTo: nil) else { return }
                    let ext = url.pathExtension.lowercased()
                    guard ext == "pdf" || ext == "tex" else { return }
                    DispatchQueue.main.async { onOpenURL(url) }
                }
                return true
            }
    }
}
