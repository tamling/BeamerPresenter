import SwiftUI
import UIKit
import WebKit

/// Drives the external (audience) Mentimeter web view from the iPad's control
/// strip. It clicks Mentimeter's on-screen nav button when present, and only
/// falls back to a synthetic arrow key otherwise (so it never advances twice).
final class MentiControl {
    static let shared = MentiControl()
    weak var webView: WKWebView?

    func next()   { navigate(["next slide", "next question", "go forward"], key: "ArrowRight", keyCode: 39) }
    func prev()   { navigate(["previous slide", "previous question", "go back"], key: "ArrowLeft", keyCode: 37) }
    func reload() { webView?.reload() }

    private func navigate(_ labels: [String], key: String, keyCode: Int) {
        let list = labels.map { "'\($0)'" }.joined(separator: ",")
        let js = """
        (function(){
          var labels=[\(list)];
          var els=document.querySelectorAll('button,a,[role=button]');
          for(var i=0;i<els.length;i++){
            var el=els[i];
            var t=((el.getAttribute('aria-label')||'')+' '+(el.getAttribute('title')||'')+' '+(el.getAttribute('data-testid')||'')).toLowerCase();
            for(var j=0;j<labels.length;j++){ if(t.indexOf(labels[j])>=0){ el.click(); return; } }
          }
          var o={key:'\(key)',code:'\(key)',keyCode:\(keyCode),which:\(keyCode),bubbles:true};
          document.dispatchEvent(new KeyboardEvent('keydown',o));
          document.dispatchEvent(new KeyboardEvent('keyup',o));
        })();
        """
        webView?.evaluateJavaScript(js, completionHandler: nil)
    }
}

/// The Mentimeter present view shown on the external/audience display. Shares the
/// logged-in session and registers itself with `MentiControl`.
struct MentiAudienceView: UIViewRepresentable {
    let url: URL

    func makeUIView(context: Context) -> WKWebView {
        let webView = WKWebView(frame: .zero, configuration: MentiSession.configuration())
        webView.load(URLRequest(url: url))
        context.coordinator.url = url
        MentiControl.shared.webView = webView
        return webView
    }

    func updateUIView(_ webView: WKWebView, context: Context) {
        if context.coordinator.url != url {
            context.coordinator.url = url
            webView.load(URLRequest(url: url))
        }
        MentiControl.shared.webView = webView
    }

    func makeCoordinator() -> Coordinator { Coordinator() }
    final class Coordinator { var url: URL? }
}
