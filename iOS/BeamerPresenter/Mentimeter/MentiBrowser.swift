import SwiftUI
import UIKit
import WebKit

/// Shared, persistent Mentimeter session so the presenter view and the external
/// (audience) view are the *same* logged-in session. The app never sees the
/// password — the user signs in on the real Mentimeter page inside the web view.
enum MentiSession {
    static func configuration() -> WKWebViewConfiguration {
        let config = WKWebViewConfiguration()
        config.websiteDataStore = .default()      // persistent cookies → shared login
        return config
    }
}

/// Owns a `WKWebView` and publishes its navigation state for the SwiftUI toolbar.
final class MentiBrowser: NSObject, ObservableObject {
    static let home = URL(string: "https://www.mentimeter.com/app")!

    let webView: WKWebView

    @Published private(set) var canGoBack = false
    @Published private(set) var canGoForward = false
    @Published private(set) var isLoading = false
    @Published private(set) var urlString = ""
    @Published private(set) var pageTitle = ""

    /// Called on the main thread when a result export finished downloading.
    var onDownloadFinished: ((URL) -> Void)?

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

    private func observe() {
        observations = [
            webView.observe(\.canGoBack, options: [.initial, .new]) { [weak self] wv, _ in self?.canGoBack = wv.canGoBack },
            webView.observe(\.canGoForward, options: [.initial, .new]) { [weak self] wv, _ in self?.canGoForward = wv.canGoForward },
            webView.observe(\.isLoading, options: [.initial, .new]) { [weak self] wv, _ in self?.isLoading = wv.isLoading },
            webView.observe(\.url, options: [.initial, .new]) { [weak self] wv, _ in self?.urlString = wv.url?.absoluteString ?? "" },
            webView.observe(\.title, options: [.initial, .new]) { [weak self] wv, _ in self?.pageTitle = wv.title ?? "" }
        ]
    }

    func load(_ url: URL) { webView.load(URLRequest(url: url)) }
    func goHome() { load(Self.home) }
    func goBack() { webView.goBack() }
    func goForward() { webView.goForward() }
    func reloadOrStop() {
        if isLoading { webView.stopLoading() } else { webView.reload() }
    }
    var currentURL: URL? { webView.url }
}

// Route result exports to a download, save to a temp file, then share it.
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

extension MentiBrowser: WKDownloadDelegate {
    func download(_ download: WKDownload, decideDestinationUsing response: URLResponse,
                  suggestedFilename: String, completionHandler: @escaping (URL?) -> Void) {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("Menti", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        // Reduce the server-supplied name to a single safe path component (defense
        // in depth on top of WebKit's own sanitisation) so it can't escape `dir`.
        var name = (suggestedFilename as NSString).lastPathComponent
        if name.isEmpty || name == "." || name == ".." { name = "mentimeter-results" }
        let dest = dir.appendingPathComponent(name)
        try? FileManager.default.removeItem(at: dest)      // WKDownload won't overwrite
        downloadDestinations[ObjectIdentifier(download)] = dest
        completionHandler(dest)
    }

    func downloadDidFinish(_ download: WKDownload) {
        let id = ObjectIdentifier(download)
        if let url = downloadDestinations[id] { onDownloadFinished?(url) }
        downloadDestinations[id] = nil
    }

    func download(_ download: WKDownload, didFailWithError error: Error, resumeData: Data?) {
        downloadDestinations[ObjectIdentifier(download)] = nil
    }
}

// Login flows (SSO popups) often open a new window; load them in the same view.
extension MentiBrowser: WKUIDelegate {
    func webView(_ webView: WKWebView, createWebViewWith configuration: WKWebViewConfiguration,
                 for navigationAction: WKNavigationAction,
                 windowFeatures: WKWindowFeatures) -> WKWebView? {
        if navigationAction.targetFrame == nil { webView.load(navigationAction.request) }
        return nil
    }
}

/// Hosts the browser's `WKWebView` in SwiftUI.
struct MentiWebView: UIViewRepresentable {
    let browser: MentiBrowser
    func makeUIView(context: Context) -> WKWebView { browser.webView }
    func updateUIView(_ uiView: WKWebView, context: Context) {}
}
