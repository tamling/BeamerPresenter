// Audience window: renders the deck full-bleed and follows the presenter via
// events. On a split deck (notes on second screen) it shows the left half —
// the slide; the notes never reach the projector.

"use strict";

(() => {
  const { listen, emitTo } = window.__TAURI__.event;

  let split = false;
  let page = 0;
  let loaded = false;

  const el = (id) => document.getElementById(id);

  async function render() {
    if (!loaded) return;
    await Slides.render(el("slide"), page,
      window.innerWidth, window.innerHeight, split ? "left" : "full");
  }

  listen("deck", async (event) => {
    const { path, split: isSplit } = event.payload;
    split = isSplit;
    try {
      await Slides.open(path);
      loaded = true;
      render();
    } catch (e) {
      console.error("audience: could not open deck", e);
    }
  });

  listen("state", (event) => {
    const { page: p, blackout } = event.payload;
    page = p;
    el("blackout").classList.toggle("active", blackout);
    render();
  });

  let resizeTimer = null;
  window.addEventListener("resize", () => {
    clearTimeout(resizeTimer);
    resizeTimer = setTimeout(render, 120);
  });

  // Black-out clock.
  const two = (n) => String(n).padStart(2, "0");
  setInterval(() => {
    const now = new Date();
    el("black-clock").textContent = `${two(now.getHours())}:${two(now.getMinutes())}`;
  }, 1000);

  // Ask the presenter for the current deck (covers audience loading last).
  emitTo("presenter", "audience-ready", {});
})();
