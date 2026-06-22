import SwiftUI

/// The Mentimeter screen (iPad): an embedded browser with a persistent login,
/// plus a bar to present the current page on the external display and drive it
/// (next / previous question). Result exports are captured and shared.
struct MentimeterView: View {
    @EnvironmentObject var model: PresentationModel
    @EnvironmentObject var external: ExternalDisplayManager
    @Environment(\.dismiss) private var dismiss

    @StateObject private var browser = MentiBrowser()
    @State private var recents = MentiLinks.load()
    @State private var shareURL: URL?
    @State private var showShare = false

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                MentiWebView(browser: browser)
                Divider()
                audienceBar
            }
            .navigationTitle("Mentimeter")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItemGroup(placement: .navigationBarLeading) {
                    Button { browser.goBack() } label: { Image(systemName: "chevron.left") }
                        .disabled(!browser.canGoBack)
                    Button { browser.goForward() } label: { Image(systemName: "chevron.right") }
                        .disabled(!browser.canGoForward)
                    Button { browser.reloadOrStop() } label: {
                        Image(systemName: browser.isLoading ? "xmark" : "arrow.clockwise")
                    }
                    Button { browser.goHome() } label: { Image(systemName: "house") }
                    recentsMenu
                }
                ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } }
            }
        }
        .onAppear { browser.onDownloadFinished = { url in shareURL = url; showShare = true } }
        .onReceive(NotificationCenter.default.publisher(for: MentiLinks.didChange)) { _ in
            recents = MentiLinks.load()
        }
        .sheet(isPresented: $showShare) { if let url = shareURL { ShareSheet(items: [url]) } }
    }

    @ViewBuilder private var audienceBar: some View {
        HStack(spacing: 12) {
            if model.mentiActive {
                Circle().fill(.green).frame(width: 9, height: 9)
                Text("Live on display").font(.callout.weight(.medium))
                Spacer()
                Button { MentiControl.shared.prev() } label: { Image(systemName: "chevron.left") }
                Button { MentiControl.shared.next() } label: { Image(systemName: "chevron.right") }
                Button { MentiControl.shared.reload() } label: { Image(systemName: "arrow.clockwise") }
                Button(role: .destructive) { model.stopMenti() } label: { Label("Stop", systemImage: "stop.fill") }
            } else {
                Image(systemName: external.isConnected ? "tv" : "tv.slash")
                    .foregroundStyle(external.isConnected ? Color.accentColor : .secondary)
                Text(external.isConnected
                     ? "Open your menti, hit Present, then send it to the display."
                     : "Connect a display (USB-C / AirPlay) to project the poll.")
                    .font(.callout).foregroundStyle(.secondary).lineLimit(2)
                Spacer()
                Button {
                    if let url = browser.currentURL {
                        MentiLinks.add(title: browser.pageTitle, url: url)
                        model.startMenti(url)
                    }
                } label: { Label("Present on display", systemImage: "play.rectangle.on.rectangle") }
                    .buttonStyle(.borderedProminent)
                    .disabled(browser.currentURL == nil)
            }
        }
        .padding(.horizontal, 16).padding(.vertical, 10)
        .background(.bar)
    }

    private var recentsMenu: some View {
        Menu {
            if recents.isEmpty {
                Text("No recent menti yet")
            } else {
                ForEach(recents) { link in
                    Button(link.title) {
                        browser.load(link.url)
                        model.startMenti(link.url)
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
    }
}
