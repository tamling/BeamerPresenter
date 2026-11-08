import Foundation
import BeamerCore

/// Startup checks and on-demand LaTeX compilation. A LaTeX install lets the app
/// compile a `.tex` to its PDF; nothing here is required to present a PDF.
enum Dependencies {
    /// LaTeX engines we consider, in order of preference. lualatex is left out
    /// on purpose: a document's `\directlua` can still delete or rename any
    /// user file (`os.remove`, `lfs.*`) — TeX's `openin_any`/`openout_any`
    /// don't cover those, and `--safer` breaks luaotfload's font cache.
    private static let latexTools = ["latexmk", "pdflatex", "xelatex"]
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
        case success(URL)                                // the produced PDF
        case failure(String)                             // a (truncated) log to show
        case timedOut(after: TimeInterval, log: String)  // stopped by the time limit
        case cancelled                                   // stopped by the user — nothing to report
    }

    /// Time limits for the external tools: a hung build must not hang the app.
    static let compileTimeout: TimeInterval = 180
    static let convertTimeout: TimeInterval = 120

    /// Converts a presentation file (`.pptx`, `.ppt`, `.odp`, …) to PDF in its own
    /// folder using LibreOffice. Runs synchronously — call it off the main actor.
    static func convertToPDF(_ input: URL, soffice: String,
                             cancel: SafeProcess.CancelToken? = nil) -> CompileResult {
        let dir = input.deletingLastPathComponent()
        // A throwaway profile, removed again afterwards (see SafeProcess).
        let profile = SafeProcess.throwawayDirectory(prefix: "soffice-profile")
        defer { try? FileManager.default.removeItem(at: profile) }

        let result = SafeProcess.run(
            executable: URL(fileURLWithPath: soffice),
            arguments: SafeProcess.sofficeArguments(input: input, outputDirectory: dir,
                                                    profileDirectory: profile),
            environment: nil, currentDirectory: nil,
            timeout: convertTimeout, cancel: cancel)
        if let error = result.launchError {
            return .failure("Could not start LibreOffice: \(error)")
        }
        if result.cancelled { return .cancelled }
        let log = String(result.output.suffix(1500))
        if result.timedOut { return .timedOut(after: convertTimeout, log: log) }

        let pdf = dir.appendingPathComponent(input.deletingPathExtension().lastPathComponent + ".pdf")
        if FileManager.default.fileExists(atPath: pdf.path) { return .success(pdf) }
        return .failure(log)
    }

    /// Compiles `texURL` with the given engine, in the file's own folder. Runs
    /// synchronously — call it off the main actor. TeX follows symbolic links,
    /// so callers check the folder with `SafeProcess.linksLeavingFolder` first.
    static func compile(texURL: URL, engine: (name: String, path: String),
                        cancel: SafeProcess.CancelToken? = nil) -> CompileResult {
        let result = SafeProcess.run(
            executable: URL(fileURLWithPath: engine.path),
            arguments: SafeProcess.latexArguments(engine: engine.name, texURL: texURL),
            // latexmk shells out to pdflatex etc., so the TeX bin goes on PATH;
            // the environment also locks down TeX's file access.
            environment: SafeProcess.latexEnvironment(base: ProcessInfo.processInfo.environment,
                                                      searchDirs: searchDirs),
            currentDirectory: texURL.deletingLastPathComponent(),
            timeout: compileTimeout, cancel: cancel)
        if let error = result.launchError {
            return .failure("Could not start \(engine.name): \(error)")
        }
        if result.cancelled { return .cancelled }
        let log = String(result.output.suffix(1500))
        if result.timedOut { return .timedOut(after: compileTimeout, log: log) }

        let pdf = texURL.deletingPathExtension().appendingPathExtension("pdf")
        // Beamer can exit non-zero yet still produce a usable PDF, so accept the
        // PDF whenever it exists.
        if FileManager.default.fileExists(atPath: pdf.path) { return .success(pdf) }
        return .failure(log)
    }
}
