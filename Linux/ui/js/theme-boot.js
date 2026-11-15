// Apply the saved appearance before first paint (no dark→light flash).
// Lives in its own file rather than inline so the window's Content-Security-Policy
// can forbid inline script.
try {
  if (localStorage.getItem("appearance") === "paper") {
    document.documentElement.dataset.theme = "paper";
  }
} catch (e) {}
