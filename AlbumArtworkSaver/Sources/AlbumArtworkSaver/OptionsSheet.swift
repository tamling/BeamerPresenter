import AppKit
import os

/// The screensaver's options, which System Settings shows as a sheet:
///
///     Musikordner:  [/Users/…/Musik (path, editable)]  [Ordner wählen…]
///                   1.234 Alben · zuletzt eingelesen …  [Jetzt neu einlesen]
///     Reihen:       [slider 3…12]                      6
///     Intervall:    [slider 1…10 s]                    3 s
///                                                              [Fertig]
///
/// A folder chosen in the open panel, or typed into the path field (Return
/// or "Fertig" takes it), is saved at once and scanned at once, so the status
/// line moves while the sheet is open. "Fertig" saves the rest, closes the
/// sheet and hands the settings to `onDone`.
final class OptionsSheet: NSWindowController {
    private static let pathWidth: CGFloat = 400

    private var settings: SaverSettings
    private let service: LibraryService?
    private let onDone: (SaverSettings) -> Void
    /// Whether the folder can be read; nil until it was first resolved.
    private var folder: FolderStatus?
    /// Counts requests to resolve the folder; only the latest one's result is used.
    private var resolution = 0
    /// The folder this sheet asked the service to scan, with the access
    /// `FolderAccess.resolve` started for it; let go once that scan is over.
    private var scanFolder: URL?
    /// Whether the scan of `scanFolder` has begun: until then it waits for the
    /// service's earlier scan to stop.
    private var scanBegun = false

    private let pathField: PathField
    private let chooseButton: NSButton
    private let statusLabel: NSTextField
    private let rescanButton: NSButton
    private let rowsSlider: NSSlider
    private let rowsValue: NSTextField
    private let intervalSlider: NSSlider
    private let intervalValue: NSTextField
    private let doneButton: NSButton

