// Shared whiteboard rendering for the presenter and audience windows.
//
// A board is `{ strokes: [{ color, width, points: [[x, y], …] }] }` with all
// geometry in *unit* coordinates (0…1 of the board, like the macOS app) and a
// *relative* stroke width (fraction of the board width), so ink scales
// identically on the presenter pane and the projector.

"use strict";

const Board = (() => {
  // Mirrors BoardStyle in WhiteboardView.swift: dark = Night look with a faint
  // dot grid; light = ink-on-white (used e.g. under bright projectors).
  const STYLES = {
    dark:  { bg: "#0C0D10", grid: "rgba(91,99,110,0.4)", showGrid: true },
    light: { bg: "#FFFFFF", grid: "transparent",         showGrid: false }
  };

  // Pen palette (PenInk in Theme.swift).
  const PENS = [
    { name: "red",    color: "#FF5A4D" },
    { name: "yellow", color: "#E8C84E" },
    { name: "green",  color: "#5BD08A" },
    { name: "blue",   color: "#5BA8FF" }
  ];

  const RELATIVE_WIDTH = 0.004;   // default pen width as a fraction of board width

  /// Sizes `canvas` to fit maxW × maxH at `aspect` (sharp on HiDPI) and draws
  /// the board: background, dot grid, committed strokes, and the in-progress
  /// `live` stroke ({ color, width, points }) if given.
  function draw(canvas, board, styleName, maxW, maxH, aspect, live = null) {
    const style = STYLES[styleName] || STYLES.dark;
    const cssW = Math.min(maxW, maxH * aspect);
    const cssH = cssW / aspect;
    const dpr = window.devicePixelRatio || 1;
    canvas.width = Math.floor(cssW * dpr);
    canvas.height = Math.floor(cssH * dpr);
    canvas.style.width = `${cssW}px`;
    canvas.style.height = `${cssH}px`;

    const ctx = canvas.getContext("2d");
    const w = canvas.width, h = canvas.height;
    ctx.fillStyle = style.bg;
    ctx.fillRect(0, 0, w, h);

    if (style.showGrid) {
      ctx.fillStyle = style.grid;
      const step = w / 48;
      const r = Math.max(1, w / 900);
      for (let y = step; y < h; y += step) {
        for (let x = step; x < w; x += step) {
          ctx.beginPath();
          ctx.arc(x, y, r, 0, 2 * Math.PI);
          ctx.fill();
        }
      }
    }

    for (const stroke of board?.strokes || []) drawStroke(ctx, stroke, w, h);
    if (live && live.points.length > 1) drawStroke(ctx, live, w, h);
  }

  function drawStroke(ctx, stroke, w, h) {
    const points = stroke.points;
    if (!points || points.length < 2) return;
    ctx.strokeStyle = stroke.color;
    ctx.lineWidth = Math.max(1, stroke.width * w);
    ctx.lineCap = "round";
    ctx.lineJoin = "round";
    ctx.beginPath();
    ctx.moveTo(points[0][0] * w, points[0][1] * h);
    // Midpoint smoothing — same visual as the macOS Catmull-ish path.
    for (let i = 1; i < points.length - 1; i++) {
      const midX = (points[i][0] + points[i + 1][0]) / 2 * w;
      const midY = (points[i][1] + points[i + 1][1]) / 2 * h;
      ctx.quadraticCurveTo(points[i][0] * w, points[i][1] * h, midX, midY);
    }
    const last = points[points.length - 1];
    ctx.lineTo(last[0] * w, last[1] * h);
    ctx.stroke();
  }

  return { draw, STYLES, PENS, RELATIVE_WIDTH };
})();
