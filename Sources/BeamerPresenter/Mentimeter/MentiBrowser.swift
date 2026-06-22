import SwiftUI
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

    private var observations: [NSKeyValueObservation] = []

    override init() {
        webView = WKWebView(frame: .zero, configuration: MentiSession.configuration())
        super.init()
        webView.allowsBackForwardNavigationGestures = true
        webView.uiDelegate = self
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
            }
        ]
    }

    func load(_ url: URL) { webView.load(URLRequest(url: url)) }
    func goHome() { load(Self.home) }
    func goBack() { webView.goBack() }
    func goForward() { webView.goForward() }
    func reloadOrStop() { isLoading ? webView.stopLoading() : webView.reload() }
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
