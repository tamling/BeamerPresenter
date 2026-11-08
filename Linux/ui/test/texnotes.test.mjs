// TexNotes reads \note{…} from a .tex next to the deck — a file the deck's
// author controls. Crafted sources must parse in linear time: an unclosed
// group used to make every later \note rescan to the end of the file
// (quadratic), freezing the console for minutes on a few MB.
// Run with: node --test Linux/ui/test/*.test.mjs

import { test } from "node:test";
import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import vm from "node:vm";

// texnotes.js is a classic browser script that reads the .tex/.nav through
// Tauri commands: run it in a fresh context with a stubbed invoke that serves
// the files from `files`.
function loadTexNotes(files) {
  const source = readFileSync(new URL("../js/texnotes.js", import.meta.url), "utf8");
  const invoke = async (cmd, args) => {
    if (cmd === "tex_candidates") return ["/deck/deck.tex"];
    if (cmd === "read_text") return files[args.path] ?? null;
    throw new Error(`unexpected command ${cmd}`);
  };
  const context = vm.createContext({ window: { __TAURI__: { core: { invoke } } } });
  vm.runInContext(`${source};globalThis.TexNotes = TexNotes;`, context);
  return context.TexNotes;
}

async function notesFor(tex, pageCount = 10) {
  const map = await loadTexNotes({ "/deck/deck.tex": tex }).load("/deck/deck.pdf", pageCount);
  return Object.fromEntries(map);
}

async function assertFast(tex, ms = 1500) {
  const start = performance.now();
  const notes = await notesFor(tex);
  const took = performance.now() - start;
  assert.ok(took < ms, `parsing took ${Math.round(took)} ms`);
  return notes;
}

test("notes are attached to their frames", async () => {
  const notes = await notesFor([
    "\\begin{frame}{One}\\note{First note}\\end{frame}",
    "\\begin{frame}{Two}\\end{frame}",
    "\\begin{frame}{Three}\\note<2>{Overlay}\\note[item]{Item}\\end{frame}",
  ].join("\n"));
  assert.equal(notes[0], "First note");
  assert.equal(notes[1], undefined);
  assert.match(notes[2], /Overlay/);
  assert.match(notes[2], /Item/);
});

test("an unclosed \\note{ followed by many more \\note{ stays linear", async () => {
  const tex = "\\begin{frame}\\note{kept}\\end{frame}\n\\begin{frame}\\note{open to the end\n"
    + "\\note{lorem ipsum dolor \n".repeat(150_000);
  const notes = await assertFast(tex);
  assert.equal(notes[0], "kept");
});

test("unclosed \\note< and \\note[ overlays stay linear", async () => {
  await assertFast("\\begin{frame}\\note<2 \n".repeat(100_000));
  await assertFast("\\begin{frame}\\note[item \n".repeat(100_000));
});

test("an unclosed \\begin{ stays linear", async () => {
  await assertFast("\\begin{frame \\note{x}\n".repeat(100_000));
});
