import SwiftUI
import UIKit

/// Mirrors the current slide onto a connected external display (USB‑C / AirPlay)
/// while the iPad keeps the presenter console. Uses the `UIScreen` API: it is
/// marked deprecated on iOS 16 but remains the simplest reliable way to put
/// distinct content on a second screen. (See CHECKLIST.md for the scene‑based
/// modernisation.)
@MainActor
final class ExternalDisplayManager: ObservableObject {
    @Published private(set) var isConnected = false

    private var externalWindow: UIWindow?
    private weak var model: PresentationModel?

    func start(model: PresentationModel) {
        self.model = model
        let center = NotificationCenter.default
        center.addObserver(self, selector: #selector(screenConnected(_:)),
                           name: UIScreen.didConnectNotification, object: nil)
        center.addObserver(self, selector: #selector(screenDisconnected(_:)),
                           name: UIScreen.didDisconnectNotification, object: nil)
        // Attach if a display is already connected at launch.
        if let screen = UIScreen.screens.first(where: { $0 !== UIScreen.main }) {
            attach(to: screen)
        }
    }

    @objc private func screenConnected(_ note: Notification) {
        if let screen = note.object as? UIScreen { attach(to: screen) }
    }

    @objc private func screenDisconnected(_ note: Notification) {
        externalWindow?.isHidden = true
        externalWindow = nil
        isConnected = false
    }

    private func attach(to screen: UIScreen) {
        guard let model, externalWindow == nil else { return }
        let window = UIWindow(frame: screen.bounds)
        window.screen = screen
        let host = UIHostingController(rootView: AudienceSlideView(model: model)
            .ignoresSafeArea())
        host.view.backgroundColor = .black
        window.rootViewController = host
        window.isHidden = false
        externalWindow = window
        isConnected = true
    }
}
