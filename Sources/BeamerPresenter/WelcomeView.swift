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
                Image(systemName: "chart.bar.fill")
                    .font(.system(size: 30, weight: .bold))
                    .foregroundStyle(Theme.accent)
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
        ScrollView {
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
                        VStack(spacing: 8) { ForEach(recents, id: \.self) { recentCard($0) } }
                    }
                }

                dropZone.frame(minHeight: 240)
            }
            .padding(28)
        }
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

    private func favoriteCard(_ folder: URL) -> some View {
        HStack(spacing: 13) {
            Menu {
                let pdfs = Favorites.pdfs(in: folder)
                if pdfs.isEmpty {
                    Text("No PDFs in this folder")
                } else {
                    ForEach(pdfs, id: \.self) { p in
                        Button(p.deletingPathExtension().lastPathComponent) { onOpenURL(p) }
                    }
                }
            } label: {
                HStack(spacing: 13) {
                    tile { Image(systemName: "folder.fill").foregroundStyle(Theme.accent) }
                    VStack(alignment: .leading, spacing: 2) {
                        Text(folder.lastPathComponent)
                            .font(.ui(16, "SemiBold")).foregroundStyle(Theme.textPrimary).lineLimit(1)
                        Text("\(Favorites.pdfs(in: folder).count) presentations")
                            .font(.mono(11)).foregroundStyle(Theme.textMuted)
                    }
                    Spacer()
                }
            }
            .menuStyle(.borderlessButton).menuIndicator(.hidden)

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
                Text("…or drop a folder to add it to favourites")
                    .font(.ui(13)).foregroundStyle(Theme.textFaint)
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
