import AppKit
import SwiftUI
import UniformTypeIdentifiers

@MainActor
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

        // App menu — About (with version) + standard items.
        let appItem = NSMenuItem()
        mainMenu.addItem(appItem)
        let appMenu = NSMenu(title: AppInfo.name)
        appItem.submenu = appMenu
        add(to: appMenu, "About \(AppInfo.name)", #selector(showAbout(_:)))
        appMenu.addItem(.separator())
        appMenu.addItem(withTitle: "Hide \(AppInfo.name)",
                        action: #selector(NSApplication.hide(_:)), keyEquivalent: "h")
        appMenu.addItem(withTitle: "Quit \(AppInfo.name)",
                        action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")

        // File menu — open, favourites, close.
        let fileItem = NSMenuItem()
        mainMenu.addItem(fileItem)
        let fileMenu = NSMenu(title: "File")
        fileItem.submenu = fileMenu
        add(to: fileMenu, "Open…", #selector(openDocument(_:)), "o")
        add(to: fileMenu, "Add Folder to Favorites…", #selector(addFavoriteFolder(_:)), "d")
        fileMenu.addItem(.separator())
        add(to: fileMenu, "Close Presentation", #selector(closePresentation(_:)), "w")

        // View menu — mirrors the in-app navigation/tools (requires a deck).
        let viewItem = NSMenuItem()
        mainMenu.addItem(viewItem)
        let viewMenu = NSMenu(title: "View")
        viewItem.submenu = viewMenu
        add(to: viewMenu, "Next Slide", #selector(nextSlide(_:)), "]")
        add(to: viewMenu, "Previous Slide", #selector(previousSlide(_:)), "[")
        viewMenu.addItem(.separator())
        add(to: viewMenu, "Toggle Overview", #selector(toggleOverview(_:)), "1")
        add(to: viewMenu, "Black Out Audience", #selector(toggleBlackout(_:)), "b")
        viewMenu.addItem(.separator())
        add(to: viewMenu, "Toggle Whiteboard", #selector(toggleWhiteboard(_:)))
        add(to: viewMenu, "Save Whiteboard…", #selector(saveWhiteboard(_:)), "s")
        viewMenu.addItem(.separator())
        add(to: viewMenu, "Reset Timer", #selector(resetTimer(_:)), "r")

        NSApp.mainMenu = mainMenu
    }

    /// Adds an item targeting this delegate so menu validation/handling routes
    /// here rather than through the responder chain.
    @discardableResult
    private func add(to menu: NSMenu, _ title: String, _ action: Selector,
                     _ key: String = "") -> NSMenuItem {
        let item = menu.addItem(withTitle: title, action: action, keyEquivalent: key)
        item.target = self
        return item
    }

    /// Greys out deck-dependent commands until a presentation is loaded.
    func validateMenuItem(_ item: NSMenuItem) -> Bool {
        switch item.action {
        case #selector(closePresentation(_:)), #selector(nextSlide(_:)),
             #selector(previousSlide(_:)), #selector(toggleOverview(_:)),
             #selector(toggleBlackout(_:)), #selector(resetTimer(_:)),
             #selector(toggleWhiteboard(_:)):
            return state.isLoaded
        case #selector(saveWhiteboard(_:)):
            return state.isBoardActive
        default:
            return true
        }
    }

    @objc private func showAbout(_ sender: Any?) {
        NSApp.orderFrontStandardAboutPanel(options: [
            .applicationName: AppInfo.name,
            .applicationVersion: AppInfo.version,
            .credits: NSAttributedString(
                string: "Present LaTeX Beamer PDFs with speaker notes.",
                attributes: [.font: NSFont.systemFont(ofSize: 11)])
        ])
        NSApp.activate(ignoringOtherApps: true)
    }

    @objc private func addFavoriteFolder(_ sender: Any?) {
        let panel = NSOpenPanel()
        panel.title = "Add Folder to Favorites"
        panel.prompt = "Add"
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        guard panel.runModal() == .OK, let url = panel.url else { return }
        Favorites.add(url)
    }

    @objc private func closePresentation(_ sender: Any?) {
        guard state.isLoaded else { return }
        state.unload()
    }

    @objc private func nextSlide(_ sender: Any?)      { state.next() }
    @objc private func previousSlide(_ sender: Any?)  { state.previous() }
    @objc private func toggleOverview(_ sender: Any?) { state.showOverview.toggle() }
    @objc private func toggleBlackout(_ sender: Any?) { state.blackout.toggle() }
    @objc private func toggleWhiteboard(_ sender: Any?) { state.toggleBoard() }
    @objc private func resetTimer(_ sender: Any?)     { state.resetTimer() }

    @objc private func saveWhiteboard(_ sender: Any?) {
        guard let board = state.activeBoard else { return }
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.pdf]
        panel.nameFieldStringValue = "\(board.name).pdf"
        panel.canCreateDirectories = true
        guard panel.runModal() == .OK, let url = panel.url else { return }
        if !BoardExporter.writePDF(board: board, aspect: state.slideAspect, to: url) {
            let alert = NSAlert()
            alert.messageText = "Could not save the whiteboard"
            alert.informativeText = url.lastPathComponent
            alert.runModal()
        }
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
    /// Modifier combos (⌘…) are left for the menu bar's key equivalents, and keys
    /// are ignored while a text field (e.g. a whiteboard item editor) is editing.
    private func handleKey(_ event: NSEvent) -> Bool {
        guard state.isLoaded else { return false }
        let modifiers: NSEvent.ModifierFlags = [.command, .control, .option]
        guard event.modifierFlags.isDisjoint(with: modifiers) else { return false }
        if NSApp.keyWindow?.firstResponder is NSTextView { return false }
        switch event.keyCode {
        case 124, 49, 121: state.next()              // → / space / page down
        case 123, 116:     state.previous()          // ← / page up
        case 115:          state.goToFirst()         // home
        case 119:          state.goToLast()          // end
        case 5:            state.showOverview.toggle()   // G
        case 11:           state.blackout.toggle()       // B
        case 15:           state.resetTimer()            // R
        case 13:           state.toggleBoard()           // W
        case 35:           state.toggleTool(.pen)        // P
        case 37:           state.toggleTool(.laser)      // L
        case 6:            state.undoStroke()            // Z
        case 8:            state.clearStrokes()          // C
        case 53:                                         // esc
            if state.selectedItemID != nil { state.selectedItemID = nil }
            else if state.tool != .none { state.tool = .none; state.laserPoint = nil }
            else if state.isBoardActive { state.hideBoard() }
            else if state.showOverview { state.showOverview = false }
            else { return false }
        default:           return false
        }
        return true
    }
}
