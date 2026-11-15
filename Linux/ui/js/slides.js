// Shared slide rendering for the presenter and audience windows.
//
// Wraps pdf.js: loads a deck via Tauri's asset protocol, detects the Beamer
// `show notes on second screen=right` double-width layout (aspect > 2.4, like
// PDFModel.swift), and renders a page — or one half of it — into a canvas
// sized to fit its container.
//
// `makeSlides()` builds an independent instance; `Slides` is the primary deck
// and the presenter keeps a second instance for the translated twin deck.

"use strict";

// pdf.js throws if a render starts on a canvas an earlier one still holds, and
// its guard is keyed on the canvas element — across documents. Every instance
// therefore shares one in-flight task per canvas and cancels it before
// starting the next render there.
const inFlight = new WeakMap();   // canvas -> pdf.js RenderTask

// pdf.js reports /Root/Pages/Count verbatim, and nothing checks it against the
// page tree: a one-kilobyte file can claim five million pages. Everything
// downstream — the strip, the overview, the resume map — builds per-page state
// from that number, so it has to be the count of pages that actually resolve.
// One probe settles an honest deck; a lying one costs a binary search, about
// twenty probes even for a claimed five million.
async function resolves(doc, oneBased) {
  try { await doc.getPage(oneBased); return true; } catch { return false; }
}

async function truePageCount(doc) {
  const declared = doc.numPages;
  if (!Number.isInteger(declared) || declared < 1) return 0;
  if (declared === 1 || await resolves(doc, declared)) return declared;
  let lo = 1, hi = declared;          // lo resolves (page 1 was already read), hi does not
  while (hi - lo > 1) {
    const mid = Math.floor((lo + hi) / 2);
    if (await resolves(doc, mid)) lo = mid; else hi = mid;
  }
  console.warn(`PDF declares ${declared} pages but only ${lo} resolve; using ${lo}.`);
  return lo;
}

function makeSlides() {
  let pdf = null;        // pdf.js document
  let task = null;       // its loading task — what owns the worker (see close())
  let count = 0;         // pages that really resolve, not the declared /Count
  let split = false;     // double-width notes layout?
  let aspect = 16 / 9;   // aspect of the slide half (for layout)

  async function open(path) {
    close();             // one document per instance; the old one goes away
    // The asset protocol's configured scope is empty, so this deck has to be
    // granted before its URL resolves. Doing it here covers every open: the
    // presenter and the audience window both load through this function.
    if (!(await window.__TAURI__.core.invoke("allow_deck", { path }))) {
      throw new Error("Could not open this file: " + path);
    }
    const url = window.__TAURI__.core.convertFileSrc(path);
    // isEvalSupported: false — type-4 (PostScript calculator) functions are
    // then interpreted instead of compiled with `new Function` in the worker.
    task = pdfjsLib.getDocument({ url, isEvalSupported: false });
    pdf = await task.promise;
    const first = await pdf.getPage(1);
    const vp = first.getViewport({ scale: 1 });
    split = vp.width / Math.max(vp.height, 1) > 2.4;
    const w = split ? vp.width / 2 : vp.width;
    // A page box the PDF declares as zero or non-numeric would otherwise make the
    // aspect 0 or NaN and collapse every layout that divides by it.
    const a = w / Math.max(vp.height, 1);
    aspect = Number.isFinite(a) && a > 0 ? a : 16 / 9;
    count = await truePageCount(pdf);
    return { pageCount: count, split, aspect };
  }

  // Tearing down is what releases pdf.js's worker thread and the document's
  // font, image and operator-list caches — dropping the reference leaks them.
  // The loading task is the owner: PDFDocumentProxy.destroy() was removed in
  // pdf.js 6, while PDFDocumentLoadingTask.destroy() works in both 4 and 6.
  function close() {
    const doc = pdf;
    const loading = task;
    pdf = null;          // before awaiting anything: callers see it closed
    task = null;
    count = 0;
    split = false;
    aspect = 16 / 9;
    // Also rejects any pending render.
    const stop = loading?.destroy?.() ?? doc?.destroy?.();
    stop?.catch?.(() => {});
  }
  function pageCount() { return pdf ? count : 0; }
  function isSplit() { return split; }
  function slideAspect() { return aspect; }

  // Renders page `index` (0-based) into `canvas`, fitted inside maxW × maxH
  // CSS pixels (sharp on HiDPI). `half`: "full" | "left" | "right" — on a
  // split deck the slide is the left half, the notes column the right half.
  // Returns false if there was nothing to draw, or if the pass was superseded
  // or the document closed under it — never throws, so a fire-and-forget call
  // site cannot leave an unhandled rejection behind.
  async function render(canvas, index, maxW, maxH, half = "full") {
    if (!pdf || index < 0 || index >= pdf.numPages) return false;
    if (maxW <= 0 || maxH <= 0) return false;   // hidden container: nothing fits
    try {
      const page = await pdf.getPage(index + 1);
      const base = page.getViewport({ scale: 1 });
      const srcW = half === "full" ? base.width : base.width / 2;

      const fit = Math.min(maxW / srcW, maxH / base.height);
      const dpr = window.devicePixelRatio || 1;
      const scale = fit * dpr;

      // offsetX shifts the page so the wanted half lands on the canvas.
      const offsetX = half === "right" ? -srcW * scale : 0;
      const viewport = page.getViewport({ scale, offsetX, offsetY: 0 });

      // Stop a render still painting this canvas first: resizing it below
      // would wipe the context out from under it. From here to the render()
      // call nothing awaits, so two passes cannot both slip past the cancel.
      inFlight.get(canvas)?.cancel();

      canvas.width = Math.floor(srcW * scale);
      canvas.height = Math.floor(base.height * scale);
      canvas.style.width = `${srcW * fit}px`;
      canvas.style.height = `${base.height * fit}px`;

      const ctx = canvas.getContext("2d");
      ctx.fillStyle = "#FFFFFF"; // slides assume a white page behind them
      ctx.fillRect(0, 0, canvas.width, canvas.height);
      const task = page.render({ canvasContext: ctx, viewport });
      inFlight.set(canvas, task);
      try {
        await task.promise;
      } finally {
        if (inFlight.get(canvas) === task) inFlight.delete(canvas);
      }
      return true;
    } catch (e) {
      return false;
    }
  }

  return { open, close, pageCount, isSplit, slideAspect, render };
}

const Slides = makeSlides();
