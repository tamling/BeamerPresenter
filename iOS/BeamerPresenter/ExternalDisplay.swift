import SwiftUI
import UIKit

/// Mirrors the current slide onto a connected external display (USB‑C / AirPlay)
/// while the iPad keeps the presenter console. The audience window has to live in
/// the `UIWindowScene` iOS creates for the external screen: in a scene‑based
/// (SwiftUI) app a scene‑less `UIWindow` is never put on a second screen, so the
/// old `UIScreen` path could not work. (The Info.plist must carry
/// `UIApplicationSceneManifest` → `UIApplicationSupportsMultipleScenes` for such
/// a scene to be offered at all; see CHECKLIST.md.)
@MainActor
final class ExternalDisplayManager: ObservableObject {
    /// True only while an audience window is really live on an external scene.
    @Published private(set) var isConnected = false

    private var externalWindow: UIWindow?
    private weak var attachedScene: UIWindowScene?
    private weak var model: PresentationModel?
    private var observing = false

    func start(model: PresentationModel) {
        self.model = model
        // A `WindowGroup`'s `.task` can run more than once — observe only once.
        if !observing {
            observing = true
            let center = NotificationCenter.default
            center.addObserver(self, selector: #selector(sceneConnected(_:)),
                               name: UIScene.willConnectNotification, object: nil)
            center.addObserver(self, selector: #selector(sceneDisconnected(_:)),
                               name: UIScene.didDisconnectNotification, object: nil)
        }
        // Attach if a display scene is already connected at launch.
        attachToConnectedScene()
    }

    @objc private func sceneConnected(_ note: Notification) {
        if let scene = externalScene(note.object) { attach(to: scene) }
    }

    @objc private func sceneDisconnected(_ note: Notification) {
        // Only tear down for the scene the audience window actually lives on.
        guard let scene = externalScene(note.object), scene === attachedScene else { return }
        externalWindow?.isHidden = true
        externalWindow = nil
        attachedScene = nil
        isConnected = false
        model?.stopMenti()   // nothing is being projected any more
        // A display hand‑off can connect the new scene before the old one goes
        // away, so pick up whatever external scene is left.
        attachToConnectedScene()
    }

    /// The object of a scene notification, when it is an external‑display scene.
    private func externalScene(_ object: Any?) -> UIWindowScene? {
        guard let scene = object as? UIWindowScene,
              scene.session.role == .windowExternalDisplayNonInteractive else { return nil }
        return scene
    }

    private func attachToConnectedScene() {
        for scene in UIApplication.shared.connectedScenes {
            if let external = externalScene(scene) {
                attach(to: external)
                return
            }
        }
    }

    private func attach(to scene: UIWindowScene) {
        guard let model, externalWindow == nil else { return }
        // `UIWindow(windowScene:)` takes the scene's bounds and UIKit keeps it in
        // step with the screen, so the frame is never set (or re‑set) by hand.
        let window = UIWindow(windowScene: scene)
        let host = UIHostingController(rootView: AudienceSlideView(model: model)
            .ignoresSafeArea())
        host.view.backgroundColor = .black
        window.rootViewController = host
        window.isHidden = false
        externalWindow = window
        attachedScene = scene
        isConnected = true
    }
}
