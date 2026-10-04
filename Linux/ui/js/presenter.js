// Presenter window: home screen (open / drop / recents) and the console
// (current + next slide, notes, clock, elapsed timer, overview, blackout).
// The audience window renders the same deck itself and follows via events.

"use strict";

(() => {
  const { invoke, convertFileSrc } = window.__TAURI__.core;
  const { listen, emitTo } = window.__TAURI__.event;

  // ---- State ---------------------------------------------------------------

  const state = {
    path: null,      // PDF being presented
    page: 0,
    count: 0,
    split: false,    // Beamer "show notes on second screen=right" layout
    blackout: false,
    notes: new Map(), // pageIndex -> note text (plain-PDF decks only)
    // Whiteboard: boards live outside the PDF, in-memory for the session.
    boards: [],       // [{ strokes: [{color, width, points}] }]
    boardIndex: null, // active board while the whiteboard is up, else null
    boardLight: false,
    penColor: Board.PENS[0].color
  };

  const el = (id) => document.getElementById(id);

  // ---- Audience sync -------------------------------------------------------

  function pushDeck() {
    emitTo("audience", "deck", { path: state.path, split: state.split });
  }
  function pushState() {
    emitTo("audience", "state", { page: state.page, blackout: state.blackout });
  }
  function pushBoard() {
    const active = state.boardIndex !== null;
    emitTo("audience", "board", {
      active,
      light: state.boardLight,
      aspect: Slides.slideAspect(),
      strokes: active ? state.boards[state.boardIndex].strokes : []
    });
  }

  // ---- Home screen ---------------------------------------------------------

  const RECENTS_KEY = "recents";
  const RECENTS_MAX = 10;
  const CARDS_MAX = 3;   // up to here: rich cards; more: a compact list
  const loadRecents = () => JSON.parse(localStorage.getItem(RECENTS_KEY) || "[]");
  function addRecent(path) {
    const list = [path, ...loadRecents().filter((p) => p !== path)].slice(0, RECENTS_MAX);
    localStorage.setItem(RECENTS_KEY, JSON.stringify(list));
  }

  function splitName(path) {
    const name = path.split("/").pop();
    const dot = name.lastIndexOf(".");
    return {
      base: dot > 0 ? name.slice(0, dot) : name,
      ext: dot > 0 ? name.slice(dot + 1).toUpperCase() : "PDF",
      dir: path.slice(0, path.length - name.length - 1) || "/"
    };
  }

  function renderRecents() {
    const box = el("recents");
    const list = loadRecents();
    box.innerHTML = "";
    const compact = list.length > CARDS_MAX;
    box.classList.toggle("compact", compact);
    for (const path of list) {
      const { base, ext, dir } = splitName(path);
      const cell = document.createElement("div");
      if (compact) {
        cell.className = "recent-row";
        cell.innerHTML =
          `<span class="row-ext"></span><span class="row-name"></span>
           <span class="row-path"></span>`;
        cell.querySelector(".row-ext").textContent = ext;
        cell.querySelector(".row-name").textContent = base;
        cell.querySelector(".row-path").textContent = dir;
      } else {
        cell.className = "recent-card card";
        cell.innerHTML =
          `<div class="recent-ext"></div>
           <div style="min-width:0">
             <div class="recent-name"></div><div class="recent-path"></div>
           </div>`;
        cell.querySelector(".recent-ext").textContent = ext;
        cell.querySelector(".recent-name").textContent = base;
        cell.querySelector(".recent-path").textContent = path;
      }
      cell.title = path;
      cell.addEventListener("click", () => openAny(path));
      box.appendChild(cell);
    }
  }

  // ---- Per-deck resume -----------------------------------------------------

  const POS_KEY = "lastSlideByPath";
  const loadPositions = () => JSON.parse(localStorage.getItem(POS_KEY) || "{}");
  function savePosition(path, page) {
    const map = loadPositions();
    map[path] = page;
    localStorage.setItem(POS_KEY, JSON.stringify(map));
  }

  // ---- Opening decks -------------------------------------------------------

  function hud(title, detail = "", closable = false) {
    el("hud-title").textContent = title;
    el("hud-detail").textContent = detail;
    el("hud-close").style.display = closable ? "inline-block" : "none";
    el("hud").classList.add("active");
  }
  const hideHud = () => el("hud").classList.remove("active");
  el("hud-close").addEventListener("click", hideHud);

  // A picked/dropped file: a .pdf directly; a .tex via its sibling PDF or by
  // compiling it; a PowerPoint/ODP via its sibling PDF or a LibreOffice
  // conversion (mirrors the macOS open flow).
  async function openAny(path) {
    const lower = path.toLowerCase();
    const viaSiblingOr = async (extRe, title, detail, command, arg) => {
      const sibling = path.replace(extRe, ".pdf");
      if (await invoke("file_exists", { path: sibling })) return openPDF(sibling);
      hud(title, detail);
      const result = await invoke(command, arg);
      hideHud();
      if (result.ok) return openPDF(result.pdf_path);
      hud(`Could not open ${path.split("/").pop()}`, result.log, true);
    };
    if (lower.endsWith(".tex")) {
      return viaSiblingOr(/\.tex$/i, `Compiling ${path.split("/").pop()}…`,
        "Running LaTeX…", "compile_tex", { texPath: path });
    }
    if (/\.(pptx|ppt|odp)$/.test(lower)) {
      return viaSiblingOr(/\.(pptx|ppt|odp)$/i, `Converting ${path.split("/").pop()}…`,
        "Using LibreOffice…", "convert_office", { path });
    }
    if (lower.endsWith(".pdf")) return openPDF(path);
    hud("Unsupported file", "Drop a .pdf, .tex, .pptx, .ppt or .odp.", true);
  }

  async function openPDF(path) {
    try {
      const info = await Slides.open(path);
      state.path = path;
      state.count = info.pageCount;
      state.split = info.split;
      // Resume where this deck was left last time (first slide for new decks).
      state.page = Math.min(Math.max(0, loadPositions()[path] || 0), info.pageCount - 1);
      state.blackout = false;
      // Plain single-screen PDFs pull \note{} text from the .tex next to them
      // — or PowerPoint speaker notes from a sibling .pptx (converted decks);
      // split decks carry their notes on the page's right half already.
      state.notes = info.split ? new Map() : await TexNotes.load(path, info.pageCount);
      if (!info.split && state.notes.size === 0) {
        const pptxNotes = await invoke("pptx_notes", { pdfPath: path });
        state.notes = new Map(pptxNotes
          .map((text, i) => [i, text])
          .filter(([, text]) => text && text.trim() !== ""));
      }
    } catch (e) {
      return hud("Could not open PDF", String(e), true);
    }
    addRecent(path);
    el("deck-title").textContent = path.split("/").pop().replace(/\.pdf$/i, "");
    el("home").classList.add("hidden");
    el("console").classList.add("active");
    buildOverview();
    buildStrip();
    pushDeck();
    pushState();
    await invoke("show_audience");
    renderAll();
  }

  function closeDeck() {
    Slides.close();
    state.path = null;
    state.blackout = false;
    state.boards = [];
    if (boardActive()) { state.boardIndex = null; setBoardVisible(false); }
    pushBoard();
    invoke("hide_audience");
    el("strip").innerHTML = "";
    el("console").classList.remove("active");
    el("overview").classList.remove("active");
    el("home").classList.remove("hidden");
    renderRecents();
  }

  // Leaving the presentation: back to the home screen, or quit entirely
  // (mirrors the macOS exit dialog).
  el("close-btn").addEventListener("click", () => {
    if (state.path) el("exit-dialog").style.display = "flex";
  });
  el("exit-home").addEventListener("click", () => {
    el("exit-dialog").style.display = "none";
    closeDeck();
  });
  el("exit-quit").addEventListener("click", () => invoke("quit_app"));
  el("exit-cancel").addEventListener("click", () => {
    el("exit-dialog").style.display = "none";
  });

  // ---- Console rendering ---------------------------------------------------

  async function renderAll() {
    if (!state.path) return;
    const pane = document.querySelector(".current-pane");
    await Slides.render(el("current"), state.page,
      pane.clientWidth - 36, pane.clientHeight - 36,
      state.split ? "left" : "full");

    const nextWrap = document.querySelector(".next-frame");
    const nw = nextWrap.clientWidth - 16;
    if (state.page + 1 < state.count) {
      el("next").style.visibility = "visible";
      await Slides.render(el("next"), state.page + 1, nw, nw / Slides.slideAspect(),
        state.split ? "left" : "full");
    } else {
      el("next").style.visibility = "hidden";
    }

    if (state.split) {
      // Notes are the right half of the current page.
      el("notes").style.display = "none";
      const wrap = el("notes-canvas-wrap");
      wrap.style.display = "flex";
      await Slides.render(el("notes-canvas"), state.page,
        wrap.clientWidth - 24, 1e6, "right");
    } else {
      el("notes-canvas-wrap").style.display = "none";
      const notes = el("notes");
      notes.style.display = "block";
      const text = state.notes.get(state.page) || "";
      notes.textContent = text || "No notes for this slide.";
      notes.classList.toggle("empty", !text);
    }

    el("counter").textContent = `${state.page + 1} / ${state.count}`;
    const live = el("live");
    live.textContent = state.blackout ? "BLACK" : "LIVE";
    live.classList.toggle("black", state.blackout);
    highlightOverview();
    highlightStrip();
  }

  let resizeTimer = null;
  window.addEventListener("resize", () => {
    clearTimeout(resizeTimer);
    resizeTimer = setTimeout(() => { renderAll(); renderBoard(); }, 120);
  });

  // ---- Whiteboard ----------------------------------------------------------

  const boardActive = () => state.boardIndex !== null;
  const activeBoard = () => state.boards[state.boardIndex];

  function renderBoard(live = null) {
    if (!boardActive()) return;
    const area = el("board-area");
    Board.draw(el("board-canvas"), activeBoard(),
      state.boardLight ? "light" : "dark",
      area.clientWidth, area.clientHeight, Slides.slideAspect(), live);
    el("board-counter").textContent = `${state.boardIndex + 1}/${state.boards.length}`;
  }

  function setBoardVisible(on) {
    document.querySelector(".current-pane").style.display = on ? "none" : "flex";
    el("board-wrap").classList.toggle("active", on);
    el("board-btn").classList.toggle("on", on);
  }

  function toggleBoard() {
    if (!state.path) return;
    if (boardActive()) {
      state.boardIndex = null;
      setBoardVisible(false);
    } else {
      if (state.boards.length === 0) state.boards.push({ strokes: [] });
      state.boardIndex = state.boards.length - 1;
      setBoardVisible(true);
      renderBoard();
    }
    pushBoard();
  }

  function switchBoard(delta) {
    if (!boardActive()) return;
    const n = state.boards.length;
    state.boardIndex = (state.boardIndex + delta + n) % n;
    renderBoard();
    pushBoard();
  }

  function newBoard() {
    if (!boardActive()) return;
    state.boards.push({ strokes: [] });
    state.boardIndex = state.boards.length - 1;
    renderBoard();
    pushBoard();
  }

  function deleteBoard() {
    if (!boardActive()) return;
    state.boards.splice(state.boardIndex, 1);
    if (state.boards.length === 0) state.boards.push({ strokes: [] });
    state.boardIndex = Math.min(state.boardIndex, state.boards.length - 1);
    renderBoard();
    pushBoard();
  }

  function undoStroke() {
    if (!boardActive()) return;
    activeBoard().strokes.pop();
    renderBoard();
    pushBoard();
  }

  function clearBoard() {
    if (!boardActive()) return;
    activeBoard().strokes = [];
    renderBoard();
    pushBoard();
  }

  function toggleBoardStyle() {
    state.boardLight = !state.boardLight;
    el("wb-style").textContent = state.boardLight ? "Dark" : "Light";
    renderBoard();
    pushBoard();
  }

  // Drawing: pointer events on the board canvas, in unit coordinates.
  let stroke = null;      // in-progress {color, width, points}
  let lastLiveEmit = 0;

  function boardPoint(e) {
    const rect = el("board-canvas").getBoundingClientRect();
    return [
      Math.min(1, Math.max(0, (e.clientX - rect.left) / rect.width)),
      Math.min(1, Math.max(0, (e.clientY - rect.top) / rect.height))
    ];
  }

  el("board-canvas").addEventListener("pointerdown", (e) => {
    if (!boardActive() || e.button !== 0) return;
    el("board-canvas").setPointerCapture(e.pointerId);
    stroke = { color: state.penColor, width: Board.RELATIVE_WIDTH, points: [boardPoint(e)] };
  });
  el("board-canvas").addEventListener("pointermove", (e) => {
    if (!stroke) return;
    stroke.points.push(boardPoint(e));
    renderBoard(stroke);
    const now = performance.now();
    if (now - lastLiveEmit > 40) {   // ~25 fps live ink on the projector
      lastLiveEmit = now;
      emitTo("audience", "board-live", stroke);
    }
  });
  const endStroke = () => {
    if (!stroke) return;
    if (stroke.points.length > 1) activeBoard().strokes.push(stroke);
    stroke = null;
    renderBoard();
    pushBoard();                      // full state; also clears the live stroke
  };
  el("board-canvas").addEventListener("pointerup", endStroke);
  el("board-canvas").addEventListener("pointercancel", endStroke);

  // Toolbar: colour dots + buttons.
  for (const pen of Board.PENS) {
    const dot = document.createElement("button");
    dot.className = "wb-color" + (pen.color === state.penColor ? " on" : "");
    dot.style.background = pen.color;
    dot.title = `Pen: ${pen.name}`;
    dot.addEventListener("click", () => {
      state.penColor = pen.color;
      document.querySelectorAll(".wb-color").forEach((b) => b.classList.remove("on"));
      dot.classList.add("on");
    });
    el("board-toolbar").insertBefore(dot, el("board-toolbar").querySelector(".sep"));
  }
  el("board-btn").addEventListener("click", toggleBoard);
  el("wb-close").addEventListener("click", toggleBoard);
  el("wb-undo").addEventListener("click", undoStroke);
  el("wb-clear").addEventListener("click", clearBoard);
  el("wb-prev").addEventListener("click", () => switchBoard(-1));
  el("wb-next").addEventListener("click", () => switchBoard(1));
  el("wb-new").addEventListener("click", newBoard);
  el("wb-delete").addEventListener("click", deleteBoard);
  el("wb-style").addEventListener("click", toggleBoardStyle);

  // ---- Thumbnail strip (zoomable, mirrors the macOS strip) -----------------

  let stripHeight = (() => {
    const h = parseFloat(localStorage.getItem("stripHeight"));
    return Number.isFinite(h) ? Math.min(Math.max(h, 50), 200) : 70;
  })();
  // Thumbnails render at 64px buckets and are *displayed* scaled to the live
  // height, so dragging the zoom handle never re-renders per pixel.
  const stripBucket = () => Math.max(64, Math.ceil(stripHeight / 64) * 64);
  let renderedBucket = 0;
  let stripRenderToken = 0;

  function buildStrip() {
    const strip = el("strip");
    strip.innerHTML = "";
    for (let i = 0; i < state.count; i++) {
      const cell = document.createElement("div");
      cell.className = "strip-cell";
      const canvas = document.createElement("canvas");
      const num = document.createElement("div");
      num.className = "strip-num";
      num.textContent = String(i + 1);
      cell.append(canvas, num);
      cell.addEventListener("click", () => goTo(i));
      strip.appendChild(cell);
    }
    renderedBucket = 0;
    renderStrip();
  }

  function applyStripScale() {
    const h = stripHeight;
    for (const cell of el("strip").children) {
      const canvas = cell.querySelector("canvas");
      canvas.style.height = `${h}px`;
      canvas.style.width = `${h * Slides.slideAspect()}px`;
    }
  }

  async function renderStrip() {
    const bucket = stripBucket();
    applyStripScale();
    if (bucket === renderedBucket) return;
    renderedBucket = bucket;
    const token = ++stripRenderToken;
    const cells = el("strip").children;
    for (let i = 0; i < cells.length; i++) {
      if (token !== stripRenderToken) return;   // superseded by a newer pass
      const canvas = cells[i].querySelector("canvas");
      await Slides.render(canvas, i, bucket * Slides.slideAspect(), bucket,
        state.split ? "left" : "full");
    }
    applyStripScale();   // Slides.render set per-canvas sizes; rescale to live height
  }

  function highlightStrip() {
    const cells = el("strip").children;
    for (let i = 0; i < cells.length; i++) {
      cells[i].classList.toggle("current", i === state.page);
    }
    cells[state.page]?.scrollIntoView({ inline: "center", block: "nearest", behavior: "smooth" });
  }

  // Drag the handle to zoom; re-render crisp at the new bucket on release.
  (() => {
    const handle = el("strip-handle");
    let startY = null, startH = null;
    handle.addEventListener("pointerdown", (e) => {
      startY = e.clientY;
      startH = stripHeight;
      handle.setPointerCapture(e.pointerId);
    });
    handle.addEventListener("pointermove", (e) => {
      if (startY === null) return;
      stripHeight = Math.min(Math.max(startH + (startY - e.clientY), 50), 200);
      applyStripScale();   // pure scaling while dragging — stays fluid
    });
    const done = () => {
      if (startY === null) return;
      startY = null;
      localStorage.setItem("stripHeight", String(stripHeight));
      renderStrip();       // crisp re-render at the final bucket
    };
    handle.addEventListener("pointerup", done);
    handle.addEventListener("pointercancel", done);
  })();

  // ---- Navigation ----------------------------------------------------------

  function goTo(page) {
    const p = Math.max(0, Math.min(state.count - 1, page));
    if (p === state.page) return;
    state.page = p;
    if (state.path) savePosition(state.path, p);
    pushState();
    renderAll();
  }
  const next = () => goTo(state.page + 1);
  const previous = () => goTo(state.page - 1);

  function toggleBlackout() {
    state.blackout = !state.blackout;
    pushState();
    renderAll();
  }

  // ---- Overview grid -------------------------------------------------------

  function buildOverview() {
    const grid = el("ov-grid");
    grid.innerHTML = "";
    for (let i = 0; i < state.count; i++) {
      const cell = document.createElement("div");
      cell.className = "ov-cell";
      const canvas = document.createElement("canvas");
      const num = document.createElement("div");
      num.className = "ov-num";
      num.textContent = String(i + 1);
      cell.append(canvas, num);
      cell.addEventListener("click", () => {
        el("overview").classList.remove("active");
        goTo(i);
      });
      grid.appendChild(cell);
    }
  }

  let overviewRendered = false;
  async function toggleOverview() {
    const ov = el("overview");
    const showing = ov.classList.toggle("active");
    if (showing && !overviewRendered) {
      overviewRendered = true;
      const cells = el("ov-grid").children;
      for (let i = 0; i < cells.length; i++) {
        await Slides.render(cells[i].querySelector("canvas"), i, 220,
          220 / Slides.slideAspect(), state.split ? "left" : "full");
        cells[i].querySelector("canvas").style.width = "100%";
        cells[i].querySelector("canvas").style.height = "auto";
      }
    }
    highlightOverview();
  }

  function highlightOverview() {
    const cells = el("ov-grid").children;
    for (let i = 0; i < cells.length; i++) {
      cells[i].classList.toggle("current", i === state.page);
    }
  }

  // ---- Clock & timer -------------------------------------------------------

  const two = (n) => String(n).padStart(2, "0");
  let timerRunning = false;
  let timerAccum = 0;      // seconds accumulated while stopped
  let timerStarted = null; // Date when (re)started

  const elapsedSeconds = () =>
    timerAccum + (timerRunning ? Math.floor((Date.now() - timerStarted) / 1000) : 0);

  function tick() {
    const now = new Date();
    el("clock").textContent = `${two(now.getHours())}:${two(now.getMinutes())}`;
    const s = elapsedSeconds();
    el("timer").textContent =
      s >= 3600 ? `${Math.floor(s / 3600)}:${two(Math.floor((s % 3600) / 60))}:${two(s % 60)}`
                : `${two(Math.floor(s / 60))}:${two(s % 60)}`;
  }
  setInterval(tick, 500);
  tick();

  function toggleTimer() {
    if (timerRunning) {
      timerAccum = elapsedSeconds();
      timerRunning = false;
    } else {
      timerStarted = Date.now();
      timerRunning = true;
    }
    el("timer").classList.toggle("stopped", !timerRunning);
    el("timer-btn").textContent = timerRunning ? "Stop" : "Start";
  }
  function resetTimer() {
    timerAccum = 0;
    timerStarted = Date.now();
    tick();
  }
  el("timer-btn").addEventListener("click", toggleTimer);
  el("timer-reset").addEventListener("click", resetTimer);

  // ---- Keyboard ------------------------------------------------------------

  document.addEventListener("keydown", (e) => {
    if (!state.path || e.ctrlKey || e.metaKey || e.altKey) return;
    switch (e.key) {
      case "ArrowRight": case " ": case "PageDown": next(); break;
      case "ArrowLeft": case "PageUp": previous(); break;
      case "Home": goTo(0); break;
      case "End": goTo(state.count - 1); break;
      case "b": case "B": toggleBlackout(); break;
      case "g": case "G": toggleOverview(); break;
      case "w": case "W": toggleBoard(); break;
      case "z": case "Z": undoStroke(); break;
      case "c": case "C": clearBoard(); break;
      case "t": case "T": toggleTimer(); break;
      case "r": case "R": resetTimer(); break;
      case "f": case "F": invoke("toggle_audience_fullscreen"); break;
      case "Escape":
        if (el("overview").classList.contains("active")) toggleOverview();
        else if (boardActive()) toggleBoard();
        else if (state.blackout) toggleBlackout();
        break;
      default: return;
    }
    e.preventDefault();
  });

  // ---- Drag & drop (whole window, like the macOS home screen) --------------

  listen("tauri://drag-enter", () => el("dropzone").classList.add("targeted"));
  listen("tauri://drag-leave", () => el("dropzone").classList.remove("targeted"));
  listen("tauri://drag-drop", (event) => {
    el("dropzone").classList.remove("targeted");
    const paths = event.payload.paths || [];
    if (paths.length > 0 && !state.path) openAny(paths[0]);
  });

  // ---- Audience handshake --------------------------------------------------

  // The audience window asks for the deck once its scripts are up.
  listen("audience-ready", () => {
    if (state.path) { pushDeck(); pushState(); pushBoard(); }
  });

  // ---- Startup -------------------------------------------------------------

  el("open-btn").addEventListener("click", async () => {
    const path = await invoke("pick_file");
    if (path) openAny(path);
  });

  invoke("latex_engine").then((engine) => {
    el("latex-dot").className = "dot " + (engine ? "ok" : "warn");
    el("latex-status").textContent = engine
      ? `LaTeX ready — ${engine}`
      : "LaTeX not found — install TeX Live to compile .tex";
  });

  invoke("office_engine").then((engine) => {
    el("office-dot").className = "dot " + (engine ? "ok" : "warn");
    el("office-status").textContent = engine
      ? "LibreOffice ready — .pptx supported"
      : "LibreOffice not found — needed to open .pptx";
  });

  el("version").textContent = "BeamerPresenter 4.12 · Linux";
  renderRecents();
})();
