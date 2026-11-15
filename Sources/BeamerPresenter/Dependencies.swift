import Foundation

/// Startup checks and on-demand LaTeX compilation. A LaTeX install lets the app
/// compile a `.tex` to its PDF; nothing here is required to present a PDF.
enum Dependencies {
    /// LaTeX engines we consider, in order of preference.
    private static let latexTools = ["latexmk", "pdflatex", "lualatex", "xelatex"]
    /// Common install locations (MacTeX / TeX Live, Homebrew).
    static let searchDirs = [
        "/Library/TeX/texbin", "/usr/texbin",
        "/opt/homebrew/bin", "/usr/local/bin", "/usr/bin",
    ]

    /// The first LaTeX engine found on disk (name + full path), or `nil`.
    static func latexEngine() -> (name: String, path: String)? {
        let fm = FileManager.default
        for dir in searchDirs {
            for tool in latexTools {
                let path = "\(dir)/\(tool)"
                if fm.isExecutableFile(atPath: path) { return (tool, path) }
            }
        }
        return nil
    }

    /// LibreOffice's `soffice` binary, used to convert PowerPoint/ODP to PDF.
    static func soffice() -> String? {
        let candidates = [
            "/Applications/LibreOffice.app/Contents/MacOS/soffice",
            "/opt/homebrew/bin/soffice", "/usr/local/bin/soffice",
            "/Applications/OpenOffice.app/Contents/MacOS/soffice",
        ]
        return candidates.first { FileManager.default.isExecutableFile(atPath: $0) }
    }

    enum CompileResult {
        case success(URL)     // the produced PDF
        case failure(String)  // a (truncated) log to show
    }

    /// How long a child may run before we kill it. Generous on purpose: a first
    /// lualatex run on a figure-heavy deck legitimately takes minutes.
    private static let childTimeout: TimeInterval = 600
    /// How much of a child's output we hold on to while it runs.
    private static let logTailLimit = 64 * 1024

    /// The last `logTailLimit` bytes of a child's output, collected as it runs.
    private final class LogTail: @unchecked Sendable {
        private let lock = NSLock()
        private var data = Data()

        func append(_ chunk: Data) {
            lock.lock()
            data.append(chunk)
            let limit = Dependencies.logTailLimit
            if data.count > limit { data.removeFirst(data.count - limit) }
            lock.unlock()
        }

        /// Decoded leniently — the tail can start mid-character.
        var text: String {
            lock.lock()
            defer { lock.unlock() }
            return String(decoding: data, as: UTF8.self)
        }
    }

    /// Waits for `process` while draining `pipe`, and returns the log tail to show
    /// if it failed. Only the last bytes are kept, so a deck that floods its output
    /// cannot grow the app without bound, and a child that outlives `childTimeout`
    /// is killed instead of hanging the caller forever.
    private static func waitForOutput(_ process: Process, draining pipe: Pipe,
                                      name: String) -> String {
        let handle = pipe.fileHandleForReading
        let tail = LogTail()
        // Drained off this thread: latexmk's own children can keep the pipe open
        // after it is killed, so the read must never be what we wait on.
        let drained = DispatchSemaphore(value: 0)
        DispatchQueue.global().async {
            while let chunk = try? handle.read(upToCount: 1 << 16), !chunk.isEmpty {
                tail.append(chunk)
            }
            drained.signal()
        }
        var timedOut = false
        if drained.wait(timeout: .now() + childTimeout) == .timedOut {
            timedOut = true
            if process.isRunning { process.terminate() }
            if drained.wait(timeout: .now() + 5) == .timedOut, process.isRunning {
                _ = kill(process.processIdentifier, SIGKILL)
            }
        }
        process.waitUntilExit()
        let log = String(tail.text.suffix(1500))
        return timedOut
            ? "Stopped \(name) after \(Int(childTimeout / 60)) minutes.\n\n" + log
            : log
    }

    /// Converts a presentation file (`.pptx`, `.ppt`, `.odp`, …) to PDF in its own
    /// folder using LibreOffice. Runs synchronously — call it off the main actor.
    static func convertToPDF(_ input: URL, soffice: String) -> CompileResult {
        let dir = input.deletingLastPathComponent()
        let process = Process()
        process.executableURL = URL(fileURLWithPath: soffice)
        // Own profile: with the user's default one a headless run hands the job to
        // an already-open LibreOffice, which exits 0 and writes no PDF.
        process.arguments = ["-env:UserInstallation=\(sofficeProfile().absoluteString)",
                             "--headless", "--convert-to", "pdf", "--outdir", dir.path, input.path]

        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe
        do { try process.run() } catch {
            return .failure("Could not start LibreOffice: \(error.localizedDescription)")
        }
        let log = waitForOutput(process, draining: pipe, name: "LibreOffice")

        let pdf = dir.appendingPathComponent(input.deletingPathExtension().lastPathComponent + ".pdf")
        if FileManager.default.fileExists(atPath: pdf.path) { return .success(pdf) }
        // soffice can exit silently (a running instance took the request, a stale
        // profile lock), so never hand back an empty log.
        if log.isEmpty {
            return .failure("LibreOffice exited with status \(process.terminationStatus) "
                            + "and produced no PDF.")
        }
        return .failure(log)
    }

