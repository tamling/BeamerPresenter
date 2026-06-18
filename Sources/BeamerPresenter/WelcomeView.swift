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
    @State private var hasLibreOffice = false
    @State private var checkedDeps = false

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 0) {
                sidebarBranding
                    .padding(30)
                    .frame(width: 404)
                Rectangle().fill(Theme.hairline).frame(width: 1)
                library
                    .frame(maxWidth: .infinity)
            }
            Rectangle().fill(Theme.hairline).frame(height: 1)
            dashboard
        }
        .frame(minWidth: 680, minHeight: 460)
        .background(Theme.base)
        .tint(Theme.accent)
        .onReceive(NotificationCenter.default.publisher(for: Favorites.didChange)) { _ in
            favorites = Favorites.load()
        }
        .onReceive(NotificationCenter.default.publisher(for: Stats.didChange)) { _ in
            statsTick += 1
        }
    }

    // MARK: - Left

    private var sidebarBranding: some View {
        VStack(alignment: .leading, spacing: 22) {
            VStack(alignment: .leading, spacing: 10) {
                Image(nsImage: NSApp.applicationIconImage)
                    .resizable()
                    .frame(width: 64, height: 64)
                    .clipShape(RoundedRectangle(cornerRadius: 15, style: .continuous))
                Text(AppInfo.name).font(.display(30)).tracking(-0.3)
                    .foregroundStyle(Theme.textPrimary)
                Text("Present LaTeX Beamer PDFs with speaker notes.")
                    .font(.ui(15)).foregroundStyle(Theme.textSecondary)
            }

            Button(action: onOpen) {
                Label("Open PDF, .tex or .pptx…", systemImage: "folder")
            }
            .buttonStyle(PrimaryButtonStyle())
            .keyboardShortcut("o", modifiers: .command)

            dropZone
                .frame(maxHeight: .infinity)

            systemStatus

            Text("Tip: keep the .tex with \\note{…} next to the PDF — or just open the .tex.")
                .font(.ui(13)).foregroundStyle(Theme.textFaint)
        }
        .onAppear {
            guard !checkedDeps else { return }
            checkedDeps = true
            latexEngine = Dependencies.latexEngine()?.name
            hasLibreOffice = Dependencies.soffice() != nil
        }
    }

    /// Green/yellow startup status of optional dependencies.
    private var systemStatus: some View {
        VStack(alignment: .leading, spacing: 4) {
            statusRow(ok: latexEngine != nil,
                      okText: "LaTeX ready — \(latexEngine ?? "")",
                      missingText: "LaTeX not found — install MacTeX to compile .tex")
            statusRow(ok: hasLibreOffice,
                      okText: "LibreOffice ready — .pptx supported",
                      missingText: "LibreOffice not found — needed to open .pptx")
        }
        .font(.caption)
        .foregroundStyle(.secondary)
    }

    private func statusRow(ok: Bool, okText: String, missingText: String) -> some View {
        HStack(spacing: 8) {
            Circle().fill(ok ? Theme.statusOk : Theme.statusWarn).frame(width: 9, height: 9)
                .shadow(color: (ok ? Theme.statusOk : Theme.statusWarn).opacity(0.6), radius: 4)
            Text(ok ? okText : missingText)
            Spacer()
        }
    }

    // MARK: - Right (sidebar list)

    private var library: some View {
        List {
            Section {
                if favorites.isEmpty {
                    Text("No favorite folders yet").font(.ui(13)).foregroundStyle(Theme.textFaint)
                } else {
                    ForEach(favorites, id: \.self) { favoriteRow($0) }
                }
            } header: {
                HStack {
                    Text("Favorite Folders").microLabel()
                    Spacer()
                    Button { addFavoriteFolder() } label: { Image(systemName: "plus") }
                        .buttonStyle(.borderless)
                        .help("Add a folder of presentations")
                }
                .padding(.trailing, 10)
            }

            Section {
                if recents.isEmpty {
                    Text("No recent presentations").font(.ui(13)).foregroundStyle(Theme.textFaint)
                } else {
                    ForEach(recents, id: \.self) { recentRow($0) }
                }
            } header: {
                HStack {
                    Text("Recent").microLabel()
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
        .scrollContentBackground(.hidden)
        .background(Theme.base)
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
        HStack(spacing: 26) {
            statTile("rectangle.on.rectangle", "\(Stats.count)", "Presentations")
            statTile("stopwatch", Stats.format(Stats.averageSeconds), "Avg. session")
            statTile("clock", Stats.format(Stats.totalSeconds), "Total time")

            Spacer()

            VStack(alignment: .trailing, spacing: 3) {
                Text("\(AppInfo.name) \(AppInfo.version)")
                    .font(.ui(13.5, "Medium")).foregroundStyle(Theme.textSecondary)
                Text("\(AppInfo.releaseDate)  ·  by \(AppInfo.author)").microLabel()
            }
        }
        .padding(.horizontal, 30)
        .frame(height: 66)
        .background(Theme.raised)
        .id(statsTick)   // refresh when stats change
    }

    private func statTile(_ icon: String, _ value: String, _ title: String) -> some View {
        HStack(spacing: 10) {
            Image(systemName: icon).font(.title3).foregroundStyle(Theme.accent)
            VStack(alignment: .leading, spacing: 1) {
                Text(value).font(.display(19)).foregroundStyle(Theme.textPrimary)
                Text(title).microLabel()
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
            .strokeBorder(dropTargeted ? Theme.accent : Theme.hairlineStrong,
                          style: StrokeStyle(lineWidth: 2, dash: [8]))
            .background(RoundedRectangle(cornerRadius: 12)
                .fill(dropTargeted ? Theme.accentDim : Color.clear))
            .overlay(
                VStack(spacing: 8) {
                    Image(systemName: "square.and.arrow.down").font(.title2)
                    Text("Drop a PDF, .tex or .pptx to open").font(.ui(13.5))
                    Text("…or drop a folder to add it to favorites").font(.ui(12))
                }
                .foregroundStyle(dropTargeted ? Theme.accent : Theme.textFaint)
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
                                if ["pdf", "tex", "pptx", "ppt", "odp"].contains(ext) { onOpenURL(url) }
                            }
                        }
                    }
                }
                return true
            }
    }
}
