import Foundation
import PDFKit

/// Finds the "translated twin" of a deck: the same talk compiled in another
/// language, lying next to the primary PDF with a language-suffixed name —
/// e.g. `talk-no.pdf` ↔ `talk-en.pdf`, `talk_en.pdf`, `talk.en.pdf`, or
/// `talk.pdf` ↔ `talk-en.pdf`. A candidate only counts when its page count
/// matches, so the two decks stay in sync slide by slide.
enum ReferenceDeck {
    /// Recognised language suffixes ("en" is tried first — the common case of
    /// presenting a localized deck while reading the English one).
    static let codes = ["en", "de", "no", "nb", "nn", "da", "sv", "fi",
                        "fr", "es", "it", "nl", "pl"]
    private static let separators = ["-", "_", "."]

    /// The twin PDF for `pdfURL` (same folder, language-suffixed sibling with
    /// an equal page count), or nil.
    static func autoDetect(for pdfURL: URL, pageCount: Int) -> URL? {
        let dir = pdfURL.deletingLastPathComponent()
        let stem = pdfURL.deletingPathExtension().lastPathComponent

        // Strip the primary deck's own language suffix, if it has one.
        var base = stem
        var ownCode: String?
        outer: for sep in separators {
            for code in codes where stem.lowercased().hasSuffix(sep + code) {
                base = String(stem.dropLast(code.count + sep.count))
                ownCode = code
                break outer
            }
        }

        let ordered = (["en"] + codes.filter { $0 != "en" }).filter { $0 != ownCode }
        for code in ordered {
            for sep in separators {
                let url = dir.appendingPathComponent(base + sep + code)
                    .appendingPathExtension("pdf")
                guard url.path != pdfURL.path,
                      FileManager.default.fileExists(atPath: url.path),
                      let doc = PDFDocument(url: url),
                      doc.pageCount == pageCount else { continue }
                return url
            }
        }
        return nil
    }
}
