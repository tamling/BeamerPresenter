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
    notes: new Map() // pageIndex -> note text (plain-PDF decks only)
  };

  const el = (id) => document.getElementById(id);

  // ---- Audience sync -------------------------------------------------------

  function pushDeck() {
    emitTo("audience", "deck", { path: state.path, split: state.split });
  }
  function pushState() {
    emitTo("audience", "state", { page: state.page, blackout: state.blackout });
  }

  // ---- Home screen ---------------------------------------------------------

  const RECENTS_KEY = "recents";
  const loadRecents = () => JSON.parse(localStorage.getItem(RECENTS_KEY) || "[]");
  function addRecent(path) {
    const list = [path, ...loadRecents().filter((p) => p !== path)].slice(0, 5);
    localStorage.setItem(RECENTS_KEY, JSON.stringify(list));
  }

  function renderRecents() {
    const box = el("recents");
    box.innerHTML = "";
    for (const path of loadRecents()) {
      const name = path.split("/").pop();
      const dot = name.lastIndexOf(".");
      const cell = document.createElement("div");
      cell.className = "recent-card card";
      cell.innerHTML =
        `<div class="recent-ext"></div>
         <div style="min-width:0">
           <div class="recent-name"></div><div class="recent-path"></div>
         </div>`;
      cell.querySelector(".recent-ext").textContent =
        dot > 0 ? name.slice(dot + 1).toUpperCase() : "PDF";
      cell.querySelector(".recent-name").textContent = dot > 0 ? name.slice(0, dot) : name;
      cell.querySelector(".recent-path").textContent = path;
      cell.addEventListener("click", () => openAny(path));
      box.appendChild(cell);
    }
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
  // compiling it (mirrors the macOS open flow).
  async function openAny(path) {
    const lower = path.toLowerCase();
    if (lower.endsWith(".tex")) {
      const sibling = path.replace(/\.tex$/i, ".pdf");
      if (await invoke("file_exists", { path: sibling })) return openPDF(sibling);
      hud(`Compiling ${path.split("/").pop()}…`, "Running LaTeX…");
      const result = await invoke("compile_tex", { texPath: path });
      hideHud();
      if (result.ok) return openPDF(result.pdf_path);
      return hud("Could not compile the .tex", result.log, true);
    }
    if (lower.endsWith(".pdf")) return openPDF(path);
    hud("Unsupported file", "Drop a .pdf or a .tex.", true);
  }

  async function openPDF(path) {
    try {
      const info = await Slides.open(path);
      state.path = path;
      state.count = info.pageCount;
      state.split = info.split;
      state.page = 0;
      state.blackout = false;
      // Plain single-screen PDFs pull \note{} text from the .tex next to them;
      // split decks carry their notes on the page's right half already.
      state.notes = info.split ? new Map() : await TexNotes.load(path, info.pageCount);
    } catch (e) {
      return hud("Could not open PDF", String(e), true);
    }
    addRecent(path);
    el("deck-title").textContent = path.split("/").pop().replace(/\.pdf$/i, "");
    el("home").classList.add("hidden");
    el("console").classList.add("active");
    buildOverview();
    pushDeck();
    pushState();
    await invoke("show_audience");
    renderAll();
  }

  function closeDeck() {
    Slides.close();
    state.path = null;
    state.blackout = false;
    invoke("hide_audience");
    el("console").classList.remove("active");
    el("overview").classList.remove("active");
    el("home").classList.remove("hidden");
    renderRecents();
  }
  el("close-btn").addEventListener("click", closeDeck);

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
  }

  let resizeTimer = null;
  window.addEventListener("resize", () => {
    clearTimeout(resizeTimer);
    resizeTimer = setTimeout(renderAll, 120);
  });

  // ---- Navigation ----------------------------------------------------------

  function goTo(page) {
    const p = Math.max(0, Math.min(state.count - 1, page));
    if (p === state.page) return;
    state.page = p;
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
      case "t": case "T": toggleTimer(); break;
      case "r": case "R": resetTimer(); break;
      case "f": case "F": invoke("toggle_audience_fullscreen"); break;
      case "Escape":
        if (el("overview").classList.contains("active")) toggleOverview();
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
    if (state.path) { pushDeck(); pushState(); }
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

  el("version").textContent = "BeamerPresenter 4.0 · Linux";
  renderRecents();
})();