    init(settings: SaverSettings, service: LibraryService?, onDone: @escaping (SaverSettings) -> Void) {
        self.settings = settings
        self.service = service
        self.onDone = onDone
        pathField = PathField(string: settings.folderPath ?? "")
        chooseButton = NSButton(title: "Ordner wählen…", target: nil, action: nil)
        statusLabel = NSTextField(wrappingLabelWithString: "")
        rescanButton = NSButton(title: "Jetzt neu einlesen", target: nil, action: nil)
        rowsSlider = NSSlider(value: Double(settings.wall.rows), minValue: 3, maxValue: 12, target: nil, action: nil)
        rowsValue = NSTextField(labelWithString: "")
        intervalSlider = NSSlider(value: settings.wall.interval, minValue: 1, maxValue: 10, target: nil, action: nil)
        intervalValue = NSTextField(labelWithString: "")
        doneButton = NSButton(title: "Fertig", target: nil, action: nil)
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 640, height: 220), styleMask: [.titled],
                              backing: .buffered, defer: true)
        window.title = "AlbumArtwork"
        window.isReleasedWhenClosed = false
        super.init(window: window)
        buildContent(in: window)
        showWallSettings()
        // Only to tell the status line whether the folder can be read now.
        resolveFolder(then: .show)
        service?.addObserver(self) { [weak self] in self?.serviceChanged() }
        refreshStatus()
    }

    required init?(coder: NSCoder) {
        return nil
    }

    deinit {
        if let scanFolder { FolderAccess.stopAccessing(scanFolder) }
    }

    // MARK: - Actions

    @objc private func chooseFolder(_ sender: Any?) {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.canCreateDirectories = false
        if let path = settings.folderPath { panel.directoryURL = URL(fileURLWithPath: path, isDirectory: true) }
        Logger.scan.notice("folder: open panel shown")
        let response = panel.runModal()
        Logger.scan.notice("""
            folder: open panel closed (response \(response.rawValue, privacy: .public)) \
            with \(panel.url?.path ?? "nothing", privacy: .public)
            """)
        guard response == .OK, let url = panel.url else { return }
        choose(url)
    }

    @objc private func pathEntered(_ sender: Any?) {
        applyTypedPath()
    }

    @objc private func rescan(_ sender: Any?) {
        resolveFolder(then: .scan(cancellingRunning: false))
    }

    @objc private func rowsChanged(_ sender: NSSlider) {
        settings.wall = WallSettings(rows: sender.integerValue, interval: settings.wall.interval)
        showWallSettings()
    }

    @objc private func intervalChanged(_ sender: NSSlider) {
        settings.wall = WallSettings(rows: settings.wall.rows, interval: Double(sender.integerValue))
        showWallSettings()
    }

    @objc private func done(_ sender: Any?) {
        // Ends an edit of the path field, so its text is final.
        _ = window?.makeFirstResponder(nil)
        applyTypedPath()
        settings.save()
        if let window {
            if let parent = window.sheetParent { parent.endSheet(window) } else { window.close() }
        }
        onDone(settings)
    }

    // MARK: - The folder

    /// Takes the folder typed into the path field, if it is another one.
    private func applyTypedPath() {
        let typed = pathField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !typed.isEmpty else {
            pathField.stringValue = settings.folderPath ?? ""
            return
        }
        let url = URL(fileURLWithPath: Self.expandingTilde(typed), isDirectory: true).standardizedFileURL
        guard url.path != settings.folderPath else { return }
        Logger.scan.notice("folder: path typed: \(url.path, privacy: .public)")
        choose(url)
    }

    private func choose(_ url: URL) {
        FolderAccess.remember(url, in: &settings)
        settings.save()
        pathField.stringValue = settings.folderPath ?? ""
        // The earlier folder's scan makes way for this one.
        resolveFolder(then: .scan(cancellingRunning: true))
    }

    private enum AfterResolving {
        /// Only the status line.
        case show
        case scan(cancellingRunning: Bool)
    }

    /// Resolves the chosen folder in the background (a disk or share may be
    /// slow to answer), then shows whether it can be read and does `next`
    /// with it. The status line keeps its text until the result is in. A
    /// result for an earlier request, or for a sheet that is gone, is let go of.
    private func resolveFolder(then next: AfterResolving) {
        resolution += 1
        let request = resolution
        FolderAccess.resolve(settings) { [weak self] status, url in
            guard let self, self.resolution == request else {
                if let url { FolderAccess.stopAccessing(url) }
                return
            }
            self.folder = status
            // Resolving saves a stale bookmark anew; "Fertig" must not put the old one back.
            let saved = SaverSettings.load()
            if saved.folderBookmark != self.settings.folderBookmark || saved.folderPath != self.settings.folderPath {
                self.settings.folderBookmark = saved.folderBookmark
                self.settings.folderPath = saved.folderPath
                self.pathField.stringValue = self.settings.folderPath ?? ""
            }
            if let url {
                switch next {
                case .show: FolderAccess.stopAccessing(url)
                case let .scan(cancellingRunning): self.scan(url, cancellingRunning: cancellingRunning)
                }
            }
            self.refreshStatus()
        }
    }

    private func scan(_ url: URL, cancellingRunning: Bool) {
        releaseScanFolder()
        guard let service else {
            FolderAccess.stopAccessing(url)
            return
        }
        scanFolder = url
        if cancellingRunning { service.cancelScan() }
        advanceScan()
    }

    /// Starts the scan of `scanFolder` once the service is free, and lets go
    /// of the folder once that scan is over.
    private func advanceScan() {
        guard let service, scanFolder != nil, !service.isScanning else { return }
        if scanBegun {
            releaseScanFolder()
        } else if let root = scanFolder {
            scanBegun = true
            service.scan(root: root)
        }
    }

    private func releaseScanFolder() {
        if let scanFolder { FolderAccess.stopAccessing(scanFolder) }
        scanFolder = nil
        scanBegun = false
    }

    /// `~` is the user's home folder, not the sandbox container's.
    private static func expandingTilde(_ path: String) -> String {
        guard path == "~" || path.hasPrefix("~/"), let home = getpwuid(getuid())?.pointee.pw_dir else { return path }
        return String(cString: home) + path.dropFirst()
    }

    // MARK: - Showing

    private func serviceChanged() {
        advanceScan()
        refreshStatus()
    }

    private func refreshStatus() {
        guard let folder else {
            // Not resolved yet: no status to tell.
            statusLabel.stringValue = ""
            rescanButton.isEnabled = false
            return
        }
        let scanning = service?.isScanning ?? false
        statusLabel.stringValue = StatusText.make(albumCount: service?.albums.count ?? 0,
                                                  lastCompleteScan: service?.lastCompleteScan, now: Date(),
                                                  folder: folder, isScanning: scanning)
        rescanButton.isEnabled = service != nil && folder != .notChosen && !scanning
    }

    private func showWallSettings() {
        rowsSlider.integerValue = settings.wall.rows
        rowsValue.stringValue = "\(settings.wall.rows)"
        intervalSlider.doubleValue = settings.wall.interval
        intervalValue.stringValue = "\(Int(settings.wall.interval.rounded())) s"
    }

    private func buildContent(in window: NSWindow) {
        chooseButton.target = self
        chooseButton.action = #selector(chooseFolder(_:))
        pathField.target = self
        pathField.action = #selector(pathEntered(_:))
        pathField.lineBreakMode = .byTruncatingMiddle
        pathField.usesSingleLineMode = true
        pathField.cell?.wraps = false
        pathField.cell?.isScrollable = false
        rescanButton.target = self
        rescanButton.action = #selector(rescan(_:))
        statusLabel.textColor = .secondaryLabelColor
        statusLabel.preferredMaxLayoutWidth = Self.pathWidth
        statusLabel.maximumNumberOfLines = 2
        for (slider, ticks, action) in [(rowsSlider, 10, #selector(rowsChanged(_:))),
                                        (intervalSlider, 10, #selector(intervalChanged(_:)))] {
            slider.numberOfTickMarks = ticks
            slider.allowsTickMarkValuesOnly = true
            slider.isContinuous = true
            slider.target = self
            slider.action = action
        }
        for label in [rowsValue, intervalValue] {
            label.font = .monospacedDigitSystemFont(ofSize: NSFont.systemFontSize, weight: .regular)
        }
        doneButton.target = self
        doneButton.action = #selector(done(_:))
        doneButton.keyEquivalent = "\r"

        let grid = NSGridView(views: [
            [NSTextField(labelWithString: "Musikordner:"), pathField, chooseButton],
            [NSGridCell.emptyContentView, statusLabel, rescanButton],
            [NSTextField(labelWithString: "Reihen:"), rowsSlider, rowsValue],
            [NSTextField(labelWithString: "Intervall:"), intervalSlider, intervalValue],
        ])
        grid.translatesAutoresizingMaskIntoConstraints = false
        grid.rowSpacing = 12
        grid.columnSpacing = 8
        grid.rowAlignment = .firstBaseline
        grid.column(at: 0).xPlacement = .trailing
        grid.column(at: 1).xPlacement = .fill
        for row in 2...3 {
            grid.row(at: row).rowAlignment = .none
            grid.row(at: row).yPlacement = .center
        }
        doneButton.translatesAutoresizingMaskIntoConstraints = false

        let content = NSView()
        content.addSubview(grid)
        content.addSubview(doneButton)
        NSLayoutConstraint.activate([
            pathField.widthAnchor.constraint(equalToConstant: Self.pathWidth),
            grid.topAnchor.constraint(equalTo: content.topAnchor, constant: 20),
            grid.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 20),
            grid.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -20),
            doneButton.topAnchor.constraint(equalTo: grid.bottomAnchor, constant: 20),
            doneButton.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -20),
            doneButton.bottomAnchor.constraint(equalTo: content.bottomAnchor, constant: -20),
        ])
        window.contentView = content
        window.setContentSize(content.fittingSize)
    }
}

/// A path field that shortens a long path in the middle while it is shown,
/// and scrolls while it is edited.
private final class PathField: NSTextField {
    override func becomeFirstResponder() -> Bool {
        cell?.isScrollable = true
        return super.becomeFirstResponder()
    }

    override func textDidEndEditing(_ notification: Notification) {
        super.textDidEndEditing(notification)
        cell?.isScrollable = false
    }
}
