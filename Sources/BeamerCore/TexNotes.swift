import Foundation

/// Reads LaTeX Beamer `\note{...}` speaker notes straight from the `.tex` source
/// next to a presentation, so a *plain* single-screen PDF can still show notes in
/// the presenter view — no `show notes on second screen` recompile required.
///
/// Page ranges come from the Beamer `.nav` file when it sits beside the PDF
/// (exact and overlay-aware); otherwise each frame is assumed to be a single
/// page, in document order.
public enum TexNotes {
    /// Returns a page-index → note map for the PDF. It prefers a `.tex` with the
    /// same base name next to the PDF; if that is missing or carries no notes, it
    /// falls back to any other `.tex` in the same folder, using the first that has
    /// `\note{}` content. Returns an empty map when nothing usable is found.
    public static func load(forPDF pdfURL: URL, pageCount: Int) -> [Int: String] {
        for texURL in candidateTexURLs(for: pdfURL) {
            let notes = notes(fromTex: texURL, pageCount: pageCount)
            if !notes.isEmpty { return notes }
        }
        return [:]
    }

    /// `.tex` files worth trying, same-name first, then the rest of the folder
    /// in a stable alphabetical order.
    private static func candidateTexURLs(for pdfURL: URL) -> [URL] {
        let sameName = pdfURL.deletingPathExtension().appendingPathExtension("tex")
        let dir = pdfURL.deletingLastPathComponent()
        let others = (try? FileManager.default.contentsOfDirectory(
            at: dir, includingPropertiesForKeys: nil))?
            .filter { $0.pathExtension.lowercased() == "tex" && $0 != sameName }
            .sorted { $0.lastPathComponent < $1.lastPathComponent } ?? []
        return [sameName] + others
    }

    /// Parses one `.tex` file into a page-index → note map, using the sibling
    /// `.nav` (same base name) for exact page ranges when available.
    private static func notes(fromTex texURL: URL, pageCount: Int) -> [Int: String] {
        guard let source = readText(texURL) else { return [:] }

        let notes = framesWithNotes(in: source)        // frameIndex → cleaned note
        guard !notes.isEmpty else { return [:] }

        let navURL = texURL.deletingPathExtension().appendingPathExtension("nav")
        let ranges = readText(navURL).map(framePages) ?? []

        var byPage: [Int: String] = [:]
        for (frame, note) in notes {
            let pages: ClosedRange<Int>
            if frame < ranges.count {
                pages = ranges[frame]
            } else if ranges.isEmpty {
                pages = frame...frame              // one page per frame (0-based)
            } else {
                continue                           // nav present but frame unknown
            }
            for p in pages where p >= 0 && p < pageCount {
                byPage[p] = byPage[p].map { $0 + "\n\n" + note } ?? note
            }
        }
        return byPage
    }

    // MARK: - File reading

    /// Sources larger than this are skipped — no real deck needs more.
    private static let maxFileBytes = 5 * 1024 * 1024

    /// Reads `url` as text if it is (or links to) a regular file of at most
    /// `maxFileBytes`. Resource values describe a symlink itself and report 0
    /// for a FIFO, so the link is resolved and the type checked first; the read
    /// is bounded anyway, in case the file changes after the check.
    private static func readText(_ url: URL) -> String? {
        let resolved = url.resolvingSymlinksInPath()
        guard let values = try? resolved.resourceValues(forKeys: [.isRegularFileKey, .fileSizeKey]),
              values.isRegularFile == true,
              (values.fileSize ?? 0) <= maxFileBytes,
              let handle = try? FileHandle(forReadingFrom: resolved) else { return nil }
        defer { try? handle.close() }
        guard let data = try? handle.read(upToCount: maxFileBytes + 1),
              data.count <= maxFileBytes else { return nil }
        return String(data: data, encoding: .utf8) ?? String(data: data, encoding: .isoLatin1)
    }

    // MARK: - .nav parsing

    /// Each `\beamer@framepages {start}{end}` in the `.nav` file gives the 1-based
    /// page range of a frame, emitted once per frame in document order. Converted
    /// here to 0-based closed ranges.
    static func framePages(_ nav: String) -> [ClosedRange<Int>] {
        let pattern = #"\\beamer@framepages\s*\{(\d+)\}\{(\d+)\}"#
        guard let re = try? NSRegularExpression(pattern: pattern) else { return [] }
        let ns = nav as NSString
        var ranges: [ClosedRange<Int>] = []
        for m in re.matches(in: nav, range: NSRange(location: 0, length: ns.length)) {
            let a = Int(ns.substring(with: m.range(at: 1))) ?? 0
            let b = Int(ns.substring(with: m.range(at: 2))) ?? 0
            let lo = max(0, a - 1)
            let hi = max(lo, b - 1)
            ranges.append(lo...hi)
        }
        return ranges
    }

    // MARK: - .tex parsing

