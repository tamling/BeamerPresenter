import SwiftUI
import AppKit

/// The Mentimeter window: an embedded browser with a persistent login, plus a
/// bar to push the current page onto the audience screen and drive it (next /
/// previous question). See docs/MENTIMETER.md.
struct MentimeterView: View {
    @EnvironmentObject var state: PresentationState
    @StateObject private var browser = MentiBrowser()
    @State private var results = MentiResults.load()
    @State private var recents = MentiLinks.load()

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                Button { browser.goBack() } label: { Image(systemName: "chevron.left") }
                    .disabled(!browser.canGoBack)
                Button { browser.goForward() } label: { Image(systemName: "chevron.right") }
                    .disabled(!browser.canGoForward)
                Button { browser.reloadOrStop() } label: {
                    Image(systemName: browser.isLoading ? "xmark" : "arrow.clockwise")
                }
                Button { browser.goHome() } label: { Image(systemName: "house") }
                    .help("Back to your Mentimeter dashboard")
                recentsMenu

                Text(browser.urlString)
                    .font(.caption.monospaced()).foregroundStyle(.secondary)
                    .lineLimit(1).truncationMode(.middle)
                    .frame(maxWidth: .infinity, alignment: .leading)

                if browser.isLoading { ProgressView().controlSize(.small) }
                resultsMenu
            }
            .buttonStyle(.borderless)
            .padding(.horizontal, 12).padding(.vertical, 8)

            Divider()
            MentiWebView(browser: browser)
            Divider()
            audienceBar
        }
        .frame(minWidth: 760, minHeight: 520)
        .onAppear { browser.deckFolder = { state.sourceURL?.deletingLastPathComponent() } }
        .onReceive(NotificationCenter.default.publisher(for: MentiResults.didChange)) { _ in
            results = MentiResults.load()
        }
        .onReceive(NotificationCenter.default.publisher(for: MentiLinks.didChange)) { _ in
            recents = MentiLinks.load()
        }
    }

    /// One-click relaunch of a recently presented menti.
    private var recentsMenu: some View {
        Menu {
            if recents.isEmpty {
                Text("No recent menti yet")
            } else {
                ForEach(recents) { link in
                    Button(link.title) {
                        browser.load(link.url)
                        state.startMenti(link.url)
                    }
                }
                Divider()
                Button("Clear recents", role: .destructive) {
                    recents.forEach { MentiLinks.remove($0.url) }
                }
            }
        } label: {
            Image(systemName: "clock.arrow.circlepath")
        }
        .menuIndicator(.hidden)
        .fixedSize()
        .help("Recently presented mentis")
    }

    /// Recently downloaded result files → reveal in Finder.
    private var resultsMenu: some View {
        Menu {
            if results.isEmpty {
                Text("No downloaded results yet")
            } else {
                ForEach(results, id: \.self) { url in
                    Button(url.lastPathComponent) {
                        NSWorkspace.shared.activateFileViewerSelecting([url])
                    }
                }
            }
        } label: {
            Image(systemName: "tray.and.arrow.down")
        }
        .menuIndicator(.hidden)
        .fixedSize()
        .help("Downloaded Mentimeter results")
    }

    /// Push the current page to the projector and control it, or stop.
    @ViewBuilder private var audienceBar: some View {
        HStack(spacing: 10) {
            if state.mentiActive {
                Circle().fill(.green).frame(width: 8, height: 8)
                Text("Live on audience").font(.callout.weight(.medium))
                Spacer()
                Button { MentiControl.shared.prev() } label: { Label("Previous", systemImage: "chevron.left") }
                Button { MentiControl.shared.next() } label: { Label("Next", systemImage: "chevron.right") }
                Button { MentiControl.shared.reload() } label: { Image(systemName: "arrow.clockwise") }
                Button(role: .destructive) { state.stopMenti() } label: { Label("Stop", systemImage: "stop.fill") }
                    .help("Return the audience screen to your slides")
            } else {
                Image(systemName: "info.circle").foregroundStyle(.secondary)
                Text("Open your menti and hit Present, then show it on the projector.")
                    .font(.callout).foregroundStyle(.secondary)
                Spacer()
                Button {
                    if let url = browser.currentURL {
                        MentiLinks.add(title: browser.pageTitle, url: url)
                        state.startMenti(url)
                    }
                } label: {
                    Label("Present on audience", systemImage: "play.rectangle.on.rectangle")
                }
                .keyboardShortcut(.return, modifiers: [.command])
                .disabled(browser.currentURL == nil)
            }
        }
        .padding(.horizontal, 12).padding(.vertical, 8)
    }
}
