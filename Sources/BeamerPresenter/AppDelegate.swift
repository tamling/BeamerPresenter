import AppKit
import SwiftUI
import Combine
import UniformTypeIdentifiers

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate, NSMenuDelegate {
    let state = PresentationState()
    private var presenterWindow: NSWindow?
    private var audienceWindow: NSWindow?
    private var splashWindow: NSWindow?
    private var settingsWindow: NSWindow?
    private var statusItem: NSStatusItem?
    private weak var statusInfoItem: NSMenuItem?
    private var keyMonitor: Any?
    private var cancellables = Set<AnyCancellable>()

    func applicationDidFinishLaunching(_ notification: Notification) {
        setupMenu()
        installKeyMonitor()
        NotificationCenter.default.addObserver(
            self, selector: #selector(screensChanged),
            name: NSApplication.didChangeScreenParametersNotification, object: nil)
        NotificationCenter.default.addObserver(
            self, selector: #selector(updateStatusItem),
            name: .statusItemPrefChanged, object: nil)
        // Returning to the home screen (unload) hides the audience window.
        state.$isLoaded
            .dropFirst()
            .sink { [weak self] loaded in if !loaded { self?.audienceWindow?.orderOut(nil) } }
            .store(in: &cancellables)
        buildPresenterWindow()
        updateStatusItem()
        showSplash()
        NSApp.activate(ignoringOtherApps: true)
    }

    // MARK: - Menu bar status item

    /// Adds or removes the Time Machine-style menu bar icon based on the setting.
    @objc private func updateStatusItem() {
        let show = UserDefaults.standard.object(forKey: Prefs.showStatusItem) as? Bool ?? true
        if show {
            guard statusItem == nil else { return }
            let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
            item.button?.image = NSImage(systemSymbolName: "rectangle.on.rectangle.angled",
                                         accessibilityDescription: AppInfo.name)
            item.menu = buildStatusMenu()
            statusItem = item
        } else if let item = statusItem {
            NSStatusBar.system.removeStatusItem(item)
            statusItem = nil
        }
    }

    private func buildStatusMenu() -> NSMenu {
        let menu = NSMenu()
        menu.delegate = self
        let info = menu.addItem(withTitle: AppInfo.name, action: nil, keyEquivalent: "")
        info.isEnabled = false
        statusInfoItem = info
        menu.addItem(.separator())
        add(to: menu, "Open…", #selector(openDocument(_:)))
        add(to: menu, "Show Presenter Window", #selector(showPresenter(_:)))
        menu.addItem(.separator())
        add(to: menu, "Next Slide", #selector(nextSlide(_:)))
        add(to: menu, "Previous Slide", #selector(previousSlide(_:)))
        add(to: menu, "Black Out Audience", #selector(toggleBlackout(_:)))
        add(to: menu, "Toggle Whiteboard", #selector(toggleWhiteboard(_:)))
        menu.addItem(.separator())
        add(to: menu, "Settings…", #selector(showSettings(_:)))
        menu.addItem(withTitle: "Quit \(AppInfo.name)",
                     action: #selector(NSApplication.terminate(_:)), keyEquivalent: "")
        return menu
    }

    /// Keeps the status menu's header line in sync when it opens.
    func menuNeedsUpdate(_ menu: NSMenu) {
        guard menu === statusItem?.menu else { return }
        statusInfoItem?.title = state.isLoaded
            ? "\(state.title) — \(state.index + 1)/\(state.pageCount)"
            : "No presentation open"
    }

    @objc private func showPresenter(_ sender: Any?) {
        presenterWindow?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    // MARK: - Launch splash

    /// Shows a brief launch splash with the icon and version, then fades it out
    /// and brings the presenter window forward.
    private func showSplash() {
        let splash = SplashView(icon: NSApp.applicationIconImage, version: AppInfo.versionLine)
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 440, height: 280),
                              styleMask: [.borderless], backing: .buffered, defer: false)
        window.isOpaque = false
        window.backgroundColor = .clear
        window.hasShadow = true
        window.level = .floating
        window.isMovableByWindowBackground = true
        window.contentView = NSHostingView(rootView: splash)
        window.center()
        window.orderFrontRegardless()
        splashWindow = window

        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 1_600_000_000)
            guard let window = splashWindow else { return }
            window.animator().alphaValue = 0
            presenterWindow?.makeKeyAndOrderFront(nil)   // reveal home screen behind the fade
            try? await Task.sleep(nanoseconds: 400_000_000)
            window.orderOut(nil)
            splashWindow = nil
        }
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }

    func applicationWillTerminate(_ notification: Notification) {
        state.recordCurrentSession()
        state.saveScratch()
    }

    /// Closing the presenter window also closes the audience window (so the app
    /// can quit cleanly and the projector view doesn't linger).
    func windowWillClose(_ notification: Notification) {
        guard notification.object as? NSWindow === presenterWindow else { return }
        audienceWindow?.close()
        audienceWindow = nil
    }

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
        add(to: appMenu, "Settings…", #selector(showSettings(_:)), ",")
        appMenu.addItem(.separator())
        appMenu.addItem(withTitle: "Hide \(AppInfo.name)",
                        action: #selector(NSApplication.hide(_:)), keyEquivalent: "h")
        appMenu.addItem(withTitle: "Quit \(AppInfo.name)",
                        action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")

        // File menu — open, favourites, close.
        let fileMenu = addSubmenu(to: mainMenu, "File")
        add(to: fileMenu, "Open…", #selector(openDocument(_:)), "o")
        add(to: fileMenu, "Add Folder to Favorites…", #selector(addFavoriteFolder(_:)), "d")
        fileMenu.addItem(.separator())
        add(to: fileMenu, "Save Notes…", #selector(saveNotes(_:)))
        add(to: fileMenu, "Close Presentation", #selector(closePresentation(_:)), "w")

        // Presentation menu — navigation + audience controls.
        let presoMenu = addSubmenu(to: mainMenu, "Presentation")
        add(to: presoMenu, "Next Slide", #selector(nextSlide(_:)), "]")
        add(to: presoMenu, "Previous Slide", #selector(previousSlide(_:)), "[")
        add(to: presoMenu, "First Slide", #selector(firstSlide(_:)))
        add(to: presoMenu, "Last Slide", #selector(lastSlide(_:)))
        presoMenu.addItem(.separator())
        add(to: presoMenu, "Toggle Overview", #selector(toggleOverview(_:)), "1")
        add(to: presoMenu, "Black Out Audience", #selector(toggleBlackout(_:)), "b")

        let blackMenu = addSubmenu(to: presoMenu, "Black Screen")
        for preset in BlackScreen.presets {
            add(to: blackMenu, preset, #selector(setMessagePreset(_:))).representedObject = preset
        }
        blackMenu.addItem(.separator())
        add(to: blackMenu, "Custom Message…", #selector(setBlackScreenMessage(_:)))
        add(to: blackMenu, "Clear Message", #selector(clearBlackMessage(_:)))
        blackMenu.addItem(.separator())
        add(to: blackMenu, "Choose Background Image…", #selector(chooseBlackImage(_:)))
        add(to: blackMenu, "Clear Background Image", #selector(clearBlackImage(_:)))

        presoMenu.addItem(.separator())
        add(to: presoMenu, "Start / Stop Timer", #selector(toggleTimer(_:)), "t")
        add(to: presoMenu, "Reset Timer", #selector(resetTimer(_:)), "r")

        // Tools menu — pen / laser / colours / ink.
        let toolsMenu = addSubmenu(to: mainMenu, "Tools")
        add(to: toolsMenu, "Pen", #selector(togglePen(_:)), "p")
        add(to: toolsMenu, "Laser Pointer", #selector(toggleLaser(_:)), "l")
        toolsMenu.addItem(.separator())
        for (name, color) in PenPalette.colors {
            let item = add(to: toolsMenu, "Pen Colour: \(name)", #selector(setPenColor(_:)))
            item.representedObject = color
        }
        toolsMenu.addItem(.separator())
        add(to: toolsMenu, "Undo Stroke", #selector(undoInk(_:)), "z")
        add(to: toolsMenu, "Clear Ink", #selector(clearInk(_:)))

        // Whiteboard menu — boards, items, and export.
        let boardMenu = addSubmenu(to: mainMenu, "Whiteboard")
        add(to: boardMenu, "Toggle Whiteboard", #selector(toggleWhiteboard(_:)))
        add(to: boardMenu, "New Whiteboard", #selector(newBoard(_:)))
        add(to: boardMenu, "Next Board", #selector(nextBoard(_:)))
        add(to: boardMenu, "Previous Board", #selector(previousBoard(_:)))
        add(to: boardMenu, "Delete Board", #selector(deleteBoard(_:)))
        boardMenu.addItem(.separator())
        add(to: boardMenu, "Add Text", #selector(addText(_:)))
        add(to: boardMenu, "Add Table", #selector(addTable(_:)))
        add(to: boardMenu, "Add QR Code", #selector(addQR(_:)))
        boardMenu.addItem(.separator())
        add(to: boardMenu, "Save Whiteboard as PDF…", #selector(saveWhiteboard(_:)), "s")
        add(to: boardMenu, "Insert into PDF (Copy)…", #selector(insertWhiteboard(_:)), "i")

        NSApp.mainMenu = mainMenu
    }

    private func addSubmenu(to mainMenu: NSMenu, _ title: String) -> NSMenu {
        let item = NSMenuItem()
        item.title = title          // shown for nested items (top-level uses the submenu title)
        mainMenu.addItem(item)
        let menu = NSMenu(title: title)
        item.submenu = menu
        return menu
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

    /// Enables/disables deck- and board-dependent commands and shows checkmarks
    /// for the current tool, colour, and toggles.
    func validateMenuItem(_ item: NSMenuItem) -> Bool {
        switch item.action {
        case #selector(closePresentation(_:)), #selector(nextSlide(_:)),
             #selector(previousSlide(_:)), #selector(firstSlide(_:)),
             #selector(lastSlide(_:)), #selector(resetTimer(_:)),
             #selector(toggleTimer(_:)),
             #selector(toggleLaser(_:)), #selector(newBoard(_:)),
             #selector(saveNotes(_:)):
            return state.isLoaded

        case #selector(toggleOverview(_:)):
            item.state = state.showOverview ? .on : .off
            return state.isLoaded
        case #selector(toggleBlackout(_:)):
            item.state = state.blackout ? .on : .off
            return state.isLoaded
        case #selector(toggleWhiteboard(_:)):
            item.state = state.isBoardActive ? .on : .off
            return state.isLoaded
        case #selector(togglePen(_:)):
            item.state = state.tool == .pen ? .on : .off
            return state.isLoaded
        case #selector(setPenColor(_:)):
            item.state = (item.representedObject as? Color) == state.penColor ? .on : .off
            return state.isLoaded
        case #selector(undoInk(_:)), #selector(clearInk(_:)):
            return state.isLoaded && state.hasInkOnCurrentSlide

        case #selector(nextBoard(_:)), #selector(previousBoard(_:)),
             #selector(deleteBoard(_:)), #selector(addText(_:)),
             #selector(addTable(_:)), #selector(addQR(_:)),
             #selector(saveWhiteboard(_:)), #selector(insertWhiteboard(_:)):
            return state.isBoardActive

        default:
            return true
        }
    }

    @objc private func showAbout(_ sender: Any?) {
        let credits = "Present LaTeX Beamer PDFs with speaker notes.\n\n"
            + "By \(AppInfo.author)   ·   \(AppInfo.copyright)"
        NSApp.orderFrontStandardAboutPanel(options: [
            .applicationName: AppInfo.name,
            .applicationVersion: AppInfo.versionLine,
            .credits: NSAttributedString(
                string: credits,
                attributes: [.font: NSFont.systemFont(ofSize: 11),
                             .paragraphStyle: { let p = NSMutableParagraphStyle(); p.alignment = .center; return p }()])
        ])
        NSApp.activate(ignoringOtherApps: true)
    }

    @objc private func showSettings(_ sender: Any?) {
        if settingsWindow == nil {
            let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 480, height: 340),
                                  styleMask: [.titled, .closable], backing: .buffered, defer: false)
            window.title = "Settings"
            window.contentView = NSHostingView(rootView: SettingsView())
            window.isReleasedWhenClosed = false
            window.center()
            settingsWindow = window
        }
        settingsWindow?.makeKeyAndOrderFront(nil)
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

    @objc private func saveNotes(_ sender: Any?) {
        guard state.isLoaded else { return }
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.plainText]
        panel.nameFieldStringValue = "\(state.title.isEmpty ? "notes" : state.title) notes.txt"
        panel.canCreateDirectories = true
        guard panel.runModal() == .OK, let url = panel.url else { return }
        if (try? state.scratch.write(to: url, atomically: true, encoding: .utf8)) == nil {
            let alert = NSAlert()
            alert.messageText = "Could not save the notes"
            alert.informativeText = url.lastPathComponent
            alert.runModal()
        }
    }

    @objc private func nextSlide(_ sender: Any?)      { state.next() }
    @objc private func previousSlide(_ sender: Any?)  { state.previous() }
    @objc private func firstSlide(_ sender: Any?)     { state.goToFirst() }
    @objc private func lastSlide(_ sender: Any?)      { state.goToLast() }
    @objc private func toggleOverview(_ sender: Any?) { state.showOverview.toggle() }
    @objc private func toggleBlackout(_ sender: Any?) { state.blackout.toggle() }
    @objc private func resetTimer(_ sender: Any?)     { state.resetTimer() }
    @objc private func toggleTimer(_ sender: Any?)    { state.toggleTimer() }

    @objc private func setBlackScreenMessage(_ sender: Any?) {
        let alert = NSAlert()
        alert.messageText = "Black-Screen Message"
        alert.informativeText = "Shown centered on the blacked-out audience screen "
            + "(the clock stays, smaller, beneath it)."
        alert.addButton(withTitle: "Save")
        alert.addButton(withTitle: "Clear")
        alert.addButton(withTitle: "Cancel")
        let field = NSTextField(frame: NSRect(x: 0, y: 0, width: 300, height: 24))
        field.stringValue = UserDefaults.standard.string(forKey: Prefs.blackScreenMessage) ?? ""
        field.placeholderString = "e.g. Back in 5 minutes"
        alert.accessoryView = field
        switch alert.runModal() {
        case .alertFirstButtonReturn:
            UserDefaults.standard.set(field.stringValue, forKey: Prefs.blackScreenMessage)
        case .alertSecondButtonReturn:
            UserDefaults.standard.set("", forKey: Prefs.blackScreenMessage)
        default:
            break
        }
    }

    @objc private func setMessagePreset(_ sender: NSMenuItem) {
        UserDefaults.standard.set(sender.representedObject as? String ?? "", forKey: Prefs.blackScreenMessage)
    }

    @objc private func clearBlackMessage(_ sender: Any?) {
        UserDefaults.standard.set("", forKey: Prefs.blackScreenMessage)
    }

    @objc private func chooseBlackImage(_ sender: Any?) {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.image]
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.prompt = "Choose"
        if panel.runModal() == .OK, let url = panel.url {
            UserDefaults.standard.set(url.path, forKey: Prefs.blackScreenImage)
        }
    }

    @objc private func clearBlackImage(_ sender: Any?) {
        UserDefaults.standard.set("", forKey: Prefs.blackScreenImage)
    }

    // Tools
    @objc private func togglePen(_ sender: Any?)      { state.toggleTool(.pen) }
    @objc private func toggleLaser(_ sender: Any?)    { state.toggleTool(.laser) }
    @objc private func undoInk(_ sender: Any?)        { state.undoStroke() }
    @objc private func clearInk(_ sender: Any?)       { state.clearStrokes() }
    @objc private func setPenColor(_ sender: NSMenuItem) {
        guard let color = sender.representedObject as? Color else { return }
        state.penColor = color
        if state.tool == .none { state.tool = .pen }   // keep the laser if it's active
    }

    // Whiteboard
    @objc private func toggleWhiteboard(_ sender: Any?) { state.toggleBoard() }
    @objc private func newBoard(_ sender: Any?)       { state.addBoard() }
    @objc private func nextBoard(_ sender: Any?)      { state.nextBoard() }
    @objc private func previousBoard(_ sender: Any?)  { state.previousBoard() }
    @objc private func deleteBoard(_ sender: Any?)    { state.deleteActiveBoard() }
    @objc private func addText(_ sender: Any?)        { state.addItem(.text) }
    @objc private func addTable(_ sender: Any?)       { state.addItem(.table) }
    @objc private func addQR(_ sender: Any?)          { state.addItem(.qr) }

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

    @objc private func insertWhiteboard(_ sender: Any?) {
        guard let board = state.activeBoard, let source = state.sourceURL else { return }
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.pdf]
        panel.nameFieldStringValue = "\(state.title) + \(board.name).pdf"
        panel.canCreateDirectories = true
        guard panel.runModal() == .OK, let dest = panel.url else { return }
        if !BoardExporter.insertIntoCopy(of: source, board: board, afterIndex: state.index,
                                         aspect: state.slideAspect, to: dest) {
            let alert = NSAlert()
            alert.messageText = "Could not insert the whiteboard into the PDF"
            alert.informativeText = dest.lastPathComponent
            alert.runModal()
        }
    }

    @objc func openDocument(_ sender: Any?) {
        let panel = NSOpenPanel()
        panel.message = "Choose a PDF — or its .tex source, and the matching PDF is opened."
        panel.allowedContentTypes = [.pdf, UTType(filenameExtension: "tex") ?? .plainText]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        guard panel.runModal() == .OK, let url = panel.url else { return }
        load(url: url)
    }

    /// Maps a picked file to the PDF to present: a `.pdf` is used directly; a
    /// `.tex` resolves to the same-named `.pdf` next to it.
    private func resolvedPDF(for url: URL) -> URL? {
        if url.pathExtension.lowercased() == "tex" {
            let pdf = url.deletingPathExtension().appendingPathExtension("pdf")
            return FileManager.default.fileExists(atPath: pdf.path) ? pdf : nil
        }
        return url
    }

    private func load(url rawURL: URL) {
        guard let url = resolvedPDF(for: rawURL) else {
            let alert = NSAlert()
            alert.messageText = "No PDF found for this .tex"
            alert.informativeText = "Compile \(rawURL.lastPathComponent) first, or keep "
                + "\(rawURL.deletingPathExtension().lastPathComponent).pdf next to it."
            alert.runModal()
            return
        }
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
        presenter.isReleasedWhenClosed = false   // we hold a strong ref; avoid an ARC over-release crash
        presenter.contentView = NSHostingView(rootView: root)
        presenter.contentMinSize = NSSize(width: 560, height: 380)   // allow shrinking
        presenter.delegate = self
        presenter.center()
        // Stays hidden behind the launch splash; shown once the splash fades.
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
        audience.isReleasedWhenClosed = false   // held in a strong ref; avoid an ARC over-release crash
        audience.contentMinSize = NSSize(width: 320, height: 200)   // freely resizable on a single screen
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

        // While typing in a text field (e.g. the scratch notes), still let the
        // arrow / page keys drive the slides; everything else edits the text.
        if NSApp.keyWindow?.firstResponder is NSTextView {
            switch event.keyCode {
            case 124, 121: state.next()       // → / page down
            case 123, 116: state.previous()   // ← / page up
            default:       return false
            }
            return true
        }

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

extension Notification.Name {
    /// Posted by Settings when the "show menu bar icon" preference changes.
    static let statusItemPrefChanged = Notification.Name("statusItemPrefChanged")
}
