// Port of Sources/BeamerPresenter/TexNotes.swift: reads Beamer `\note{...}`
// speaker notes straight from the .tex next to a presentation. Page ranges come
// from the sibling `.nav` file when present (exact, overlay-aware); otherwise
// each frame is assumed to be one page, in document order.
//
// Exposes: TexNotes.load(pdfPath, pageCount) -> Promise<Map<pageIndex, note>>
// (uses the Tauri commands `tex_candidates` and `read_text`).

"use strict";

const TexNotes = (() => {
  const invoke = window.__TAURI__.core.invoke;

  async function load(pdfPath, pageCount) {
    const candidates = await invoke("tex_candidates", { pdfPath });
    for (const texPath of candidates) {
      const map = await notesFromTex(texPath, pageCount);
      if (map.size > 0) return map;
    }
    return new Map();
  }

  async function notesFromTex(texPath, pageCount) {
    const source = await invoke("read_text", { path: texPath });
    if (!source) return new Map();

    const notes = framesWithNotes(source); // frameIndex -> cleaned note
    if (notes.size === 0) return new Map();

    const navPath = texPath.replace(/\.tex$/i, ".nav");
    const nav = await invoke("read_text", { path: navPath });
    const ranges = nav ? framePages(nav) : [];

    const byPage = new Map();
    for (const [frame, note] of notes) {
      let lo, hi;
      if (frame < ranges.length) {
        [lo, hi] = ranges[frame];
      } else if (ranges.length === 0) {
        lo = hi = frame; // one page per frame (0-based)
      } else {
        continue; // nav present but frame unknown
      }
      for (let p = lo; p <= hi; p++) {
        if (p < 0 || p >= pageCount) continue;
        byPage.set(p, byPage.has(p) ? byPage.get(p) + "\n\n" + note : note);
      }
    }
    return byPage;
  }

  // ---- .nav parsing -------------------------------------------------------

  // Each `\beamer@framepages {start}{end}` gives the 1-based page range of a
  // frame, once per frame in document order. Converted to 0-based pairs.
  function framePages(nav) {
    const re = /\\beamer@framepages\s*\{(\d+)\}\{(\d+)\}/g;
    const ranges = [];
    let m;
    while ((m = re.exec(nav)) !== null) {
      const lo = Math.max(0, parseInt(m[1], 10) - 1);
      const hi = Math.max(lo, parseInt(m[2], 10) - 1);
      ranges.push([lo, hi]);
    }
    return ranges;
  }

  // ---- .tex parsing -------------------------------------------------------

  // Walks the comment-stripped source, counting frames and collecting the
  // `\note{...}` bodies that belong to each one.
  function framesWithNotes(rawSource) {
    const s = stripComments(rawSource);
    const n = s.length;
    const notes = new Map();
    let frame = -1; // index of the most recently opened frame
    let i = 0;

    const isLetter = (ch) => /[a-zA-Z@]/.test(ch);

    while (i < n) {
      if (s[i] !== "\\") { i++; continue; }

      // Read the control-word name (letters/`@`) after the backslash.
      let j = i + 1;
      while (j < n && isLetter(s[j])) j++;
      if (j === i + 1) { i += 2; continue; } // control symbol (\%, \{, …)
      const name = s.slice(i + 1, j);

      if (name === "frame" || name === "againframe") {
        frame++;
        i = j;
      } else if (name === "begin") {
        const g = bracedGroup(s, skipSpaces(s, j));
        if (g && g.body === "frame") {
          frame++;
          i = g.after;
        } else {
          i = j;
        }
      } else if (name === "note") {
        let k = skipSpaces(s, j);
        k = skipOptional(s, k, "<", ">"); // \note<2>{…}
        k = skipSpaces(s, k);
        k = skipOptional(s, k, "[", "]"); // \note[item]{…}
        k = skipSpaces(s, k);
        const g = bracedGroup(s, k);
        if (g) {
          const text = cleanup(g.body);
          if (frame >= 0 && text) {
            notes.set(frame, notes.has(frame) ? notes.get(frame) + "\n\n" + text : text);
          }
          i = g.after;
        } else {
          i = j;
        }
      } else {
        i = j;
      }
    }
    return notes;
  }

  function skipSpaces(s, i) {
    while (i < s.length && /[ \t\n\r]/.test(s[i])) i++;
    return i;
  }

  // If s[i] opens an optional group, returns the index just past its close;
  // otherwise returns i unchanged.
  function skipOptional(s, i, open, close) {
    if (i >= s.length || s[i] !== open) return i;
    let j = i + 1;
    while (j < s.length && s[j] !== close) j++;
    return j < s.length ? j + 1 : i;
  }

  // Reads a balanced `{ … }` group starting at s[i] === "{", honouring nested
  // braces and `\{` / `\}` escapes.
  function bracedGroup(s, i) {
    if (i >= s.length || s[i] !== "{") return null;
    let depth = 0;
    let j = i;
    const start = i + 1;
    while (j < s.length) {
      const ch = s[j];
      if (ch === "\\") { j += 2; continue; } // skip escaped char
      if (ch === "{") depth++;
      else if (ch === "}") {
        depth--;
        if (depth === 0) return { body: s.slice(start, j), after: j + 1 };
      }
      j++;
    }
    return null;
  }

  // ---- Comment & markup cleanup ------------------------------------------

  // Drops everything after an unescaped `%` on each line.
  function stripComments(s) {
    return s
      .split("\n")
      .map((line) => {
        let out = "";
        let escaped = false;
        for (const ch of line) {
          if (escaped) { out += ch; escaped = false; continue; }
          if (ch === "\\") { out += ch; escaped = true; continue; }
          if (ch === "%") break;
          out += ch;
        }
        return out;
      })
      .join("\n");
  }

  // Best-effort conversion of a LaTeX note body to readable plain text.
  function cleanup(tex) {
    let s = tex;

    // List markup → bullets / blank lines.
    s = s.replace(/\\(begin|end)\s*\{(itemize|enumerate|description)\}/g, "\n");
    s = s.replaceAll("\\item", "\n• ");
    s = s.replaceAll("\\par", "\n\n");
    s = s.replaceAll("\\\\", "\n"); // explicit line break

    // Common escaped specials.
    for (const [esc, plain] of [["\\&", "&"], ["\\%", "%"], ["\\_", "_"],
                                ["\\#", "#"], ["\\$", "$"], ["~", " "]]) {
      s = s.replaceAll(esc, plain);
    }

    // Unwrap simple `\cmd[..]{text}` to its argument (a few passes for
    // nesting), then drop any remaining bare commands and stray braces.
    for (let pass = 0; pass < 3; pass++) {
      s = s.replace(/\\[a-zA-Z@]+\*?\s*(\[[^\]]*\])?\s*\{([^{}]*)\}/g, "$2");
    }
    s = s.replace(/\\[a-zA-Z@]+\*?/g, "");
    s = s.replaceAll("{", "").replaceAll("}", "");

    // Tidy whitespace.
    s = s.replace(/[ \t]+/g, " ");
    s = s.replace(/\n{3,}/g, "\n\n");
    return s.trim();
  }

  return { load };
})();
