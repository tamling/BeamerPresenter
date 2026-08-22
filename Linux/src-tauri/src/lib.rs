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
        .add_filter("Presentations", &["pdf", "tex", "pptx", "ppt", "odp"])
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

/// Converts a PowerPoint/ODP to a sibling PDF via headless LibreOffice.
#[tauri::command]
fn convert_office(path: String) -> CompileResult {
    let source = PathBuf::from(&path);
    let dir = source.parent().unwrap_or(Path::new("."));
    let Some(soffice) = office_binary() else {
        return CompileResult {
            ok: false,
            pdf_path: None,
            log: "LibreOffice not found — install it (e.g. libreoffice-impress) to open .pptx.".into(),
        };
    };
    match Command::new(soffice)
        .args(["--headless", "--convert-to", "pdf", "--outdir"])
        .arg(dir)
        .arg(&source)
        .output()
    {
        Ok(out) => {
            let pdf = source.with_extension("pdf");
            if out.status.success() && pdf.is_file() {
                CompileResult { ok: true, pdf_path: Some(pdf.to_string_lossy().into_owned()), log: String::new() }
            } else {
                let log = String::from_utf8_lossy(&out.stdout).into_owned()
                    + &String::from_utf8_lossy(&out.stderr);
                CompileResult { ok: false, pdf_path: None, log: tail(&log, 40) }
            }
        }
        Err(e) => CompileResult { ok: false, pdf_path: None, log: e.to_string() },
    }
}

/// Which LibreOffice binary (if any) is installed — shown on the home screen.
#[tauri::command]
fn office_engine() -> Option<String> {
    office_binary().map(|s| s.to_string())
}

fn office_binary() -> Option<&'static str> {
    ["soffice", "libreoffice"]
        .into_iter()
        .find(|name| which(name).is_some())
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

// ---- PowerPoint speaker notes -----------------------------------------------
//
// A .pptx is a ZIP: slide order comes from ppt/presentation.xml
// (<p:sldIdLst>), each slide's _rels file points to its notes page
// (ppt/notesSlides/notesSlideN.xml), and the note text lives in that page's
// body-placeholder shape. Mirrors Sources/BeamerPresenter/PptxNotes.swift.

