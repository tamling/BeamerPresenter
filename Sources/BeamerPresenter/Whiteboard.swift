import SwiftUI
import AppKit
import CoreImage

/// A free-form scratch slide shown over the deck: a white board with freehand ink
/// and movable items (a text box, a small table, or a QR code). Boards live
/// outside the PDF, so they can be added live during a talk — e.g. to work
/// through a calculation — and exported to their own file.
struct Whiteboard: Identifiable {
    let id = UUID()
    var name: String
    var strokes: [Stroke] = []
    var items: [BoardItem] = []
}

/// A single placeable element on a board. All geometry is in *unit* coordinates
/// (0…1 of the board) so it scales identically on the presenter pane, the
/// audience screen, and the exported file.
struct BoardItem: Identifiable {
    enum Kind: String { case text, table, qr }

    let id = UUID()
    var kind: Kind
    var center: CGPoint          // unit position of the item's centre
    var width: CGFloat           // unit width (fraction of board width)
    var text: String             // plain text, QR payload, or "a | b\nc | d" table
    var fontScale: CGFloat = 0.045   // font size as a fraction of board width

    static func makeDefault(_ kind: Kind) -> BoardItem {
        switch kind {
        case .text:  return BoardItem(kind: .text, center: CGPoint(x: 0.5, y: 0.4), width: 0.4, text: "Text")
        case .table: return BoardItem(kind: .table, center: CGPoint(x: 0.5, y: 0.4), width: 0.5, text: "a | b\nc | d")
        case .qr:    return BoardItem(kind: .qr, center: CGPoint(x: 0.5, y: 0.4), width: 0.2, text: "https://")
        }
    }
}

/// Generates a crisp QR code image from a string (used for links, contact info,
/// etc. dropped onto a board).
enum QRCode {
    static func image(from string: String) -> NSImage? {
        let trimmed = string.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty,
              let filter = CIFilter(name: "CIQRCodeGenerator") else { return nil }
        filter.setValue(Data(trimmed.utf8), forKey: "inputMessage")
        filter.setValue("M", forKey: "inputCorrectionLevel")
        guard let output = filter.outputImage else { return nil }
        let scaled = output.transformed(by: CGAffineTransform(scaleX: 12, y: 12))
        let rep = NSCIImageRep(ciImage: scaled)
        let image = NSImage(size: rep.size)
        image.addRepresentation(rep)
        return image
    }
}