    /// Walks the (comment-stripped) source, counting frames and collecting the
    /// `\note{...}` bodies that belong to each one. An unterminated group ends
    /// the scan: everything after it is inside that group anyway, and rescanning
    /// to the end for every later `\note` would be quadratic.
    static func framesWithNotes(in rawSource: String) -> [Int: String] {
        let chars = Array(stripComments(rawSource))
        let n = chars.count
        var notes: [Int: String] = [:]
        var frame = -1            // index of the most recently opened frame
        var i = 0

        scan: while i < n {
            guard chars[i] == "\\" else { i += 1; continue }

            // Read the control-word name (letters/`@`) following the backslash.
            var j = i + 1
            while j < n, chars[j].isLetter || chars[j] == "@" { j += 1 }
            if j == i + 1 { i += 2; continue }            // control symbol (\%, \{, …)
            let name = String(chars[(i + 1)..<j])

            switch name {
            case "frame", "againframe":
                frame += 1
                i = j
            case "begin":
                let k = skipSpaces(chars, j)
                if let (env, after) = bracedGroup(chars, k) {
                    if env == "frame" { frame += 1 }
                    i = after                                    // never rescan the argument
                } else if k < n, chars[k] == "{" {
                    break scan                                   // unterminated \begin{
                } else {
                    i = j
                }
            case "note":
                var k = skipSpaces(chars, j)
                guard let afterOverlay = skipOptional(chars, k, open: "<", close: ">")  // \note<2>{…}
                else { break scan }                                 // unterminated \note<
                k = skipSpaces(chars, afterOverlay)
                guard let afterOption = skipOptional(chars, k, open: "[", close: "]")   // \note[item]{…}
                else { break scan }                                 // unterminated \note[
                k = skipSpaces(chars, afterOption)
                if let (body, after) = bracedGroup(chars, k) {
                    let text = cleanup(body)
                    if frame >= 0, !text.isEmpty {
                        notes[frame] = notes[frame].map { $0 + "\n\n" + text } ?? text
                    }
                    i = after
                } else if k < n, chars[k] == "{" {
                    break scan                                   // unterminated \note{
                } else {
                    i = max(j, k)                                // never rescan a <…>/[…] group
                }
            default:
                i = j
            }
        }
        return notes
    }

    static func skipSpaces(_ c: [Character], _ i: Int) -> Int {
        var i = i
        while i < c.count, c[i] == " " || c[i] == "\t" || c[i] == "\n" || c[i] == "\r" { i += 1 }
        return i
    }

    /// If `c[i]` opens an optional group, returns the index just past its close;
    /// otherwise returns `i` unchanged. `nil` when the group is never closed.
    static func skipOptional(_ c: [Character], _ i: Int, open: Character, close: Character) -> Int? {
        guard i < c.count, c[i] == open else { return i }
        var j = i + 1
        while j < c.count, c[j] != close { j += 1 }
        return j < c.count ? j + 1 : nil
    }

    /// Reads a balanced `{ … }` group starting at `c[i] == "{"`, honouring nested
    /// braces and `\{` / `\}` escapes. Returns the inner text and the index past
    /// the closing brace.
    static func bracedGroup(_ c: [Character], _ i: Int) -> (String, Int)? {
        guard i < c.count, c[i] == "{" else { return nil }
        var depth = 0
        var j = i
        let start = i + 1
        while j < c.count {
            let ch = c[j]
            if ch == "\\" { j += 2; continue }            // skip escaped char
            if ch == "{" { depth += 1 }
            else if ch == "}" {
                depth -= 1
                if depth == 0 { return (String(c[start..<j]), j + 1) }
            }
            j += 1
        }
        return nil
    }

    // MARK: - Comment & markup cleanup

    /// Drops everything after an unescaped `%` on each line.
    static func stripComments(_ s: String) -> String {
        var out = ""
        out.reserveCapacity(s.count)
        for line in s.split(separator: "\n", omittingEmptySubsequences: false) {
            var escaped = false
            for ch in line {
                if escaped { out.append(ch); escaped = false; continue }
                if ch == "\\" { out.append(ch); escaped = true; continue }
                if ch == "%" { break }
                out.append(ch)
            }
            out.append("\n")
        }
        return out
    }

    /// Best-effort conversion of a LaTeX note body to readable plain text.
    static func cleanup(_ tex: String) -> String {
        var s = tex

        // List markup → bullets / blank lines.
        s = regexReplace(s, #"\\(begin|end)\s*\{(itemize|enumerate|description)\}"#, "\n")
        s = s.replacingOccurrences(of: "\\item", with: "\n• ")
        s = s.replacingOccurrences(of: "\\par", with: "\n\n")
        s = s.replacingOccurrences(of: "\\\\", with: "\n")          // explicit line break

        // Common escaped specials.
        for (esc, plain) in [("\\&", "&"), ("\\%", "%"), ("\\_", "_"),
                             ("\\#", "#"), ("\\$", "$"), ("~", " ")] {
            s = s.replacingOccurrences(of: esc, with: plain)
        }

        // Unwrap simple `\cmd[..]{text}` to its argument (a few passes for nesting),
        // then drop any remaining bare commands and stray braces.
        for _ in 0..<3 {
            s = regexReplace(s, #"\\[a-zA-Z@]+\*?\s*(\[[^\]]*\])?\s*\{([^{}]*)\}"#, "$2")
        }
        s = regexReplace(s, #"\\[a-zA-Z@]+\*?"#, "")
        s = s.replacingOccurrences(of: "{", with: "")
        s = s.replacingOccurrences(of: "}", with: "")

        // Tidy whitespace.
        s = regexReplace(s, #"[ \t]+"#, " ")
        s = regexReplace(s, #"\n{3,}"#, "\n\n")
        return s.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    static func regexReplace(_ s: String, _ pattern: String, _ template: String) -> String {
        guard let re = try? NSRegularExpression(pattern: pattern) else { return s }
        let range = NSRange(location: 0, length: (s as NSString).length)
        return re.stringByReplacingMatches(in: s, range: range, withTemplate: template)
    }
}
