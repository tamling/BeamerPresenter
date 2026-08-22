// Shared slide rendering for the presenter and audience windows.
//
// Wraps pdf.js: loads the deck via Tauri's asset protocol, detects the Beamer
// `show notes on second screen=right` double-width layout (aspect > 2.4, like
// PDFModel.swift), and renders a page — or one half of it — into a canvas
// sized to fit its container.

"use strict";

const Slides = (() => {
  let pdf = null;        // pdf.js document
  let split = false;     // double-width notes layout?
  let aspect = 16 / 9;   // aspect of the slide half (for layout)

  async function open(path) {
    const url = window.__TAURI__.core.convertFileSrc(path);
    pdf = await pdfjsLib.getDocument({ url }).promise;
    const first = await pdf.getPage(1);
    const vp = first.getViewport({ scale: 1 });
    split = vp.width / Math.max(vp.height, 1) > 2.4;
    const w = split ? vp.width / 2 : vp.width;
    aspect = w / Math.max(vp.height, 1);
    return { pageCount: pdf.numPages, split, aspect };
  }

  function close() { pdf = null; }
  function pageCount() { return pdf ? pdf.numPages : 0; }
  function isSplit() { return split; }
  function slideAspect() { return aspect; }

  // Renders page `index` (0-based) into `canvas`, fitted inside maxW × maxH
  // CSS pixels (sharp on HiDPI). `half`: "full" | "left" | "right" — on a
  // split deck the slide is the left half, the notes column the right half.
  async function render(canvas, index, maxW, maxH, half = "full") {
    if (!pdf || index < 0 || index >= pdf.numPages) return false;
    const page = await pdf.getPage(index + 1);
    const base = page.getViewport({ scale: 1 });
    const srcW = half === "full" ? base.width : base.width / 2;

    const fit = Math.min(maxW / srcW, maxH / base.height);
    const dpr = window.devicePixelRatio || 1;
    const scale = fit * dpr;

    // offsetX shifts the page so the wanted half lands on the canvas.
    const offsetX = half === "right" ? -srcW * scale : 0;
    const viewport = page.getViewport({ scale, offsetX, offsetY: 0 });

    canvas.width = Math.floor(srcW * scale);
    canvas.height = Math.floor(base.height * scale);
    canvas.style.width = `${srcW * fit}px`;
    canvas.style.height = `${base.height * fit}px`;

    const ctx = canvas.getContext("2d");
    ctx.fillStyle = "#FFFFFF"; // slides assume a white page behind them
    ctx.fillRect(0, 0, canvas.width, canvas.height);
    await page.render({ canvasContext: ctx, viewport }).promise;
    return true;
  }

  return { open, close, pageCount, isSplit, slideAspect, render };
})();
