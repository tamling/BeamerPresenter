import Foundation

/// Reads LaTeX Beamer `\note{...}` speaker notes straight from the `.tex` source
/// next to a presentation, so a *plain* single-screen PDF can still show notes in
/// the presenter view — no `show notes on second screen` recompile required.
///
/// Page ranges come from the Beamer `.nav` file when it sits beside the PDF
/// (exact and overlay-aware); otherwise each frame is assumed to be a single
/// page, in document order.
enum TexNotes {
    /// Returns a page-index → note map for the PDF, read from the `.tex` with the
    /// same base name next to it. Only that file is used: an unrelated `.tex`
    /// sitting in the same folder must not supply another deck's notes. Returns
    /// an empty map when nothing usable is found.
    static func load(forPDF pdfURL: URL, pageCount: Int) -> [Int: String] {
        let texURL = pdfURL.deletingPathExtension().appendingPathExtension("tex")
        return notes(fromTex: texURL, pageCount: pageCount)
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
            // Clamp before iterating: a crafted `.nav` range is otherwise walked
            // one page at a time, with the filter bounding the body, not the loop.
            let lo = max(0, pages.lowerBound)
            let hi = min(pages.upperBound, pageCount - 1)
            guard lo <= hi else { continue }
            for p in lo...hi {
                byPage[p] = byPage[p].map { $0 + "\n\n" + note } ?? note
            }
        }
        return byPage
    }

    // MARK: - File reading

    /// A `.tex`/`.nav` beside a deck is a few hundred KB at most in practice.
    /// Anything far larger is refused, so a padded sibling file cannot stall the
    /// open path or exhaust memory (the parse costs ~16 bytes per source byte).
    private static let maxTextBytes = 4 << 20

    private static func readText(_ url: URL) -> String? {
        guard let size = try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize,
              size <= maxTextBytes else { return nil }
        guard let data = try? Data(contentsOf: url) else { return nil }
        return String(data: data, encoding: .utf8) ?? String(data: data, encoding: .isoLatin1)
    }

    // MARK: - .nav parsing

    /// Each `\beamer@framepages {start}{end}` in the `.nav` file gives the 1-based
    /// page range of a frame, emitted once per frame in document order. Converted
    /// here to 0-based closed ranges.
    private static func framePages(_ nav: String) -> [ClosedRange<Int>] {
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
    /// `\note{...}` bodies that belong to each one.
    private static func framesWithNotes(in rawSource: String) -> [Int: String] {
        let chars = Array(stripComments(rawSource))
        let n = chars.count
        var notes: [Int: String] = [:]
        var frame = -1            // index of the most recently opened frame
        var i = 0
        // An unterminated `{` makes `bracedGroup` walk to the end of the source,
        // so a file full of `\note{` would cost O(n²). Group scanning draws on a
        // budget a well-formed source never comes close to exhausting.
        var scanBudget = 8 * n + (1 << 20)

        while i < n {
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
                if let (env, after) = bracedGroup(chars, skipSpaces(chars, j), &scanBudget), env == "frame" {
                    frame += 1
                    i = after
                } else {
                    i = j
                }
            case "note":
                var k = skipSpaces(chars, j)
                k = skipOptional(chars, k, open: "<", close: ">")   // \note<2>{…}
                k = skipSpaces(chars, k)
                k = skipOptional(chars, k, open: "[", close: "]")   // \note[item]{…}
                k = skipSpaces(chars, k)
                if let (body, after) = bracedGroup(chars, k, &scanBudget) {
                    let text = cleanup(body)
                    if frame >= 0, !text.isEmpty {
                        notes[frame] = notes[frame].map { $0 + "\n\n" + text } ?? text
                    }
                    i = after
                } else {
                    i = j
                }
            default:
                i = j
            }
        }
        return notes
    }

    private static func skipSpaces(_ c: [Character], _ i: Int) -> Int {
        var i = i
        while i < c.count, c[i] == " " || c[i] == "\t" || c[i] == "\n" || c[i] == "\r" { i += 1 }
        return i
    }

    /// Overlay specs and `\note[item]` labels are short, so a longer "optional
    /// group" is malformed and not worth scanning for.
    private static let maxOptionalGroup = 1024

    /// If `c[i]` opens an optional group, returns the index just past its close;
    /// otherwise returns `i` unchanged. The scan is bounded, so an unterminated
    /// group costs a constant rather than a pass over the rest of the source.
    private static func skipOptional(_ c: [Character], _ i: Int, open: Character, close: Character) -> Int {
        guard i < c.count, c[i] == open else { return i }
        var j = i + 1
        let limit = min(c.count, i + 1 + maxOptionalGroup)
        while j < limit, c[j] != close { j += 1 }
        return j < limit ? j + 1 : i
    }

    /// Reads a balanced `{ … }` group starting at `c[i] == "{"`, honouring nested
    /// braces and `\{` / `\}` escapes. Returns the inner text and the index past
    /// the closing brace. Scanning is charged to `budget`, so unterminated groups
    /// cannot add up to a quadratic walk of the source.
    private static func bracedGroup(_ c: [Character], _ i: Int, _ budget: inout Int) -> (String, Int)? {
        guard i < c.count, c[i] == "{" else { return nil }
        var depth = 0
        var j = i
        let start = i + 1
        while j < c.count, budget > 0 {
            let ch = c[j]
            if ch == "\\" { j += 2; budget -= 2; continue }  // skip escaped char
            if ch == "{" { depth += 1 }
            else if ch == "}" {
                depth -= 1
                if depth == 0 { return (String(c[start..<j]), j + 1) }
            }
            j += 1
            budget -= 1
        }
        return nil
    }

    // MARK: - Comment & markup cleanup

    /// Drops everything after an unescaped `%` on each line.
    private static func stripComments(_ s: String) -> String {
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
    private static func cleanup(_ tex: String) -> String {
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
        // then drop any remaining bare commands and stray braces. The optional
        // argument is tied to its own `[` and bounded in length, so the two
        // whitespace runs cannot trade characters and `[^\]]` cannot swallow the
        // rest of the body — either would make a pass quadratic.
        for _ in 0..<3 {
            s = regexReplace(s, #"\\[a-zA-Z@]+\*?\s*(?:(\[[^\]]{0,200}\])\s*)?\{([^{}]*)\}"#, "$2")
        }
        s = regexReplace(s, #"\\[a-zA-Z@]+\*?"#, "")
        s = s.replacingOccurrences(of: "{", with: "")
        s = s.replacingOccurrences(of: "}", with: "")

        // Tidy whitespace.
        s = regexReplace(s, #"[ \t]+"#, " ")
        s = regexReplace(s, #"\n{3,}"#, "\n\n")
        return s.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func regexReplace(_ s: String, _ pattern: String, _ template: String) -> String {
        guard let re = try? NSRegularExpression(pattern: pattern) else { return s }
        let range = NSRange(location: 0, length: (s as NSString).length)
        return re.stringByReplacingMatches(in: s, range: range, withTemplate: template)
    }
}
