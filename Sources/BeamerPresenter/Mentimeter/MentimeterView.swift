import SwiftUI

/// The Mentimeter window (Phase 1): an embedded browser with a persistent login,
/// so you can sign in and present a poll at the start of a lecture. Audience
/// integration and result downloads follow in later phases (see docs/MENTIMETER.md).
struct MentimeterView: View {
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
        }
        .frame(minWidth: 760, minHeight: 520)
    }
}
