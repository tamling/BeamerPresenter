// Speaker-notes highlighting — mirrors Sources/BeamerPresenter/NotesMarkup.swift.
// Notes from \note{…} are plain text; Markdown habits in them (# heading,
// - item, **bold**, *italic*, `code`, > question, [text](url)) are highlighted
// like a code editor does: markup characters stay visible in the note colour.
// Output is HTML built only from escaped text, so note content can't inject.

const NotesMarkup = (() => {
  const esc = (s) => s.replace(/&/g, "&amp;").replace(/</g, "&lt;")
                      .replace(/>/g, "&gt;").replace(/"/g, "&quot;");
  const span = (cls, html) => `<span class="${cls}">${html}</span>`;
  const mark = (s) => span("md-mark", esc(s));

  function inline(s) {
    let out = "", buf = "", i = 0;
    const flush = () => { out += esc(buf); buf = ""; };
    const isWord = (ch) => /[\p{L}\p{N}]/u.test(ch || "");

    // indexOf is only ever called with a non-decreasing `from` for any one
    // needle, so its last answer stays valid. Without the memo a line of
    // unmatched markers rescans the rest of the line once per marker (O(n²)).
    const hits = new Map();
    const locate = (needle, from) => {
      const cached = hits.get(needle);
      if (cached !== undefined && (cached < 0 || cached >= from)) return cached;
      const hit = s.indexOf(needle, from);
      hits.set(needle, hit);
      return hit;
    };

    while (i < s.length) {
      // **bold**
      if (s.startsWith("**", i)) {
        const end = locate("**", i + 2);
        if (end > i + 2) {
          flush();
          out += mark("**") + span("md-bold", esc(s.slice(i + 2, end))) + mark("**");
          i = end + 2; continue;
        }
      }
      // *italic* / _italic_ (not inside a word, so snake_case stays plain)
      const ch = s[i];
      if ((ch === "*" || ch === "_") && !isWord(s[i - 1]) && s[i + 1] && s[i + 1] !== " ") {
        const end = locate(ch, i + 1);
        if (end > i + 1) {
          flush();
          out += mark(ch) + span("md-italic", esc(s.slice(i + 1, end))) + mark(ch);
          i = end + 1; continue;
        }
      }
      // `code`
      if (ch === "`") {
        const end = locate("`", i + 1);
        if (end > i) {
          flush();
          out += span("md-code", esc(s.slice(i, end + 1)));
          i = end + 1; continue;
        }
      }
      // [text](url)
      if (ch === "[") {
        const close = locate("](", i + 1);
        const paren = close > 0 ? locate(")", close + 2) : -1;
        if (close > 0 && paren > 0) {
          flush();
          out += mark("[") + span("md-link", esc(s.slice(i + 1, close))) + mark("](")
               + span("md-url", esc(s.slice(close + 2, paren))) + mark(")");
          i = paren + 1; continue;
        }
      }
      buf += ch; i += 1;
    }
    flush();
    return out;
  }

  function line(l) {
    const trimmed = l.replace(/^ +/, "");
    const indent = esc(l.slice(0, l.length - trimmed.length));
    let m;
    if ((m = trimmed.match(/^(#{1,6}) (.*)$/))) {
      return indent + span("md-mark md-bold", esc(m[1] + " ")) + span("md-heading", esc(m[2]));
    }
    if (/^-{3,}$/.test(trimmed)) return indent + mark(trimmed);
    if (trimmed.startsWith("> ")) {
      return indent + mark("> ") + span("md-quote", inline(trimmed.slice(2)));
    }
    if ((m = trimmed.match(/^([-*+•] |\d+\. )(.*)$/))) {
      return indent + mark(m[1]) + inline(m[2]);
    }
    return inline(l);
  }

  return { html: (text) => text.split("\n").map(line).join("\n") };
})();
