import SwiftUI
import WebKit

/// Drives the audience-screen Mentimeter web view from the presenter's control
/// strip. Mentimeter's present mode responds to arrow keys, so "next/previous
/// question" is sent as synthetic key events into the page.
final class MentiControl {
    static let shared = MentiControl()
    weak var webView: WKWebView?

    func next()   { sendKey("ArrowRight", keyCode: 39) }
    func prev()   { sendKey("ArrowLeft",  keyCode: 37) }
    func reload() { webView?.reload() }

    private func sendKey(_ key: String, keyCode: Int) {
        let js = """
        (function(){var o={key:'\(key)',code:'\(key)',keyCode:\(keyCode),which:\(keyCode),bubbles:true};
        document.dispatchEvent(new KeyboardEvent('keydown',o));
        document.dispatchEvent(new KeyboardEvent('keyup',o));})();
        """
        webView?.evaluateJavaScript(js, completionHandler: nil)
    }
}

/// The Mentimeter present view shown on the audience/projector screen. It shares
/// the logged-in session (cookies + process pool) with the presenter's browser,
/// and registers itself with `MentiControl` so the presenter can advance slides.
struct MentiAudienceView: NSViewRepresentable {
    let url: URL

    func makeNSView(context: Context) -> WKWebView {
        let webView = WKWebView(frame: .zero, configuration: MentiSession.configuration())
        webView.load(URLRequest(url: url))
        context.coordinator.url = url
        MentiControl.shared.webView = webView
        return webView
    }

    func updateNSView(_ webView: WKWebView, context: Context) {
        if context.coordinator.url != url {            // the present URL changed
            context.coordinator.url = url
            webView.load(URLRequest(url: url))
        }
        MentiControl.shared.webView = webView
    }

    func makeCoordinator() -> Coordinator { Coordinator() }
    final class Coordinator { var url: URL? }
}
