import SwiftUI
import AppKit
import WebKit

/// A shared, persistent web session for Mentimeter so the presenter window — and,
/// later, the audience view — are the *same* logged-in session. Cookies live in
/// the default (on-disk) data store, so the login survives relaunches. The app
/// itself never sees the password: the user signs in on the real Mentimeter page
/// inside the web view.
enum MentiSession {
    static func configuration() -> WKWebViewConfiguration {
        let config = WKWebViewConfiguration()
        config.websiteDataStore = .default()      // persistent cookies → shared login
        return config
    }

    /// Drops the whole web session, so the next person starts at Mentimeter's
    /// login page — needed on a shared podium Mac, where closing the window
    /// otherwise leaves the previous lecturer signed in. Everything goes, not
    /// just mentimeter.com: SSO sign-ins ("continue with Google") live in the
    /// same store, and the app owns no other web view whose state could be
    /// lost. `done` is called on the main thread.
    static func signOut(then done: @escaping () -> Void) {
        WKWebsiteDataStore.default()
            .removeData(ofTypes: WKWebsiteDataStore.allWebsiteDataTypes(),
                        modifiedSince: .distantPast, completionHandler: done)
    }
}

/// Owns a `WKWebView` and publishes its navigation state for a SwiftUI toolbar.
final class MentiBrowser: NSObject, ObservableObject {
    static let home = URL(string: "https://www.mentimeter.com/app")!

    let webView: WKWebView

    @Published private(set) var canGoBack = false
    @Published private(set) var canGoForward = false
    @Published private(set) var isLoading = false
    @Published private(set) var urlString = ""
    @Published private(set) var pageTitle = ""

    /// Where a result export should default to (the current deck's folder).
    var deckFolder: (() -> URL?)?

    /// Where an in-flight download streams to, and the file the user picked
    /// that it replaces once the transfer finished.
    private struct Destination {
        let temp: URL
        let final: URL
    }

    private var observations: [NSKeyValueObservation] = []
    private var downloadDestinations: [ObjectIdentifier: Destination] = [:]

    override init() {
        webView = WKWebView(frame: .zero, configuration: MentiSession.configuration())
        super.init()
        webView.allowsBackForwardNavigationGestures = true
        webView.uiDelegate = self
        webView.navigationDelegate = self
        observe()
        load(Self.home)
    }

    // WKWebView delivers these KVO changes on the main thread.
    private func observe() {
        observations = [
            webView.observe(\.canGoBack, options: [.initial, .new]) { [weak self] wv, _ in
                self?.canGoBack = wv.canGoBack
            },
            webView.observe(\.canGoForward, options: [.initial, .new]) { [weak self] wv, _ in
                self?.canGoForward = wv.canGoForward
            },
            webView.observe(\.isLoading, options: [.initial, .new]) { [weak self] wv, _ in
                self?.isLoading = wv.isLoading
            },
            webView.observe(\.url, options: [.initial, .new]) { [weak self] wv, _ in
                self?.urlString = wv.url?.absoluteString ?? ""
            },
            webView.observe(\.title, options: [.initial, .new]) { [weak self] wv, _ in
                self?.pageTitle = wv.title ?? ""
            }
        ]
    }

    func load(_ url: URL) { webView.load(URLRequest(url: url)) }
    func goHome() { load(Self.home) }
    func goBack() { webView.goBack() }
    func goForward() { webView.goForward() }
    func reloadOrStop() {
        if isLoading { webView.stopLoading() } else { webView.reload() }
    }

    /// Signs out of Mentimeter (and of any SSO provider used to reach it) and
    /// returns to the login page.
    func signOut() {
        MentiSession.signOut { [weak self] in self?.goHome() }
    }

    /// The page currently shown — captured when presenting on the audience screen.
    var currentURL: URL? { webView.url }
}

// Route result exports (Excel/PDF "attachment" responses) to a download.
extension MentiBrowser: WKNavigationDelegate {
    func webView(_ webView: WKWebView, decidePolicyFor navigationResponse: WKNavigationResponse,
                 decisionHandler: @escaping (WKNavigationResponsePolicy) -> Void) {
        if let http = navigationResponse.response as? HTTPURLResponse,
           let disposition = http.value(forHTTPHeaderField: "Content-Disposition"),
           disposition.lowercased().contains("attachment") {
            decisionHandler(.download)
            return
        }
        decisionHandler(navigationResponse.canShowMIMEType ? .allow : .download)
    }

