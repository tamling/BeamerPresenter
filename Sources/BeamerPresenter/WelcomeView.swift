import SwiftUI
import AppKit
import UniformTypeIdentifiers

/// Start screen ("home menu") shown before a presentation is loaded: branding and
/// actions on the left, favourites + recents on the right, and a small dashboard
/// (usage stats + version) across the bottom.
struct WelcomeView: View {
    let onOpen: () -> Void
    let onOpenURL: (URL) -> Void

    @State private var recents: [URL] = RecentFiles.load()
    @State private var favorites: [URL] = Favorites.load()
    @State private var dropTargeted = false
    @State private var statsTick = 0
    @State private var latexEngine: String?
    @State private var checkedDeps = false

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 0) {
                sidebarBranding
                    .padding(28)
                    .frame(width: 360)
                Divider()
                library
                    .frame(maxWidth: .infinity)
            }
            Divider()
            dashboard
        }
        .frame(minWidth: 640, minHeight: 440)
        .onReceive(NotificationCenter.default.publisher(for: Favorites.didChange)) { _ in
            favorites = Favorites.load()
        }
        .onReceive(NotificationCenter.default.publisher(for: Stats.didChange)) { _ in
            statsTick += 1
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
                Label("Open PDF or .tex…", systemImage: "folder")
                    .frame(maxWidth: .infinity)
            }
            .controlSize(.large)
            .keyboardShortcut("o", modifiers: .command)

            dropZone
                .frame(maxHeight: .infinity)

            systemStatus

            Text("Tip: keep the .tex with \\note{…} next to the PDF — or just open the .tex.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .onAppear {
            guard !checkedDeps else { return }
            checkedDeps = true
            latexEngine = Dependencies.latexEngine()?.name
        }
    }

    /// Green/yellow startup status of optional dependencies.
    private var systemStatus: some View {
        HStack(spacing: 8) {
            Circle()
                .fill(latexEngine != nil ? Color.green : Color.yellow)
                .frame(width: 9, height: 9)
            if let engine = latexEngine {
                Text("LaTeX ready — \(engine)")
            } else {
                Text("LaTeX not found — install MacTeX to compile .tex")
            }
            Spacer()
        }
        .font(.caption)
        .foregroundStyle(.secondary)
    }

    // MARK: - Right (sidebar list)

    private var library: some View {
        List {
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
                .padding(.trailing, 10)
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

    // MARK: - Bottom dashboard

    private var dashboard: some View {
        HStack(spacing: 22) {
            statTile("rectangle.on.rectangle", "\(Stats.count)", "Presentations")
            statTile("stopwatch", Stats.format(Stats.averageSeconds), "Avg. session")
            statTile("clock", Stats.format(Stats.totalSeconds), "Total time")

            Spacer()

            VStack(alignment: .trailing, spacing: 1) {
                Text("\(AppInfo.name) \(AppInfo.version)").font(.caption).bold()
                Text("\(AppInfo.releaseDate)  ·  by \(AppInfo.author)")
                    .font(.caption2).foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 12)
        .background(Color(nsColor: .underPageBackgroundColor))
        .id(statsTick)   // refresh when stats change
    }

    private func statTile(_ icon: String, _ value: String, _ title: String) -> some View {
        HStack(spacing: 9) {
            Image(systemName: icon).font(.title3).foregroundStyle(.tint)
            VStack(alignment: .leading, spacing: 0) {
                Text(value).font(.headline.monospacedDigit())
                Text(title).font(.caption2).foregroundStyle(.secondary)
            }
        }
    }

    // MARK: - Actions

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
                VStack(spacing: 8) {
                    Image(systemName: "square.and.arrow.down").font(.title2)
                    Text("Drop a PDF or .tex to open").font(.callout)
                    Text("…or drop a folder to add it to favorites")
                        .font(.caption)
                }
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(8)
            )
            .frame(minHeight: 140)
            .onDrop(of: [UTType.fileURL], isTargeted: $dropTargeted) { providers in
                for provider in providers {
                    _ = provider.loadDataRepresentation(forTypeIdentifier: UTType.fileURL.identifier) { data, _ in
                        guard let data, let url = URL(dataRepresentation: data, relativeTo: nil) else { return }
                        var isDir: ObjCBool = false
                        let exists = FileManager.default.fileExists(atPath: url.path, isDirectory: &isDir)
                        DispatchQueue.main.async {
                            if exists, isDir.boolValue {
                                Favorites.add(url)            // a folder → favorite
                            } else {
                                let ext = url.pathExtension.lowercased()
                                if ext == "pdf" || ext == "tex" { onOpenURL(url) }
                            }
                        }
                    }
                }
                return true
            }
    }
}
