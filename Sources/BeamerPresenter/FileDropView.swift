import AppKit

/// An AppKit-level drag-and-drop catcher wrapped around the presenter
/// window's SwiftUI content. It guarantees that a PDF/.tex/.pptx (or a
/// folder) can be dropped *anywhere* on the window — including over buttons,
/// lists, and the left column — regardless of how SwiftUI routes drops.
///
/// SwiftUI's own `.onDrop` (the home screen's highlighted drop zone) still
/// takes precedence where it is registered; this view only catches whatever
/// would otherwise fall through.
final class FileDropView: NSView {
    private let onOpen: (URL) -> Void
    private static let extensions = ["pdf", "tex", "pptx", "ppt", "odp"]

    init(onOpen: @escaping (URL) -> Void) {
        self.onOpen = onOpen
        super.init(frame: .zero)
        registerForDraggedTypes([.fileURL])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    /// Embeds the hosted SwiftUI view, pinned to all edges.
    func host(_ view: NSView) {
        view.translatesAutoresizingMaskIntoConstraints = false
        addSubview(view)
        NSLayoutConstraint.activate([
            view.leadingAnchor.constraint(equalTo: leadingAnchor),
            view.trailingAnchor.constraint(equalTo: trailingAnchor),
            view.topAnchor.constraint(equalTo: topAnchor),
            view.bottomAnchor.constraint(equalTo: bottomAnchor),
        ])
    }

    override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation {
        droppedURL(sender) != nil ? .copy : []
    }

    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        guard let url = droppedURL(sender) else { return false }
        onOpen(url)
        return true
    }

    /// The first openable file (or any folder, which becomes a favourite).
    private func droppedURL(_ info: NSDraggingInfo) -> URL? {
        let urls = info.draggingPasteboard.readObjects(
            forClasses: [NSURL.self],
            options: [.urlReadingFileURLsOnly: true]) as? [URL] ?? []
        return urls.first { url in
            var isDir: ObjCBool = false
            FileManager.default.fileExists(atPath: url.path, isDirectory: &isDir)
            return isDir.boolValue
                || Self.extensions.contains(url.pathExtension.lowercased())
        }
    }
}
