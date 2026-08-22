use std::fs;
use std::path::{Path, PathBuf};
use std::process::Command;

/// Reads a text file as UTF-8, falling back to Latin-1 (like the macOS app's
/// TexNotes reader) so older .tex files still parse.
fn read_text_lossy(path: &Path) -> Option<String> {
    let bytes = fs::read(path).ok()?;
    match String::from_utf8(bytes) {
        Ok(s) => Some(s),
        Err(e) => Some(e.into_bytes().iter().map(|&b| b as char).collect()),
    }
}

/// Native "Open" dialog (via the XDG portal, so it matches the desktop theme).
#[tauri::command]
async fn pick_file() -> Option<String> {
    rfd::AsyncFileDialog::new()
        .add_filter("Presentations", &["pdf", "tex"])
        .pick_file()
        .await
        .map(|f| f.path().to_string_lossy().into_owned())
}

#[tauri::command]
fn file_exists(path: String) -> bool {
    Path::new(&path).is_file()
}

/// Text of a file (for .tex / .nav parsing in the frontend); None if unreadable.
#[tauri::command]
fn read_text(path: String) -> Option<String> {
    read_text_lossy(Path::new(&path))
}

/// The .tex files worth trying for `\note{}` extraction: same base name first,
/// then the rest of the PDF's folder alphabetically (mirrors the macOS app).
#[tauri::command]
fn tex_candidates(pdf_path: String) -> Vec<String> {
    let pdf = PathBuf::from(&pdf_path);
    let same = pdf.with_extension("tex");
    let mut others: Vec<PathBuf> = pdf
        .parent()
        .and_then(|dir| fs::read_dir(dir).ok())
        .map(|it| {
            it.filter_map(|e| e.ok().map(|e| e.path()))
                .filter(|p| {
                    p.extension().is_some_and(|e| e.eq_ignore_ascii_case("tex")) && *p != same
                })
                .collect()
        })
        .unwrap_or_default();
    others.sort();
    std::iter::once(same)
        .chain(others)
        .filter(|p| p.is_file())
        .map(|p| p.to_string_lossy().into_owned())
        .collect()
}

#[derive(serde::Serialize)]
pub struct CompileResult {
    pub ok: bool,
    pub pdf_path: Option<String>,
    pub log: String,
}

/// Compiles a .tex next to itself using the first LaTeX tool found
/// (latexmk → pdflatex → xelatex → lualatex). Returns the sibling PDF path.
#[tauri::command]
fn compile_tex(tex_path: String) -> CompileResult {
    let tex = PathBuf::from(&tex_path);
    let dir = tex.parent().unwrap_or(Path::new("."));
    let engines: [(&str, &[&str]); 4] = [
        ("latexmk", &["-pdf", "-interaction=nonstopmode", "-halt-on-error"]),
        ("pdflatex", &["-interaction=nonstopmode", "-halt-on-error"]),
        ("xelatex", &["-interaction=nonstopmode", "-halt-on-error"]),
        ("lualatex", &["-interaction=nonstopmode", "-halt-on-error"]),
    ];
    let Some((engine, args)) = engines
        .iter()
        .find(|(name, _)| which(name).is_some())
        .copied()
    else {
        return CompileResult {
            ok: false,
            pdf_path: None,
            log: "No LaTeX found — install TeX Live (e.g. texlive-latex-extra) to compile .tex files.".into(),
        };
    };

    // pdflatex & friends need two passes for stable refs; latexmk loops itself.
    let passes = if engine == "latexmk" { 1 } else { 2 };
    let mut log = String::new();
    for _ in 0..passes {
        match Command::new(engine).args(args).arg(&tex).current_dir(dir).output() {
            Ok(out) => {
                log = String::from_utf8_lossy(&out.stdout).into_owned()
                    + &String::from_utf8_lossy(&out.stderr);
                if !out.status.success() {
                    return CompileResult { ok: false, pdf_path: None, log: tail(&log, 40) };
                }
            }
            Err(e) => {
                return CompileResult { ok: false, pdf_path: None, log: e.to_string() };
            }
        }
    }
    let pdf = tex.with_extension("pdf");
    if pdf.is_file() {
        CompileResult { ok: true, pdf_path: Some(pdf.to_string_lossy().into_owned()), log: String::new() }
    } else {
        CompileResult { ok: false, pdf_path: None, log: tail(&log, 40) }
    }
}

/// Which LaTeX engine (if any) is installed — shown on the home screen.
#[tauri::command]
fn latex_engine() -> Option<String> {
    ["latexmk", "pdflatex", "xelatex", "lualatex"]
        .iter()
        .find(|name| which(name).is_some())
        .map(|s| s.to_string())
}

fn which(name: &str) -> Option<PathBuf> {
    std::env::var_os("PATH").and_then(|paths| {
        std::env::split_paths(&paths)
            .map(|d| d.join(name))
            .find(|p| p.is_file())
    })
}

fn tail(s: &str, lines: usize) -> String {
    let all: Vec<&str> = s.lines().collect();
    let start = all.len().saturating_sub(lines);
    all[start..].join("\n")
}

// ---- Audience window control -----------------------------------------------

use tauri::Manager;

/// Shows the audience window. With a second monitor it moves there and goes
/// full screen; on a single monitor it stays a normal window (the user can
/// toggle full screen with `F` — mirrors the macOS default behaviour).
#[tauri::command]
fn show_audience(app: tauri::AppHandle) {
    let Some(audience) = app.get_webview_window("audience") else { return };
    if let Some(external) = second_monitor(&app) {
        let _ = audience.set_position(external.position().to_owned());
        let _ = audience.set_fullscreen(true);
    }
    let _ = audience.show();
    // Keep the console focused — presenting shouldn't steal the keyboard.
    if let Some(presenter) = app.get_webview_window("presenter") {
        let _ = presenter.set_focus();
    }
}

#[tauri::command]
fn hide_audience(app: tauri::AppHandle) {
    if let Some(audience) = app.get_webview_window("audience") {
        let _ = audience.set_fullscreen(false);
        let _ = audience.hide();
    }
}

/// Toggles audience full screen; returns the new state.
#[tauri::command]
fn toggle_audience_fullscreen(app: tauri::AppHandle) -> bool {
    let Some(audience) = app.get_webview_window("audience") else { return false };
    let now = !audience.is_fullscreen().unwrap_or(false);
    let _ = audience.set_fullscreen(now);
    now
}

/// A monitor other than the presenter's — where the audience belongs.
fn second_monitor(app: &tauri::AppHandle) -> Option<tauri::Monitor> {
    let presenter = app.get_webview_window("presenter")?;
    let current = presenter.current_monitor().ok().flatten();
    let monitors = presenter.available_monitors().ok()?;
    if monitors.len() < 2 {
        return None;
    }
    monitors
        .into_iter()
        .find(|m| current.as_ref().map(|c| c.position() != m.position()).unwrap_or(true))
}

pub fn run() {
    tauri::Builder::default()
        .invoke_handler(tauri::generate_handler![
            pick_file,
            file_exists,
            read_text,
            tex_candidates,
            compile_tex,
            latex_engine,
            show_audience,
            hide_audience,
            toggle_audience_fullscreen
        ])
        .run(tauri::generate_context!())
        .expect("error while running BeamerPresenter");
}
