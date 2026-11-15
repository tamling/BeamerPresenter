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

function makeSlides() {
  let pdf = null;        // pdf.js document
  let split = false;     // double-width notes layout?
  let aspect = 16 / 9;   // aspect of the slide half (for layout)

  async function open(path) {
    close();             // one document per instance; the old one goes away
    const url = window.__TAURI__.core.convertFileSrc(path);
    // isEvalSupported: false — type-4 (PostScript calculator) functions are
    // then interpreted instead of compiled with `new Function` in the worker.
    pdf = await pdfjsLib.getDocument({ url, isEvalSupported: false }).promise;
    const first = await pdf.getPage(1);
    const vp = first.getViewport({ scale: 1 });
    split = vp.width / Math.max(vp.height, 1) > 2.4;
    const w = split ? vp.width / 2 : vp.width;
    // A page box the PDF declares as zero or non-numeric would otherwise make the
    // aspect 0 or NaN and collapse every layout that divides by it.
    const a = w / Math.max(vp.height, 1);
    aspect = Number.isFinite(a) && a > 0 ? a : 16 / 9;
    return { pageCount: pdf.numPages, split, aspect };
  }

  // destroy() is what tears down pdf.js's worker thread and the document's
  // font, image and operator-list caches — dropping the reference leaks them.
  function close() {
    const doc = pdf;
    pdf = null;          // before awaiting anything: callers see it closed
    split = false;
    aspect = 16 / 9;
    doc?.destroy().catch(() => {});   // also rejects any pending render
  }
  function pageCount() { return pdf ? pdf.numPages : 0; }
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
