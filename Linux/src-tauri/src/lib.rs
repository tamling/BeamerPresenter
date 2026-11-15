use std::fs;
use std::path::{Path, PathBuf};
use std::process::Command;

/// Cap for a note source beside a deck — real .tex/.nav files are tiny, and a
/// huge (or sparse) one next to an untrusted deck would exhaust memory.
const MAX_TEXT_BYTES: u64 = 16 * 1024 * 1024;

/// Reads a text file as UTF-8, falling back to Latin-1 (like the macOS app's
/// TexNotes reader) so older .tex files still parse. None above the cap.
fn read_text_lossy(path: &Path) -> Option<String> {
    use std::io::Read;
    let mut bytes = Vec::new();
    fs::File::open(path)
        .ok()?
        .take(MAX_TEXT_BYTES + 1)
        .read_to_end(&mut bytes)
        .ok()?;
    if bytes.len() as u64 > MAX_TEXT_BYTES {
        return None;
    }
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

/// Text of a file (for .tex / .nav parsing in the frontend); None if unreadable
/// or not one of those two note sources — the only ones the frontend asks for,
/// so the command is not a read of anything else on the machine.
#[tauri::command]
fn read_text(path: String) -> Option<String> {
    let path = Path::new(&path);
    if !path.extension().is_some_and(|e| {
        e.eq_ignore_ascii_case("tex") || e.eq_ignore_ascii_case("nav")
    }) {
        return None;
    }
    read_text_lossy(path)
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

/// How long LaTeX may run before it is killed — a heavy Beamer deck can take
/// minutes, but a non-terminating one would otherwise hang the open for ever.
const LATEX_TIMEOUT: std::time::Duration = std::time::Duration::from_secs(300);

/// Compiles a .tex next to itself using the first LaTeX tool found
/// (latexmk → pdflatex → xelatex → lualatex). Returns the sibling PDF path.
#[tauri::command(async)]
fn compile_tex(tex_path: String) -> CompileResult {
    let tex = PathBuf::from(&tex_path);
    let dir = tex.parent().unwrap_or(Path::new("."));
    // The deck's own folder is the working directory, so the tools must not
    // take instructions from it: -norc keeps latexmk from running a latexmkrc
    // shipped beside the .tex as Perl, -no-shell-escape disarms \write18.
    let engines: [(&str, &[&str]); 4] = [
        ("latexmk", &["-norc", "-pdf", "-interaction=nonstopmode", "-halt-on-error"]),
        ("pdflatex", &["-no-shell-escape", "-interaction=nonstopmode", "-halt-on-error"]),
        ("xelatex", &["-no-shell-escape", "-interaction=nonstopmode", "-halt-on-error"]),
        ("lualatex", &["-no-shell-escape", "-interaction=nonstopmode", "-halt-on-error"]),
    ];
    let Some((engine, args, exe)) = engines
        .iter()
        .find_map(|(name, args)| which(name).map(|exe| (*name, *args, exe)))
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
        let mut cmd = Command::new(&exe);
        cmd.args(args);
        // -no-shell-escape cannot reach the engine latexmk spawns itself, so the
        // limits go in the environment, where kpathsea picks them up for the whole
        // tree: shell escape held at TeX Live's restricted default even where
        // texmf.cnf opened it, no reading dot files, no writing outside the folder.
        cmd.env("shell_escape", "p")
            .env("openin_any", "r")
            .env("openout_any", "p");
        // -norc dropped the user's own latexmk config along with the deck's; put
        // just theirs back, by explicit path.
        if engine == "latexmk" {
            for rc in user_latexmk_rc() {
                cmd.arg("-r").arg(rc);
            }
        }
        cmd.arg(&tex).current_dir(dir);
        match run_with_timeout(cmd, LATEX_TIMEOUT) {
            Ok(Some(out)) => {
                log = String::from_utf8_lossy(&out.stdout).into_owned()
                    + &String::from_utf8_lossy(&out.stderr);
                if !out.status.success() {
                    let note = if engine == "latexmk" { local_rc_note(dir) } else { String::new() };
                    return CompileResult {
                        ok: false,
                        pdf_path: None,
                        log: tail(&log, 40) + &note,
                    };
                }
            }
            Ok(None) => {
                return CompileResult {
                    ok: false,
                    pdf_path: None,
                    log: format!(
                        "{engine} ran for more than {} s and was stopped.",
                        LATEX_TIMEOUT.as_secs()
                    ),
                };
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
        let note = if engine == "latexmk" { local_rc_note(dir) } else { String::new() };
        CompileResult { ok: false, pdf_path: None, log: tail(&log, 40) + &note }
    }
}

/// How long LibreOffice may run before it is killed (a cold headless start is
/// already slow, so this is generous).
const OFFICE_TIMEOUT: std::time::Duration = std::time::Duration::from_secs(120);

/// Converts a PowerPoint/ODP to a sibling PDF via headless LibreOffice.
#[tauri::command(async)]
fn convert_office(path: String) -> CompileResult {
    let source = PathBuf::from(&path);
    let dir = source.parent().unwrap_or(Path::new("."));
    let Some((_, soffice)) = office_binary() else {
        return CompileResult {
            ok: false,
            pdf_path: None,
            log: "LibreOffice not found — install it (e.g. libreoffice-impress) to open .pptx.".into(),
        };
    };
    let mut cmd = Command::new(&soffice);
    // Own profile: with the user's default one a headless run hands off to an
    // already-open LibreOffice, exits 0 and writes no PDF.
    cmd.arg(format!("-env:UserInstallation=file://{}", soffice_profile().display()))
        .args(["--headless", "--convert-to", "pdf", "--outdir"])
        .arg(dir)
        .arg(&source);
    match run_with_timeout(cmd, OFFICE_TIMEOUT) {
        Ok(Some(out)) => {
            let pdf = source.with_extension("pdf");
            if out.status.success() && pdf.is_file() {
                CompileResult { ok: true, pdf_path: Some(pdf.to_string_lossy().into_owned()), log: String::new() }
            } else {
                let log = String::from_utf8_lossy(&out.stdout).into_owned()
                    + &String::from_utf8_lossy(&out.stderr);
                let log = tail(&log, 40);
                // soffice often fails silently — say something rather than
                // handing the frontend an empty explanation.
                let log = if log.trim().is_empty() {
                    "LibreOffice produced no PDF from this file.".into()
                } else {
                    log
                };
                CompileResult { ok: false, pdf_path: None, log }
            }
        }
        Ok(None) => CompileResult {
            ok: false,
            pdf_path: None,
            log: format!(
                "LibreOffice ran for more than {} s and was stopped.",
                OFFICE_TIMEOUT.as_secs()
            ),
        },
        Err(e) => CompileResult { ok: false, pdf_path: None, log: e.to_string() },
    }
}

/// Where the headless conversions keep their LibreOffice profile — per user,
/// since /tmp is shared.
fn soffice_profile() -> PathBuf {
    if let Some(runtime) = std::env::var_os("XDG_RUNTIME_DIR") {
        return PathBuf::from(runtime).join("beamerpresenter-soffice");
    }
    use std::os::unix::fs::MetadataExt;
    let uid = fs::metadata("/proc/self").map(|m| m.uid()).unwrap_or(0);
    std::env::temp_dir().join(format!("beamerpresenter-soffice-{uid}"))
}

/// Which LibreOffice binary (if any) is installed — shown on the home screen.
#[tauri::command]
fn office_engine() -> Option<String> {
    office_binary().map(|(name, _)| name.to_string())
}

/// The name LibreOffice is installed under, and the executable it resolves to.
fn office_binary() -> Option<(&'static str, PathBuf)> {
    ["soffice", "libreoffice"]
        .into_iter()
        .find_map(|name| which(name).map(|exe| (name, exe)))
}

/// Which LaTeX engine (if any) is installed — shown on the home screen.
#[tauri::command]
fn latex_engine() -> Option<String> {
    ["latexmk", "pdflatex", "xelatex", "lualatex"]
        .iter()
        .find(|name| which(name).is_some())
        .map(|s| s.to_string())
}

/// The absolute path of `name` in PATH. Only executable files count, and empty
/// PATH entries are skipped, so the tools are started by path and never
/// re-resolved against the deck's own folder.
fn which(name: &str) -> Option<PathBuf> {
    std::env::var_os("PATH").and_then(|paths| {
        std::env::split_paths(&paths)
            .filter(|dir| dir.is_absolute())
            .map(|dir| dir.join(name))
            .find(|p| is_executable(p))
    })
}

/// The user's own latexmk config files, if they have any. `-norc` drops every rc
/// file including theirs, so these go back explicitly — unlike one sitting beside
/// an untrusted deck, which stays dropped.
fn user_latexmk_rc() -> Vec<PathBuf> {
    let home = std::env::var_os("HOME").map(PathBuf::from);
    let config = std::env::var_os("XDG_CONFIG_HOME")
        .map(PathBuf::from)
        .or_else(|| home.as_ref().map(|h| h.join(".config")));
    [
        config.map(|c| c.join("latexmk/latexmkrc")),
        home.map(|h| h.join(".latexmkrc")),
    ]
    .into_iter()
    .flatten()
    .filter(|p| p.is_file())
    .collect()
}

/// A line for a failed latexmk log when the deck brought its own rc file, which is
/// deliberately not run. Empty when there is none.
fn local_rc_note(dir: &Path) -> String {
    let found = ["latexmkrc", ".latexmkrc"]
        .into_iter()
        .find(|name| dir.join(name).is_file());
    match found {
        Some(name) => format!(
            "\n\nNote: this folder contains a {name}, which BeamerPresenter does not run — \
             latexmk rc files are Perl, and a deck's folder is not a safe place to take code \
             from. If you trust it, compile the deck once in a terminal and open the PDF instead."
        ),
        None => String::new(),
    }
}

fn is_executable(path: &Path) -> bool {
    use std::os::unix::fs::PermissionsExt;
    fs::metadata(path)
        .map(|m| m.is_file() && m.permissions().mode() & 0o111 != 0)
        .unwrap_or(false)
}

/// Runs a child with a deadline, draining both pipes so a chatty tool can't
/// block on a full one. `Ok(None)` means it ran out of time and was killed.
fn run_with_timeout(
    mut cmd: Command,
    limit: std::time::Duration,
) -> std::io::Result<Option<std::process::Output>> {
    use std::io::Read;
    use std::os::unix::process::CommandExt;
    use std::process::Stdio;
    // Its own process group, so a timeout also reaches the engines it spawned.
    let mut child = cmd
        .stdin(Stdio::null())
        .stdout(Stdio::piped())
        .stderr(Stdio::piped())
        .process_group(0)
        .spawn()?;
    let out_pipe = child.stdout.take();
    let err_pipe = child.stderr.take();
    let out_reader = std::thread::spawn(move || {
        let mut buf = Vec::new();
        if let Some(mut pipe) = out_pipe {
            let _ = pipe.read_to_end(&mut buf);
        }
        buf
    });
    let err_reader = std::thread::spawn(move || {
        let mut buf = Vec::new();
        if let Some(mut pipe) = err_pipe {
            let _ = pipe.read_to_end(&mut buf);
        }
        buf
    });
    let deadline = std::time::Instant::now() + limit;
    let status = loop {
        if let Some(status) = child.try_wait()? {
            break Some(status);
        }
        if std::time::Instant::now() >= deadline {
            kill_group(&mut child);
            break None;
        }
        std::thread::sleep(std::time::Duration::from_millis(50));
    };
    let stdout = out_reader.join().unwrap_or_default();
    let stderr = err_reader.join().unwrap_or_default();
    Ok(status.map(|status| std::process::Output { status, stdout, stderr }))
}

/// Kills a child and whatever it spawned — it leads its own process group, so
/// the negative pid covers the whole tree.
fn kill_group(child: &mut std::process::Child) {
    use std::process::Stdio;
    let _ = Command::new("kill")
        .arg("-KILL")
        .arg(format!("-{}", child.id()))
        .stdout(Stdio::null())
        .stderr(Stdio::null())
        .status();
    let _ = child.kill();
    let _ = child.wait();
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

/// Caps for an untrusted .pptx: one part, and all of its notes together. Real
/// decks are orders of magnitude smaller; a deflate bomb is not.
const MAX_ZIP_ENTRY_BYTES: u64 = 8 * 1024 * 1024;
const MAX_NOTES_BYTES: usize = 32 * 1024 * 1024;

/// Speaker notes per slide (in presentation order, "" where a slide has none)
/// for the .pptx with the same base name as the given PDF.
#[tauri::command(async)]
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

    let mut used = 0usize;
    slide_files
        .iter()
        .map(|slide_file| {
            if used >= MAX_NOTES_BYTES {
                return String::new();
            }
            let name = slide_file.rsplit('/').next().unwrap_or(slide_file);
            let Some(slide_rels) = zip_text(&mut archive, &format!("ppt/slides/_rels/{name}.rels"))
            else { return String::new() };
            let Some(notes_target) = relationships(&slide_rels)
                .into_values()
                .find(|t| t.contains("notesSlide"))
            else { return String::new() };
            let notes_name = notes_target.rsplit('/').next().unwrap_or(&notes_target).to_string();
            let notes = zip_text(&mut archive, &format!("ppt/notesSlides/{notes_name}"))
                .map(|xml| notes_text(&xml))
                .unwrap_or_default();
            used += notes.len();
            notes
        })
        .collect()
}

fn zip_text(archive: &mut zip::ZipArchive<fs::File>, name: &str) -> Option<String> {
    use std::io::Read;
    let entry = archive.by_name(name).ok()?;
    if entry.size() > MAX_ZIP_ENTRY_BYTES {
        return None;
    }
    let mut s = String::new();
    // The size above is the archive's own claim, so bound the read as well —
    // and give up rather than hand a truncated part to the parsers below.
    entry.take(MAX_ZIP_ENTRY_BYTES + 1).read_to_string(&mut s).ok()?;
    if s.len() as u64 > MAX_ZIP_ENTRY_BYTES {
        return None;
    }
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

/// Quits the app (used by the console's exit dialog).
#[tauri::command]
fn quit_app(app: tauri::AppHandle) {
    app.exit(0);
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
            toggle_audience_fullscreen,
            quit_app
        ])
        .run(tauri::generate_context!())
        .expect("error while running BeamerPresenter");
}