/// Speaker notes per slide (in presentation order, "" where a slide has none)
/// for the .pptx with the same base name as the given PDF.
#[tauri::command]
fn pptx_notes(pdf_path: String) -> Vec<String> {
    let pptx = PathBuf::from(&pdf_path).with_extension("pptx");
    let Ok(file) = fs::File::open(&pptx) else { return vec![] };
    let Ok(mut archive) = zip::ZipArchive::new(file) else { return vec![] };

    let Some(presentation) = zip_text(&mut archive, "ppt/presentation.xml") else { return vec![] };
    let Some(pres_rels) = zip_text(&mut archive, "ppt/_rels/presentation.xml.rels") else { return vec![] };
    let rel_targets = relationships(&pres_rels);

    let slide_re = regex::Regex::new(r#"<p:sldId\b[^>]*r:id="([^"]+)""#).unwrap();
    let slide_files: Vec<String> = slide_re
        .captures_iter(&presentation)
        .filter_map(|c| rel_targets.get(&c[1]).cloned()) // e.g. "slides/slide1.xml"
        .collect();

    slide_files
        .iter()
        .map(|slide_file| {
            let name = slide_file.rsplit('/').next().unwrap_or(slide_file);
            let Some(slide_rels) = zip_text(&mut archive, &format!("ppt/slides/_rels/{name}.rels"))
            else { return String::new() };
            let Some(notes_target) = relationships(&slide_rels)
                .into_values()
                .find(|t| t.contains("notesSlide"))
            else { return String::new() };
            let notes_name = notes_target.rsplit('/').next().unwrap_or(&notes_target).to_string();
            zip_text(&mut archive, &format!("ppt/notesSlides/{notes_name}"))
                .map(|xml| notes_text(&xml))
                .unwrap_or_default()
        })
        .collect()
}

fn zip_text(archive: &mut zip::ZipArchive<fs::File>, name: &str) -> Option<String> {
    use std::io::Read;
    let mut entry = archive.by_name(name).ok()?;
    let mut s = String::new();
    entry.read_to_string(&mut s).ok()?;
    Some(s)
}

/// `Id → Target` for every `<Relationship …/>`, attribute order independent.
fn relationships(xml: &str) -> std::collections::HashMap<String, String> {
    let element_re = regex::Regex::new(r"<Relationship\b[^>]*>").unwrap();
    let id_re = regex::Regex::new(r#"\bId="([^"]+)""#).unwrap();
    let target_re = regex::Regex::new(r#"\bTarget="([^"]+)""#).unwrap();
    element_re
        .find_iter(xml)
        .filter_map(|m| {
            let e = m.as_str();
            Some((
                id_re.captures(e)?[1].to_string(),
                target_re.captures(e)?[1].to_string(),
            ))
        })
        .collect()
}

/// The note text of a notes page: the `<p:sp>` shape whose placeholder is
/// `type="body"` — paragraphs (`<a:p>`) joined by newlines, runs (`<a:t>`)
/// concatenated, entities unescaped.
fn notes_text(xml: &str) -> String {
    let shape_re = regex::Regex::new(r"(?s)<p:sp>.*?</p:sp>").unwrap();
    let para_re = regex::Regex::new(r"(?s)<a:p>.*?</a:p>").unwrap();
    let run_re = regex::Regex::new(r"(?s)<a:t>(.*?)</a:t>").unwrap();
    for shape in shape_re.find_iter(xml) {
        if !shape.as_str().contains(r#"type="body""#) {
            continue;
        }
        let text = para_re
            .find_iter(shape.as_str())
            .map(|p| {
                run_re
                    .captures_iter(p.as_str())
                    .map(|c| unescape(&c[1]))
                    .collect::<String>()
            })
            .collect::<Vec<_>>()
            .join("\n");
        return text.trim().to_string();
    }
    String::new()
}

fn unescape(s: &str) -> String {
    s.replace("&lt;", "<")
        .replace("&gt;", ">")
        .replace("&quot;", "\"")
        .replace("&apos;", "'")
        .replace("&amp;", "&") // last, so &amp;lt; doesn't double-decode
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

#[cfg(test)]
mod tests {
    use super::*;
    use std::io::Write;

    /// Builds a minimal two-slide .pptx (second slide reordered first, notes on
    /// one slide only) and checks the whole extraction chain.
    #[test]
    fn extracts_pptx_notes_in_presentation_order() {
        let dir = std::env::temp_dir().join(format!("pptx-notes-test-{}", std::process::id()));
        fs::create_dir_all(&dir).unwrap();
        let pptx = dir.join("deck.pptx");
        let file = fs::File::create(&pptx).unwrap();
        let mut z = zip::ZipWriter::new(file);
        let o = zip::write::SimpleFileOptions::default();

        // Presentation order: slide2 first, then slide1.
        z.start_file("ppt/presentation.xml", o).unwrap();
        z.write_all(br#"<p:sldIdLst><p:sldId id="257" r:id="rIdB"/><p:sldId id="256" r:id="rIdA"/></p:sldIdLst>"#).unwrap();
        z.start_file("ppt/_rels/presentation.xml.rels", o).unwrap();
        z.write_all(br#"<Relationships><Relationship Id="rIdA" Target="slides/slide1.xml"/><Relationship Target="slides/slide2.xml" Id="rIdB"/></Relationships>"#).unwrap();
        // Only slide2 (shown first) has a notes page.
        z.start_file("ppt/slides/_rels/slide2.xml.rels", o).unwrap();
        z.write_all(br#"<Relationships><Relationship Id="rId9" Target="../notesSlides/notesSlide1.xml"/></Relationships>"#).unwrap();
        z.start_file("ppt/notesSlides/notesSlide1.xml", o).unwrap();
        z.write_all(br#"<p:sp><p:ph type="sldImg"/></p:sp><p:sp><p:nvSpPr><p:ph type="body" idx="1"/></p:nvSpPr><p:txBody><a:p><a:r><a:t>Greet the </a:t></a:r><a:r><a:t>audience &amp; smile</a:t></a:r></a:p><a:p><a:r><a:t>Second line</a:t></a:r></a:p></p:txBody></p:sp>"#).unwrap();
        z.finish().unwrap();

        let notes = pptx_notes(dir.join("deck.pdf").to_string_lossy().into_owned());
        fs::remove_dir_all(&dir).ok();

        assert_eq!(notes.len(), 2);
        assert_eq!(notes[0], "Greet the audience & smile\nSecond line");
        assert_eq!(notes[1], "");
    }
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
            convert_office,
            office_engine,
            pptx_notes,
            show_audience,
            hide_audience,
            toggle_audience_fullscreen
        ])
        .run(tauri::generate_context!())
        .expect("error while running BeamerPresenter");
}