    /// Where the headless conversions keep their LibreOffice profile. Stable, so
    /// the profile is built once rather than on every open. `temporaryDirectory`
    /// is already per-user on macOS.
    private static func sofficeProfile() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("beamerpresenter-soffice", isDirectory: true)
    }

    /// A fresh, empty folder to run latexmk from, or `nil` if it can't be made.
    private static func scratchDir() -> URL? {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("latexmk-\(UUID().uuidString)")
        do { try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true) }
        catch { return nil }
        return dir
    }

    /// `-r` arguments putting the user's own latexmk config back after `-norc`.
    private static func userRCArguments() -> [String] {
        let fm = FileManager.default
        let home = fm.homeDirectoryForCurrentUser
        let config = ProcessInfo.processInfo.environment["XDG_CONFIG_HOME"]
            .map { URL(fileURLWithPath: $0) } ?? home.appendingPathComponent(".config")
        return [config.appendingPathComponent("latexmk/latexmkrc"),
                home.appendingPathComponent(".latexmkrc")]
            .filter { fm.isReadableFile(atPath: $0.path) }
            .flatMap { ["-r", $0.path] }
    }

    /// Compiles `texURL` with the given engine, writing beside the file. Runs
    /// synchronously — call it off the main actor.
    static func compile(texURL: URL, engine: (name: String, path: String)) -> CompileResult {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: engine.path)
        // A downloaded deck's own folder is attacker-controlled, and latexmk runs a
        // `latexmkrc`/`.latexmkrc` found in its working directory as Perl. So latexmk
        // works in an empty scratch folder and `-cd` moves it into the deck for the
        // compile itself; `-norc` (first, as latexmk requires) backs that up, and the
        // user's own rc file goes back in explicitly. The direct engines read no rc
        // file, so they keep working in the deck's folder as before.
        let scratch = engine.name == "latexmk" ? scratchDir() : nil
        defer { if let scratch { try? FileManager.default.removeItem(at: scratch) } }
        if engine.name == "latexmk" {
            // latexmk builds the engine command as a shell string, so a path the
            // shell would expand is both unusable and unsafe.
            if texURL.path.contains(where: { $0 == "$" || $0 == "`" }) {
                return .failure("latexmk cannot be run on a path containing $ or `. "
                                + "Move the file, or compile it by hand.")
            }
            process.currentDirectoryURL = scratch ?? texURL.deletingLastPathComponent()
            process.arguments = ["-norc"] + userRCArguments()
                + ["-cd", "-pdf", "-interaction=nonstopmode", "-halt-on-error", texURL.path]
        } else {
            process.currentDirectoryURL = texURL.deletingLastPathComponent()
            // Anchored, so a deck named `-foo.tex` cannot pose as an option.
            let file = "./" + texURL.lastPathComponent
            process.arguments = ["-interaction=nonstopmode", "-halt-on-error", file]
        }

        // latexmk shells out to pdflatex etc., so make sure the TeX bin is on PATH.
        var env = ProcessInfo.processInfo.environment
        env["PATH"] = searchDirs.joined(separator: ":") + ":" + (env["PATH"] ?? "")
        // kpathsea takes these from the environment, so they bind the engines latexmk
        // spawns too: hold shell escape at TeX Live's restricted default even where
        // texmf.cnf opened it up, and keep a deck from reading dot files or writing
        // outside its own folder.
        env["shell_escape"] = "p"
        env["openin_any"] = "r"
        env["openout_any"] = "p"
        process.environment = env

        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe

        do { try process.run() } catch {
            return .failure("Could not start \(engine.name): \(error.localizedDescription)")
        }
        let log = waitForOutput(process, draining: pipe, name: engine.name)

        let pdf = texURL.deletingPathExtension().appendingPathExtension("pdf")
        // Beamer can exit non-zero yet still produce a usable PDF, so accept the
        // PDF whenever it exists.
        if FileManager.default.fileExists(atPath: pdf.path) { return .success(pdf) }

        // A deck that carries its own latexmkrc (a legitimate pattern for $pdf_mode
        // or custom dependencies) now builds without it, because running it would be
        // running the deck's own code. Say so, or the failure looks inexplicable.
        let skippedRC = engine.name == "latexmk" ? localRCNote(beside: texURL) : ""

        if log.isEmpty {
            return .failure("\(engine.name) exited with status \(process.terminationStatus) "
                            + "and produced no PDF." + skippedRC)
        }
        return .failure(log + skippedRC)
    }

    /// A line to append to a failed latexmk log when the deck brought its own rc
    /// file, which is deliberately not run. Empty when there is none.
    private static func localRCNote(beside texURL: URL) -> String {
        let dir = texURL.deletingLastPathComponent()
        let found = ["latexmkrc", ".latexmkrc"]
            .first { FileManager.default.isReadableFile(atPath: dir.appendingPathComponent($0).path) }
        guard let found else { return "" }
        return "\n\nNote: this folder contains a \(found), which BeamerPresenter does not run — "
            + "latexmk rc files are Perl, and a deck's folder is not a safe place to take code from. "
            + "If you trust it, compile the deck once in a terminal and open the PDF instead."
    }
}