    func webView(_ webView: WKWebView, navigationResponse: WKNavigationResponse, didBecome download: WKDownload) {
        download.delegate = self
    }

    func webView(_ webView: WKWebView, navigationAction: WKNavigationAction, didBecome download: WKDownload) {
        download.delegate = self
    }
}

// Ask where to save the export (defaulting to the deck's folder) and remember it.
extension MentiBrowser: WKDownloadDelegate {
    func download(_ download: WKDownload, decideDestinationUsing response: URLResponse,
                  suggestedFilename: String, completionHandler: @escaping (URL?) -> Void) {
        let panel = NSSavePanel()
        panel.nameFieldStringValue = suggestedFilename
        panel.canCreateDirectories = true
        if let folder = deckFolder?() { panel.directoryURL = folder }
        guard panel.runModal() == .OK, let url = panel.url else {
            completionHandler(nil)
            return
        }
        // Stream into a sibling rather than the file the user picked, so a
        // transfer that breaks half-way can't take last week's export with it;
        // the chosen file is only replaced once the download finished. (A
        // sandboxed build would have to use the temp directory instead: the
        // save panel grants the chosen path, not its siblings.)
        let temp = url.appendingPathExtension("download")
        try? FileManager.default.removeItem(at: temp)   // WKDownload won't overwrite
        downloadDestinations[ObjectIdentifier(download)] = Destination(temp: temp, final: url)
        completionHandler(temp)
    }

    func downloadDidFinish(_ download: WKDownload) {
        let id = ObjectIdentifier(download)
        guard let dest = downloadDestinations.removeValue(forKey: id) else { return }
        if install(dest) { MentiResults.add(dest.final) }
    }

    func download(_ download: WKDownload, didFailWithError error: Error, resumeData: Data?) {
        let id = ObjectIdentifier(download)
        guard let dest = downloadDestinations.removeValue(forKey: id) else { return }
        try? FileManager.default.removeItem(at: dest.temp)   // no half file left behind
        // The file the user picked is untouched — but say the export failed
        // rather than leaving them with last week's results and no warning.
        let failure = error as NSError
        if !(failure.domain == NSURLErrorDomain && failure.code == NSURLErrorCancelled) {
            report("Could not download the exported results", error.localizedDescription)
        }
    }

    /// Moves the finished download onto the file the user asked for, replacing
    /// an existing one only now — and keeping it if the swap fails.
    private func install(_ dest: Destination) -> Bool {
        let fm = FileManager.default
        do {
            if fm.fileExists(atPath: dest.final.path) {
                _ = try fm.replaceItemAt(dest.final, withItemAt: dest.temp)
            } else {
                try fm.moveItem(at: dest.temp, to: dest.final)
            }
            return true
        } catch {
            try? fm.removeItem(at: dest.temp)
            report("Could not save the exported results", error.localizedDescription)
            return false
        }
    }

    /// Downloads run without a sheet of their own, so failures are reported
    /// the way the rest of the app reports them.
    private func report(_ message: String, _ detail: String) {
        let alert = NSAlert()
        alert.messageText = message
        alert.informativeText = detail
        alert.runModal()
    }
}

// Login flows (e.g. "Sign in with Google/SSO") often try to open a new window;
// load such requests in the same web view instead of dropping them.
extension MentiBrowser: WKUIDelegate {
    func webView(_ webView: WKWebView, createWebViewWith configuration: WKWebViewConfiguration,
                 for navigationAction: WKNavigationAction,
                 windowFeatures: WKWindowFeatures) -> WKWebView? {
        if navigationAction.targetFrame == nil { webView.load(navigationAction.request) }
        return nil
    }
}

/// Hosts the browser's `WKWebView` in SwiftUI.
struct MentiWebView: NSViewRepresentable {
    let browser: MentiBrowser
    func makeNSView(context: Context) -> WKWebView { browser.webView }
    func updateNSView(_ nsView: WKWebView, context: Context) {}
}
