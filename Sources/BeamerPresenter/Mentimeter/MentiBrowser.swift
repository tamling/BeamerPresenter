import SwiftUI
import AppKit
import WebKit

/// A shared, persistent web session for Mentimeter so the presenter window — and,
/// later, the audience view — are the *same* logged-in session. Cookies live in
/// the default (on-disk) data store, so the login survives relaunches. The app
/// itself never sees the password: the user signs in on the real Mentimeter page
/// inside the web view.
enum MentiSession {
    static let processPool = WKProcessPool()

    static func configuration() -> WKWebViewConfiguration {
        let config = WKWebViewConfiguration()
        config.websiteDataStore = .default()      // persistent cookies (shared)
        config.processPool = processPool          // shared so views stay in sync
        return config
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

    private var observations: [NSKeyValueObservation] = []
    private var downloadDestinations: [ObjectIdentifier: URL] = [:]

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
    func reloadOrStop() { isLoading ? webView.stopLoading() : webView.reload() }

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
        try? FileManager.default.removeItem(at: url)   // WKDownload won't overwrite
        downloadDestinations[ObjectIdentifier(download)] = url
        completionHandler(url)
    }

    func downloadDidFinish(_ download: WKDownload) {
        let id = ObjectIdentifier(download)
        if let url = downloadDestinations[id] { MentiResults.add(url) }
        downloadDestinations[id] = nil
    }

    func download(_ download: WKDownload, didFailWithError error: Error, resumeData: Data?) {
        downloadDestinations[ObjectIdentifier(download)] = nil
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
