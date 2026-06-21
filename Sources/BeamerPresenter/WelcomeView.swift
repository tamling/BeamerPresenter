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
    @State private var browseTarget: BrowseTarget?
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
        .sheet(item: $browseTarget) { target in
            FolderBrowser(root: target.url) { url in
                browseTarget = nil
                onOpenURL(url)
            }
        }
    }

    // MARK: - Left

    private var sidebarBranding: some View {
        VStack(alignment: .leading, spacing: 22) {
            VStack(alignment: .leading, spacing: 10) {
                BrandMark()
                    .padding(15)
                    .frame(width: 64, height: 64)
                    .background(Theme.key, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: 16).stroke(Theme.hairline, lineWidth: 1))
                Text(AppInfo.name).font(.display(30)).tracking(-0.3)
                    .foregroundStyle(Theme.textPrimary)
                Text("Present · Annotate · Two screens")
                    .font(.mono(10)).textCase(.uppercase).tracking(1.6)
                    .foregroundStyle(Theme.accent)
                Text("Present LaTeX Beamer PDFs with speaker notes — your console on one screen, clean slides on the other.")
                    .font(.ui(15)).foregroundStyle(Theme.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Button(action: onOpen) {
                Label("Open PDF · .tex · .pptx", systemImage: "rectangle.on.rectangle")
            }
            .buttonStyle(PrimaryButtonStyle())
            .keyboardShortcut("o", modifiers: .command)

            systemStatus

            Spacer(minLength: 0)

            VStack(alignment: .leading, spacing: 8) {
                Rectangle().fill(Theme.hairline).frame(height: 1)
                Text("Tip").microLabel()
                Text("Keep the .tex with \\note{…} next to the PDF — or just open the .tex.")
                    .font(.ui(13)).foregroundStyle(Theme.textFaint)
                    .fixedSize(horizontal: false, vertical: true)
            }
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

    // MARK: - Right (library: favourites, recents, drop zone)

    private var library: some View {
        VStack(alignment: .leading, spacing: 26) {
            VStack(alignment: .leading, spacing: 12) {
                sectionHeader("Favorite Folders") {
                    smallKeyButton("plus") { addFavoriteFolder() }
                        .help("Add a folder of presentations")
                }
                if favorites.isEmpty {
                    dashedBox("No favourite folders yet — drop a folder here to pin it.")
                } else {
                    VStack(spacing: 8) { ForEach(favorites, id: \.self) { favoriteCard($0) } }
                }
            }

            VStack(alignment: .leading, spacing: 12) {
                sectionHeader("Recent") {
                    if !recents.isEmpty {
                        Button("Clear") { RecentFiles.clear(); recents = [] }
                            .buttonStyle(.plain)
                            .font(.ui(13, "Medium")).foregroundStyle(Theme.accent)
                    }
                }
                if recents.isEmpty {
                    dashedBox("No recent presentations yet.")
                } else {
                    VStack(spacing: 8) {
                        ForEach(Array(recents.prefix(5)), id: \.self) { recentCard($0) }
                    }
                }
            }

            dropZone.frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .padding(28)
        .background(Theme.base)
    }

    private func sectionHeader<T: View>(_ title: String, @ViewBuilder trailing: () -> T) -> some View {
        HStack {
            Text(title).microLabel()
            Spacer()
            trailing()
        }
    }

    private func smallKeyButton(_ icon: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: icon).font(.system(size: 12, weight: .semibold))
                .foregroundStyle(Theme.textSecondary)
                .frame(width: 30, height: 26)
                .background(Theme.key, in: RoundedRectangle(cornerRadius: 7))
                .overlay(RoundedRectangle(cornerRadius: 7).stroke(Theme.hairline, lineWidth: 1))
        }
        .buttonStyle(.plain)
    }

    private func dashedBox(_ text: String) -> some View {
        Text(text).font(.ui(15)).foregroundStyle(Theme.textMuted)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 18).padding(.vertical, 22)
            .background(RoundedRectangle(cornerRadius: 12)
                .strokeBorder(Theme.hairlineStrong, style: StrokeStyle(lineWidth: 1, dash: [5])))
    }

    private func tile<G: View>(@ViewBuilder _ glyph: () -> G) -> some View {
        glyph()
            .frame(width: 48, height: 44)
            .background(Theme.key, in: RoundedRectangle(cornerRadius: 9))
            .overlay(RoundedRectangle(cornerRadius: 9).stroke(Theme.hairline, lineWidth: 1))
    }

    private func recentCard(_ url: URL) -> some View {
        Button { onOpenURL(url) } label: {
            HStack(spacing: 13) {
                tile { Text(url.pathExtension.uppercased().isEmpty ? "PDF" : url.pathExtension.uppercased())
                        .font(.mono(10, bold: true)).foregroundStyle(Theme.accent) }
                VStack(alignment: .leading, spacing: 2) {
                    Text(url.deletingPathExtension().lastPathComponent)
                        .font(.ui(16, "SemiBold")).foregroundStyle(Theme.textPrimary)
                    Text(url.deletingLastPathComponent().path)
                        .font(.mono(11)).foregroundStyle(Theme.textMuted)
                        .lineLimit(1).truncationMode(.middle)
                }
                Spacer()
                Image(systemName: "chevron.right").font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Theme.textFaint)
            }
            .padding(14).nightCard().contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    /// A favourite folder (left-aligned). Click it to browse and open the files
    /// inside (navigating sub-folders); the minus removes the favourite.
    private func favoriteCard(_ folder: URL) -> some View {
        HStack(spacing: 13) {
            Button { browseTarget = BrowseTarget(url: folder) } label: {
                HStack(spacing: 13) {
                    tile { Image(systemName: "folder.fill").foregroundStyle(Theme.accent) }
                    VStack(alignment: .leading, spacing: 2) {
                        Text(folder.lastPathComponent)
                            .font(.ui(16, "SemiBold")).foregroundStyle(Theme.textPrimary).lineLimit(1)
                        Text("\(Favorites.children(of: folder).files.count) files")
                            .font(.mono(11)).foregroundStyle(Theme.textMuted)
                    }
                    Spacer()
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help("Browse this folder")

            Button { Favorites.remove(folder) } label: { Image(systemName: "minus.circle") }
                .buttonStyle(.plain).foregroundStyle(Theme.textFaint)
                .help("Remove from favorites")
        }
        .padding(14).nightCard()
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
                Text(AppInfo.buildLine).microLabel()
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
        ZStack {
            DotGrid().opacity(0.6)
            VStack(spacing: 14) {
                ZStack {
                    Circle().strokeBorder(Theme.accent.opacity(dropTargeted ? 1 : 0.7), lineWidth: 1.5)
                        .frame(width: 56, height: 56)
                        .shadow(color: Theme.accent.opacity(dropTargeted ? 0.6 : 0.25), radius: 10)
                    Image(systemName: "arrow.down").font(.system(size: 19, weight: .semibold))
                        .foregroundStyle(Theme.accent)
                }
                Text("Drop a PDF, .tex or .pptx to open")
                    .font(.display(18)).foregroundStyle(Theme.textPrimary)
                    .multilineTextAlignment(.center)
                Text("…or drop a folder to add it to favourites")
                    .font(.ui(13)).foregroundStyle(Theme.textFaint)
                    .multilineTextAlignment(.center)
            }
        }
        .frame(maxWidth: .infinity, minHeight: 240)
        .background(dropTargeted ? Theme.accentDim : Color.clear)
        .clipShape(RoundedRectangle(cornerRadius: 14))
        .overlay(RoundedRectangle(cornerRadius: 14)
            .strokeBorder(dropTargeted ? Theme.accent : Theme.hairlineStrong,
                          style: StrokeStyle(lineWidth: 1.5, dash: [5])))
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

/// A faint dotted grid, used behind the drop zone.
struct DotGrid: View {
    var step: CGFloat = 15

    var body: some View {
        Canvas { ctx, size in
            let r: CGFloat = 0.9
            var y = step
            while y < size.height {
                var x = step
                while x < size.width {
                    ctx.fill(Path(ellipseIn: CGRect(x: x - r, y: y - r, width: 2 * r, height: 2 * r)),
                             with: .color(Theme.textFaint.opacity(0.55)))
                    x += step
                }
                y += step
            }
        }
    }
}

/// Identifies the favourite folder currently being browsed (for `.sheet(item:)`).
struct BrowseTarget: Identifiable {
    let id = UUID()
    let url: URL
}

/// A small file browser for a favourite folder: navigate into sub-folders and
/// open a `.pdf` or `.tex`. A search field and pinned section headers keep it
/// organised when a folder holds many files. Presented as a sheet.
struct FolderBrowser: View {
    let root: URL
    let onOpen: (URL) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var stack: [URL]
    @State private var query = ""

    init(root: URL, onOpen: @escaping (URL) -> Void) {
        self.root = root
        self.onOpen = onOpen
        _stack = State(initialValue: [root])
    }

    private var current: URL { stack.last ?? root }

    private func matches(_ url: URL) -> Bool {
        query.isEmpty || url.lastPathComponent.localizedCaseInsensitiveContains(query)
    }

    var body: some View {
        let kids = Favorites.children(of: current)
        let folders = kids.folders.filter(matches)
        let files = kids.files.filter(matches)

        VStack(spacing: 0) {
            // Header: back · current folder · done.
            HStack(spacing: 10) {
                Button { if stack.count > 1 { stack.removeLast(); query = "" } } label: {
                    Image(systemName: "chevron.left")
                }
                .buttonStyle(.plain)
                .disabled(stack.count <= 1)
                .foregroundStyle(stack.count > 1 ? Theme.textPrimary : Theme.textFaint)

                Image(systemName: "folder.fill").foregroundStyle(Theme.accent)
                Text(current.lastPathComponent)
                    .font(.ui(15, "SemiBold")).foregroundStyle(Theme.textPrimary).lineLimit(1)
                Spacer()
                Button("Done") { dismiss() }.buttonStyle(.plain).foregroundStyle(Theme.accent)
            }
            .padding(14)

            // Search.
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass").foregroundStyle(Theme.textMuted)
                TextField("Search", text: $query).textFieldStyle(.plain)
            }
            .padding(.horizontal, 10).padding(.vertical, 7)
            .background(Theme.inset, in: RoundedRectangle(cornerRadius: 8))
            .padding(.horizontal, 12).padding(.bottom, 10)

            Rectangle().fill(Theme.hairline).frame(height: 1)

            if folders.isEmpty && files.isEmpty {
                Spacer()
                Text(query.isEmpty ? "Empty folder" : "No matches")
                    .font(.ui(14)).foregroundStyle(Theme.textMuted)
                Spacer()
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 3, pinnedViews: [.sectionHeaders]) {
                        if !folders.isEmpty {
                            Section {
                                ForEach(folders, id: \.self) { folderRow($0) }
                            } header: { sectionLabel("Folders", folders.count) }
                        }
                        if !files.isEmpty {
                            Section {
                                ForEach(files, id: \.self) { fileRow($0) }
                            } header: { sectionLabel("Files", files.count) }
                        }
                    }
                    .padding(8)
                }
            }
        }
        .frame(width: 380, height: 460)
        .background(Theme.base)
    }

    private func sectionLabel(_ title: String, _ count: Int) -> some View {
        HStack {
            Text("\(title) · \(count)")
                .font(.mono(10)).textCase(.uppercase).tracking(1).foregroundStyle(Theme.textMuted)
            Spacer()
        }
        .padding(.horizontal, 6).padding(.vertical, 6)
        .background(Theme.base)
    }

    private func folderRow(_ url: URL) -> some View {
        Button { stack.append(url); query = "" } label: {
            HStack(spacing: 11) {
                Image(systemName: "folder.fill").foregroundStyle(Theme.accent).frame(width: 22)
                Text(url.lastPathComponent).font(.ui(14)).foregroundStyle(Theme.textPrimary).lineLimit(1)
                Spacer()
                Image(systemName: "chevron.right").font(.caption).foregroundStyle(Theme.textFaint)
            }
            .padding(.horizontal, 12).padding(.vertical, 9).contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .background(Theme.surface, in: RoundedRectangle(cornerRadius: 8))
    }

    private func fileRow(_ url: URL) -> some View {
        Button { onOpen(url) } label: {
            HStack(spacing: 11) {
                Text(url.pathExtension.uppercased())
                    .font(.mono(9, bold: true)).foregroundStyle(Theme.accent)
                    .frame(width: 30)
                    .padding(.vertical, 4)
                    .background(Theme.accentDim, in: RoundedRectangle(cornerRadius: 5))
                Text(url.deletingPathExtension().lastPathComponent)
                    .font(.ui(14)).foregroundStyle(Theme.textPrimary).lineLimit(1)
                Spacer()
                Image(systemName: "arrow.up.forward.app").font(.caption).foregroundStyle(Theme.textFaint)
            }
            .padding(.horizontal, 12).padding(.vertical, 8).contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .background(Theme.surface, in: RoundedRectangle(cornerRadius: 8))
    }
}
