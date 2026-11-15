// Loads the vendored pdf.js and publishes it as `window.pdfjsLib`, then tells the
// page it is usable. Shared by index.html and audience.html, and kept out of the
// HTML so the window's Content-Security-Policy can forbid inline script.
//
// Both URLs are resolved against this module's own location, so the file works
// from any page depth and does not depend on the document's base URL.
import * as pdfjs from "../vendor/pdfjs/pdf.min.mjs";

pdfjs.GlobalWorkerOptions.workerSrc =
  new URL("../vendor/pdfjs/pdf.worker.min.mjs", import.meta.url).href;
window.pdfjsLib = pdfjs;
window.dispatchEvent(new Event("pdfjs-ready"));
