import SwiftUI
import AppKit
import UniformTypeIdentifiers

/// Start screen ("home menu") shown before a presentation is loaded: branding and
/// actions on the left; a sidebar listing a browsable folder, favourite folders,
/// and recent files on the right.
struct WelcomeView: View {
    let onOpen: () -> Void
    let onOpenURL: (URL) -> Void

    @AppStorage(Prefs.browseFolder) private var browseFolderPath = ""
    @State private var recents: [URL] = RecentFiles.load()
    @State private var favorites: [URL] = Favorites.load()
    @State private var dropTargeted = false

    private var browseFolder: URL { Prefs.browseFolderURL }

    var body: some View {
        HStack(spacing: 0) {
            sidebarBranding
                .padding(28)
                .frame(width: 360)

            Divider()

            library
                .frame(maxWidth: .infinity)
        }
        .frame(minWidth: 820, minHeight: 480)
        .onReceive(NotificationCenter.default.publisher(for: Favorites.didChange)) { _ in
            favorites = Favorites.load()
        }
    }

    // MARK: - Left

    private var sidebarBranding: some View {
        VStack(alignment: .leading, spacing: 20) {
            VStack(alignment: .leading, spacing: 8) {
                Image(nsImage: NSApp.applicationIconImage)
                    .resizable()
                    .frame(width: 60, height: 60)
                Text(AppInfo.name).font(.largeTitle.bold())
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

            VStack(alignment: .leading, spacing: 6) {
                Text("Tip: keep the .tex with \\note{…} next to the PDF — or just open the .tex.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text("\(AppInfo.versionLine)  ·  by \(AppInfo.author)")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
        }
    }

    // MARK: - Right (sidebar list)

    private var library: some View {
        List {
            Section {
                let pdfs = Favorites.pdfs(in: browseFolder)
                if pdfs.isEmpty {
                    Text("No PDFs in this folder").foregroundStyle(.secondary)
                } else {
                    ForEach(pdfs, id: \.self) { pdfRow($0) }
                }
            } header: {
                HStack {
                    Label(browseFolder.lastPathComponent, systemImage: "folder")
                    Spacer()
                    Button { chooseBrowseFolder() } label: { Image(systemName: "folder.badge.gearshape") }
                        .buttonStyle(.borderless)
                        .help("Choose the folder shown here (also in Settings)")
                }
            }

            Section {
                if favorites.isEmpty {
                    Text("No favorite folders yet").foregroundStyle(.secondary)
                } else {
                    ForEach(favorites, id: \.self) { favoriteRow($0) }
                }
            } header: {
                HStack {
                    Text("Favorite Folders")
                    Spacer()
                    Button { addFavoriteFolder() } label: { Image(systemName: "plus") }
                        .buttonStyle(.borderless)
                        .help("Add a folder of presentations")
                }
            }

            Section {
                if recents.isEmpty {
                    Text("No recent presentations").foregroundStyle(.secondary)
                } else {
                    ForEach(recents, id: \.self) { recentRow($0) }
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
    }

    private func pdfRow(_ url: URL) -> some View {
        Button { onOpenURL(url) } label: {
            Label(url.deletingPathExtension().lastPathComponent, systemImage: "doc.richtext")
        }
        .buttonStyle(.plain)
    }

    private func favoriteRow(_ folder: URL) -> some View {
        DisclosureGroup {
            let pdfs = Favorites.pdfs(in: folder)
            if pdfs.isEmpty {
                Text("No PDFs in this folder").font(.caption).foregroundStyle(.secondary)
            } else {
                ForEach(pdfs, id: \.self) { pdfRow($0) }
            }
        } label: {
            HStack {
                Image(systemName: "folder.fill").foregroundStyle(.tint)
                Text(folder.lastPathComponent).lineLimit(1)
                Spacer()
                Button { Favorites.remove(folder) } label: { Image(systemName: "minus.circle") }
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

    // MARK: - Actions

    private func chooseBrowseFolder() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.prompt = "Choose"
        if panel.runModal() == .OK, let url = panel.url {
            browseFolderPath = url.path
        }
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
