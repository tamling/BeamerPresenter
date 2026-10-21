import SwiftUI

// MARK: - Speaker-notes highlighting
// Notes from `\note{…}` are plain text. Writers often use Markdown habits in
// them (`# heading`, `- item`, `**bold**`, `*italic*`, `` `code` ``,
// `> question`, `[text](url)`), so we highlight those the way a code editor
// does: the markup characters stay visible in the note colour, the content
// gets its weight/style. Everything else renders as plain text.

enum NotesMarkup {
    static func attributed(_ text: String, size: CGFloat) -> AttributedString {
        var out = AttributedString()
        let lines = text.components(separatedBy: "\n")
        for (n, line) in lines.enumerated() {
            out += lineRun(line, size: size)
            if n < lines.count - 1 { out += plain("\n", size: size) }
        }
        return out
    }

    // MARK: Block level

    private static func lineRun(_ line: String, size: CGFloat) -> AttributedString {
        let trimmed = line.drop(while: { $0 == " " })
        let indent = String(line.prefix(line.count - trimmed.count))

        // # Heading (1–6 hashes + space)
        let hashes = trimmed.prefix(while: { $0 == "#" })
        if (1...6).contains(hashes.count), trimmed.dropFirst(hashes.count).first == " " {
            var run = plain(indent, size: size)
            run += markup(String(hashes) + " ", size: size, bold: true)
            var title = AttributedString(String(trimmed.dropFirst(hashes.count + 1)))
            title.swiftUI.font = .mono(size, bold: true)
            title.swiftUI.foregroundColor = Theme.noteMarkup
            run += title
            return run
        }

        // --- rule
        if trimmed.count >= 3, trimmed.allSatisfy({ $0 == "-" }) {
            return plain(indent, size: size) + markup(String(trimmed), size: size)
        }

        // > quote
        if trimmed.hasPrefix("> ") {
            var run = plain(indent, size: size) + markup("> ", size: size)
            var body = inline(String(trimmed.dropFirst(2)), size: size)
            body.swiftUI.foregroundColor = Theme.textSecondary
            body.swiftUI.font = .mono(size).italic()
            run += body
            return run
        }

        // - item, * item, + item, • item, 1. item
        for bullet in ["- ", "* ", "+ ", "• "] where trimmed.hasPrefix(bullet) {
            return plain(indent, size: size) + markup(bullet, size: size)
                + inline(String(trimmed.dropFirst(bullet.count)), size: size)
        }
        let digits = trimmed.prefix(while: { $0.isNumber })
        if !digits.isEmpty, trimmed.dropFirst(digits.count).hasPrefix(". ") {
            return plain(indent, size: size) + markup(String(digits) + ". ", size: size)
                + inline(String(trimmed.dropFirst(digits.count + 2)), size: size)
        }

        return inline(line, size: size)
    }

    // MARK: Inline

    private static func inline(_ s: String, size: CGFloat) -> AttributedString {
        let c = Array(s)
        var out = AttributedString()
        var buffer = ""
        var i = 0

        func flush() {
            if !buffer.isEmpty { out += plain(buffer, size: size); buffer = "" }
        }

        while i < c.count {
            // **bold**
            if c[i] == "*", i + 1 < c.count, c[i + 1] == "*",
               let end = find(c, ["*", "*"], from: i + 2), end > i + 2 {
                flush()
                out += markup("**", size: size)
                var body = AttributedString(String(c[(i + 2)..<end]))
                body.swiftUI.font = .mono(size, bold: true)
                body.swiftUI.foregroundColor = Theme.textPrimary
                out += body
                out += markup("**", size: size)
                i = end + 2
                continue
            }
            // *italic* / _italic_ (not inside a word, so snake_case stays plain)
            if c[i] == "*" || c[i] == "_",
               i == 0 || !(c[i - 1].isLetter || c[i - 1].isNumber),
               i + 1 < c.count, c[i + 1] != " ",
               let end = find(c, [c[i]], from: i + 1), end > i + 1 {
                flush()
                let mark = String(c[i])
                out += markup(mark, size: size)
                var body = AttributedString(String(c[(i + 1)..<end]))
                body.swiftUI.font = .mono(size).italic()
                body.swiftUI.foregroundColor = Theme.textPrimary
                out += body
                out += markup(mark, size: size)
                i = end + 1
                continue
            }
            // `code`
            if c[i] == "`", let end = find(c, ["`"], from: i + 1) {
                flush()
                var code = AttributedString(String(c[i...end]))
                code.swiftUI.font = .mono(size)
                code.swiftUI.foregroundColor = Theme.noteCode
                code.swiftUI.backgroundColor = Theme.noteCodeBg
                out += code
                i = end + 1
                continue
            }
            // [text](url)
            if c[i] == "[", let close = find(c, ["]", "("], from: i + 1),
               let paren = find(c, [")"], from: close + 2) {
                flush()
                out += markup("[", size: size)
                var label = AttributedString(String(c[(i + 1)..<close]))
                label.swiftUI.font = .mono(size)
                label.swiftUI.foregroundColor = Theme.noteLink
                out += label
                out += markup("](", size: size)
                var url = AttributedString(String(c[(close + 2)..<paren]))
                url.swiftUI.font = .mono(size)
                url.swiftUI.foregroundColor = Theme.noteLink
                url.swiftUI.underlineStyle = .single
                out += url
                out += markup(")", size: size)
                i = paren + 1
                continue
            }
            buffer.append(c[i])
            i += 1
        }
        flush()
        return out
    }

    // MARK: Helpers

    private static func find(_ c: [Character], _ pattern: [Character], from start: Int) -> Int? {
        guard start <= c.count - pattern.count else { return nil }
        var i = start
        while i <= c.count - pattern.count {
            if Array(c[i..<(i + pattern.count)]) == pattern { return i }
            i += 1
        }
        return nil
    }

    private static func plain(_ s: String, size: CGFloat) -> AttributedString {
        var a = AttributedString(s)
        a.swiftUI.font = .mono(size)
        a.swiftUI.foregroundColor = Theme.textPrimary
        return a
    }

    private static func markup(_ s: String, size: CGFloat, bold: Bool = false) -> AttributedString {
        var a = AttributedString(s)
        a.swiftUI.font = .mono(size, bold: bold)
        a.swiftUI.foregroundColor = Theme.noteMarkup
        return a
    }
}
