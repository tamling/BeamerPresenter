import SwiftUI

/// The Mentimeter window: an embedded browser with a persistent login, plus a
/// bar to push the current page onto the audience screen and drive it (next /
/// previous question). See docs/MENTIMETER.md.
struct MentimeterView: View {
    @EnvironmentObject var state: PresentationState
    @StateObject private var browser = MentiBrowser()

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

                Text(browser.urlString)
                    .font(.caption.monospaced()).foregroundStyle(.secondary)
                    .lineLimit(1).truncationMode(.middle)
                    .frame(maxWidth: .infinity, alignment: .leading)

                if browser.isLoading { ProgressView().controlSize(.small) }
            }
            .buttonStyle(.borderless)
            .padding(.horizontal, 12).padding(.vertical, 8)

            Divider()
            MentiWebView(browser: browser)
            Divider()
            audienceBar
        }
        .frame(minWidth: 760, minHeight: 520)
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
                    if let url = browser.currentURL { state.startMenti(url) }
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
