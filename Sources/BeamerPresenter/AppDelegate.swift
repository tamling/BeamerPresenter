import AppKit
import SwiftUI
import UniformTypeIdentifiers

final class AppDelegate: NSObject, NSApplicationDelegate {
    let state = PresentationState()
    private var presenterWindow: NSWindow?
    private var audienceWindow: NSWindow?
    private var keyMonitor: Any?

    func applicationDidFinishLaunching(_ notification: Notification) {
        setupMenu()
        installKeyMonitor()
        NotificationCenter.default.addObserver(
            self, selector: #selector(screensChanged),
            name: NSApplication.didChangeScreenParametersNotification, object: nil)
        buildPresenterWindow()
        NSApp.activate(ignoringOtherApps: true)
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }

    // MARK: - Menu

    private func setupMenu() {
        let mainMenu = NSMenu()
        let appItem = NSMenuItem()
        mainMenu.addItem(appItem)
        let appMenu = NSMenu()
        appItem.submenu = appMenu
        appMenu.addItem(withTitle: "Open…", action: #selector(openDocument(_:)), keyEquivalent: "o")
        appMenu.addItem(NSMenuItem.separator())
        appMenu.addItem(withTitle: "Quit", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        NSApp.mainMenu = mainMenu
    }

    @objc func openDocument(_ sender: Any?) {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [UTType.pdf]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        guard panel.runModal() == .OK, let url = panel.url else { return }
        load(url: url)
    }

    private func load(url: URL) {
        guard state.load(url: url) else {
            let alert = NSAlert()
            alert.messageText = "Could not open PDF"
            alert.informativeText = url.lastPathComponent
            alert.runModal()
            return
        }
        RecentFiles.add(url)
        buildAudienceWindowIfNeeded()
        positionWindows()
        audienceWindow?.orderFront(nil)
        presenterWindow?.makeKeyAndOrderFront(nil)
    }

    // MARK: - Windows

    private func buildPresenterWindow() {
        let root = RootPresenterView(
            onOpen: { [weak self] in self?.openDocument(nil) },
            onOpenURL: { [weak self] url in self?.load(url: url) }
        ).environmentObject(state)

        let presenter = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 1280, height: 820),
            styleMask: [.titled, .closable, .resizable, .miniaturizable],
            backing: .buffered, defer: false)
        presenter.title = "BeamerPresenter"
        presenter.contentView = NSHostingView(rootView: root)
        presenter.center()
        presenter.makeKeyAndOrderFront(nil)
        presenterWindow = presenter
    }

    private func buildAudienceWindowIfNeeded() {
        guard audienceWindow == nil else { return }
        let multiScreen = NSScreen.screens.count > 1
        let style: NSWindow.StyleMask = multiScreen ? [.borderless] : [.titled, .closable, .resizable]

        let audience = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 1280, height: 720),
            styleMask: style, backing: .buffered, defer: false)
        audience.title = "Audience"
        audience.contentView = NSHostingView(rootView: AudienceView().environmentObject(state))
        if multiScreen {
            audience.level = .mainMenu
            audience.collectionBehavior = [.fullScreenAuxiliary, .canJoinAllSpaces]
        }
        audienceWindow = audience
    }

    @objc private func screensChanged() { positionWindows() }

    /// Audience window fills the external display; presenter window stays on the
    /// built-in display.
    private func positionWindows() {
        let screens = NSScreen.screens
        guard !screens.isEmpty else { return }

        if screens.count > 1 {
            audienceWindow?.setFrame(screens[1].frame, display: true)
            if let p = presenterWindow {
                let visible = (NSScreen.main ?? screens[0]).visibleFrame
                let size = p.frame.size
                p.setFrameOrigin(NSPoint(x: visible.midX - size.width / 2,
                                         y: visible.midY - size.height / 2))
            }
        }
        // Single-screen: leave the (titled) audience window where the user puts it.
    }

    // MARK: - Keyboard

    private func installKeyMonitor() {
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self else { return event }
            return self.handleKey(event) ? nil : event
        }
    }

    /// Returns true if the key was consumed. Only active once a deck is loaded.
    private func handleKey(_ event: NSEvent) -> Bool {
        guard state.isLoaded else { return false }
        switch event.keyCode {
        case 124, 49, 121: state.next()              // → / space / page down
        case 123, 116:     state.previous()          // ← / page up
        case 115:          state.goToFirst()         // home
        case 119:          state.goToLast()          // end
        case 5:            state.showOverview.toggle()   // G
        case 11:           state.blackout.toggle()       // B
        case 15:           state.resetTimer()            // R
        case 35:           state.toggleTool(.pen)        // P
        case 37:           state.toggleTool(.laser)      // L
        case 6:            state.undoStroke()            // Z
        case 8:            state.clearStrokes()          // C
        case 53:                                         // esc
            if state.tool != .none { state.tool = .none; state.laserPoint = nil }
            else if state.showOverview { state.showOverview = false }
            else { return false }
        default:           return false
        }
        return true
    }
}
