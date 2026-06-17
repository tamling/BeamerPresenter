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

    enum CompileResult {
        case success(URL)     // the produced PDF
        case failure(String)  // a (truncated) log to show
    }

    /// Compiles `texURL` with the given engine, in the file's own folder. Runs
    /// synchronously — call it off the main actor.
    static func compile(texURL: URL, engine: (name: String, path: String)) -> CompileResult {
        let process = Process()
        process.currentDirectoryURL = texURL.deletingLastPathComponent()
        process.executableURL = URL(fileURLWithPath: engine.path)
        let file = texURL.lastPathComponent
        process.arguments = engine.name == "latexmk"
            ? ["-pdf", "-interaction=nonstopmode", "-halt-on-error", file]
            : ["-interaction=nonstopmode", "-halt-on-error", file]

        // latexmk shells out to pdflatex etc., so make sure the TeX bin is on PATH.
        var env = ProcessInfo.processInfo.environment
        env["PATH"] = searchDirs.joined(separator: ":") + ":" + (env["PATH"] ?? "")
        process.environment = env

        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe

        do { try process.run() } catch {
            return .failure("Could not start \(engine.name): \(error.localizedDescription)")
        }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()

        let pdf = texURL.deletingPathExtension().appendingPathExtension("pdf")
        // Beamer can exit non-zero yet still produce a usable PDF, so accept the
        // PDF whenever it exists.
        if FileManager.default.fileExists(atPath: pdf.path) { return .success(pdf) }

        let log = String(data: data, encoding: .utf8) ?? ""
        return .failure(String(log.suffix(1500)))
    }
}
