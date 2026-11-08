// NotesMarkup must never let note text through as HTML: \note{…} and .pptx
// notes come from the deck, and the console renders the result via innerHTML.
// Run with: node --test Linux/ui/test/

import { test } from "node:test";
import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import vm from "node:vm";

// notesmarkup.js is a classic browser script (`const NotesMarkup = …`): run it
// in a fresh context and hand the binding out.
const source = readFileSync(new URL("../js/notesmarkup.js", import.meta.url), "utf8");
const context = vm.createContext({});
vm.runInContext(`${source};globalThis.NotesMarkup = NotesMarkup;`, context);
const { NotesMarkup } = context;

/// Everything the markup itself may emit: spans with our own classes.
const OWN_TAG = /<\/?span(?: class="md-[a-z]+(?: md-[a-z]+)*")?>/g;

/// Asserts no "<" survives except our own span tags, and no raw quote can
/// break out of an attribute.
function assertInert(input) {
  const html = NotesMarkup.html(input);
  const stripped = html.replace(OWN_TAG, "");
  assert.ok(!stripped.includes("<"), `raw "<" in output for ${JSON.stringify(input)}: ${html}`);
  assert.ok(!stripped.includes(">"), `raw ">" in output for ${JSON.stringify(input)}: ${html}`);
  assert.ok(!stripped.includes('"'), `raw quote in output for ${JSON.stringify(input)}: ${html}`);
  return html;
}

const PAYLOADS = [
  "<script>alert(1)</script>",
  '<img src=x onerror="alert(1)">',
  "<img src=x onerror=alert(1)>",
  '" onmouseover="alert(1)',
  "' onmouseover='alert(1)",
  "[click me](javascript:alert(1))",
  '[<b>x</b>](javascript:alert("1"))',
  "**<script>alert(1)</script>**",
  "*<img src=x onerror=alert(1)>*",
  "_<svg onload=alert(1)>_",
  "`<iframe src=javascript:alert(1)>`",
  "# <script>alert(1)</script>",
  "> <script>alert(1)</script>",
  "- <script>alert(1)</script>",
  "1. **[*`<x>`*](<y>)**",
  "  ### **<a href=\"javascript:alert(1)\">x</a>**",
  "&lt;script&gt; stays &amp; text",
  "</span><script>alert(1)</script><span>",
  "<scr<script>ipt>alert(1)</script>",
  "line one\n<script>\nalert(1)\n</script>"
];

for (const payload of PAYLOADS) {
  test(`escapes ${JSON.stringify(payload)}`, () => {
    assertInert(payload);
  });
}

test("script tags come out as text", () => {
  assert.equal(NotesMarkup.html("<script>alert(1)</script>"),
    "&lt;script&gt;alert(1)&lt;/script&gt;");
});

test("quotes and ampersands are escaped", () => {
  const html = NotesMarkup.html(`a "b" & <c>`);
  assert.equal(html, "a &quot;b&quot; &amp; &lt;c&gt;");
});

test("already-escaped text is escaped again, not decoded", () => {
  assert.equal(NotesMarkup.html("&lt;b&gt;"), "&amp;lt;b&amp;gt;");
});

test("javascript: links stay visible text, never an href", () => {
  const html = assertInert("[click me](javascript:alert(1))");
  assert.ok(!/href|<a\b/i.test(html), html);
  // The URL ends at the first ")" — either way it is plain highlighted text.
  assert.ok(html.includes('<span class="md-url">javascript:alert(1</span>'), html);
});

test("markup inside markup is still escaped", () => {
  const html = assertInert("**<b>*<i>`<code>`</i>*</b>**");
  assert.ok(html.startsWith('<span class="md-mark">**</span><span class="md-bold">'), html);
  assert.ok(html.includes("&lt;b&gt;"), html);
});

test("output is only our own spans around escaped text", () => {
  const input = "# Title\n- **bold** and *it* `code` > q [l](u)\n> quote <x>";
  const html = assertInert(input);
  const tags = html.match(/<[^>]*>/g) || [];
  for (const tag of tags) assert.match(tag, /^<\/?span( class="md-[a-z]+( md-[a-z]+)*")?>$/);
});

test("plain text round-trips", () => {
  assert.equal(NotesMarkup.html("Greet the audience\nSmile"), "Greet the audience\nSmile");
});
