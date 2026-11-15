import Foundation

/// Reads PowerPoint speaker notes straight from the `.pptx` next to a
/// presentation (the file a converted PDF came from), so they show in the
/// presenter console even though LibreOffice's PDF carries only the slides.
///
/// A `.pptx` is a ZIP: slide order comes from `ppt/presentation.xml`
/// (`<p:sldIdLst>`), each slide's `_rels` file points to its notes page
/// (`ppt/notesSlides/notesSlideN.xml`), and the note text lives in that
/// page's body-placeholder shape.
enum PptxNotes {
    /// Returns a page-index → note map for the PDF: looks for a `.pptx` with
    /// the same base name next to it. Empty when there is none (or no notes).
    static func load(forPDF pdfURL: URL, pageCount: Int) -> [Int: String] {
        let pptx = pdfURL.deletingPathExtension().appendingPathExtension("pptx")
        guard FileManager.default.fileExists(atPath: pptx.path) else { return [:] }
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("pptx-notes-\(UUID().uuidString)")
        // Registered before extracting, so a run that fails part-way still cleans up.
        defer { try? FileManager.default.removeItem(at: dir) }
        guard unzip(pptx, to: dir) else { return [:] }

        // Slide order: r:id list in presentation.xml, resolved via its rels.
        guard let presentation = read(dir, "ppt/presentation.xml"),
              let presRels = read(dir, "ppt/_rels/presentation.xml.rels") else { return [:] }
        let relTargets = relationships(in: presRels)
        let slideFiles = matches(#"<p:sldId\b[^<>]*r:id="([^"]+)""#, in: presentation)
            .compactMap { relTargets[$0] }                       // e.g. "slides/slide1.xml"

        var byPage: [Int: String] = [:]
        for (index, slideFile) in slideFiles.enumerated() where index < pageCount {
            let name = (slideFile as NSString).lastPathComponent  // "slide1.xml"
            guard let slideRels = read(dir, "ppt/slides/_rels/\(name).rels") else { continue }
            guard let notesTarget = relationships(in: slideRels).values
                .first(where: { $0.contains("notesSlide") }) else { continue }
            let notesName = (notesTarget as NSString).lastPathComponent
            guard let notesXML = read(dir, "ppt/notesSlides/\(notesName)") else { continue }
            let text = notesText(in: notesXML)
            if !text.isEmpty { byPage[index] = text }
        }
        return byPage
    }

    // MARK: - Unzip

    /// Caps on an untrusted archive: `ulimit -f` blocks per extracted file (512 or
    /// 1024 bytes a block, depending on the shell) and bytes we will parse. Real
    /// notes parts are a few KB.
    private static let maxEntryBlocks = 8192
    private static let maxEntryBytes = 4 << 20

    /// Extracts the parts `load` reads to `dir` using the system unzip.
    private static func unzip(_ url: URL, to dir: URL) -> Bool {
        let process = Process()
        // `ulimit -f` bounds what a bomb can inflate onto the temp volume. The
        // arguments reach unzip positionally, so the shell expands none of them.
        process.executableURL = URL(fileURLWithPath: "/bin/sh")
        process.arguments = ["-c", "ulimit -f \"$1\" || exit 1; shift; exec /usr/bin/unzip \"$@\"",
                             "sh", String(maxEntryBlocks),
                             "-qq", "-o", url.path,
                             // Only what we read: never `ppt/media/*`.
                             "ppt/presentation.xml", "ppt/_rels/presentation.xml.rels",
                             "ppt/slides/_rels/*.rels", "ppt/notesSlides/*",
                             "-d", dir.path]
        // Nothing reads these, and a pipe the child fills would block it (and us)
        // forever; stdin would otherwise prompt for an encrypted archive's password.
        process.standardInput = FileHandle.nullDevice
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        do {
            try process.run()
            process.waitUntilExit()
        } catch { return false }
        // unzip exits 11 when one of the patterns matched nothing — normal for a deck
        // without notes — so the reads below decide, not the exit status.
        return true
    }

    private static func read(_ dir: URL, _ relative: String) -> String? {
        let url = dir.appendingPathComponent(relative)
        // Don't pull a hostile part into memory, and from there into the regexes.
        guard let size = try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize,
              size <= maxEntryBytes else { return nil }
        return try? String(contentsOf: url, encoding: .utf8)
    }

    // MARK: - OOXML parsing (regex-based, like the TexNotes reader)
    //
    // The scans stop at the next `<` or opening tag rather than running `.*?` or
    // `[^>]*` to the end of the part, so an archive full of unclosed tags cannot
    // make the matcher retry from every opening position.

    /// `Id → Target` for every `<Relationship …/>`, attribute order independent.
    private static func relationships(in xml: String) -> [String: String] {
        var map: [String: String] = [:]
        for element in matches(#"<Relationship\b[^<>]*>"#, in: xml, group: 0) {
            guard let id = matches(#"\bId="([^"]+)""#, in: element).first,
                  let target = matches(#"\bTarget="([^"]+)""#, in: element).first else { continue }
            map[id] = target
        }
        return map
    }

    /// The note text of a notes page: the `<p:sp>` shape whose placeholder is
    /// `type="body"`, paragraphs (`<a:p>`) joined by newlines, runs (`<a:t>`)
    /// concatenated, entities unescaped.
    private static func notesText(in xml: String) -> String {
        for shape in matches(#"<p:sp>(?:(?!<p:sp>).)*?</p:sp>"#, in: xml, group: 0) {
            guard shape.contains(#"type="body""#) else { continue }
            let paragraphs = matches(#"<a:p>(?:(?!<a:p>).)*?</a:p>"#, in: shape, group: 0).map { p in
                matches(#"<a:t>([^<]*)</a:t>"#, in: p).map(unescape).joined()
            }
            return paragraphs.joined(separator: "\n")
                .replacingOccurrences(of: "\u{2028}", with: "\n")
                .trimmingCharacters(in: .whitespacesAndNewlines)
        }
        return ""
    }

    private static func unescape(_ s: String) -> String {
        var out = s
        for (entity, plain) in [("&lt;", "<"), ("&gt;", ">"), ("&quot;", "\""),
                                ("&apos;", "'"), ("&amp;", "&")] {   // &amp; last
            out = out.replacingOccurrences(of: entity, with: plain)
        }
        return out
    }

    /// All matches of `pattern` (dot matches newlines), returning `group`.
    private static func matches(_ pattern: String, in s: String, group: Int = 1) -> [String] {
        guard let re = try? NSRegularExpression(
            pattern: pattern, options: [.dotMatchesLineSeparators]) else { return [] }
        let ns = s as NSString
        return re.matches(in: s, range: NSRange(location: 0, length: ns.length))
            .compactMap { m in
                m.range(at: group).location == NSNotFound
                    ? nil : ns.substring(with: m.range(at: group))
            }
    }
}
