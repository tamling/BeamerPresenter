import Foundation
import Dispatch
#if canImport(Glibc)
import Glibc
#elseif canImport(Darwin)
import Darwin
#endif

/// Hardened launching of the external tools the app runs on user files (LaTeX,
/// LibreOffice, unzip): pure argument / environment builders that close the
/// known injection paths, and a runner with a time limit, a cancel switch and a
/// bounded output buffer. Foundation only, so it can be unit-tested on Linux.
public enum SafeProcess {

    // MARK: - LaTeX

    /// Command-line arguments to compile `texURL` with `engine` ("latexmk",
    /// "pdflatex", "xelatex"), run in the file's own folder.
    /// `-norc` stops latexmk from loading a project's `latexmkrc` (Perl, i.e.
    /// code); `-no-shell-escape` blocks `\write18`. The file is passed as
    /// `./name.tex`, so a file named `-foo.tex` can't be parsed as an option —
    /// not as an absolute path, which `openin_any=p` (see `latexEnvironment`)
    /// refuses to read (latexmk also resets `TEXMFOUTPUT`, the only exemption).
    public static func latexArguments(engine: String, texURL: URL) -> [String] {
        let file = "./" + texURL.lastPathComponent
        if engine == "latexmk" {
            return ["-norc", "-pdf", "-interaction=nonstopmode", "-halt-on-error",
                    "-no-shell-escape", file]
        }
        return ["-no-shell-escape", "-interaction=nonstopmode", "-halt-on-error", file]
    }

    /// The environment for a LaTeX run: `base` with TeX's file access locked
    /// down (`openin_any`/`openout_any` paranoid: no dotfiles, no `..`, no
    /// absolute paths, i.e. TeX itself reads and writes nothing outside the
    /// project folder except its own trees; no shell escape) and `searchDirs`
    /// put first on `PATH`, because latexmk shells out to pdflatex etc.
    ///
    /// Not covered: symbolic links. The paranoid mode checks only the name TeX
    /// is given, so a project link `s.tex -> ../secret` (read) or
    /// `talk.log -> ~/.zshrc` (write) still leaves the folder — see
    /// `linksLeavingFolder`, which callers check before compiling.
    /// Nor tools outside kpathsea. latexmk may run biber, which
    /// ignores these variables, so a biblatex `\addbibresource{/abs/path}` (or a
    /// URL) is still read. LuaTeX's `os.remove` / `lfs.*` aren't covered either,
    /// which is why `Dependencies` never picks lualatex. The build confirmation
    /// remains the main safeguard.
    public static func latexEnvironment(base: [String: String], searchDirs: [String]) -> [String: String] {
        var env = base
        // Drop empty / relative PATH entries: they mean "the current directory",
        // which is the (untrusted) project folder.
        let inherited = (env["PATH"] ?? "").split(separator: ":").map(String.init)
            .filter { $0.hasPrefix("/") }
        env["PATH"] = (searchDirs + inherited).joined(separator: ":")
        env["openin_any"] = "p"
        env["openout_any"] = "p"
        env["shell_escape"] = "f"
        return env
    }

    /// What `linksLeavingFolder` found.
    public struct LinkScan: Equatable {
        /// Paths (relative to the folder) of symbolic links that resolve outside it.
        public var escaping: [String] = []
        /// `false` when the folder could not be checked in full (too large, too
        /// deep, or unreadable) — treat that as suspicious too.
        public var complete = true

        public init(escaping: [String] = [], complete: Bool = true) {
            self.escaping = escaping
            self.complete = complete
        }
    }

    /// Lists the symbolic links inside `folder` (recursively, bounded by
    /// `maxDepth` and `maxEntries`) that point outside it — including dangling
    /// ones, whose target TeX would create when writing. Such a link lets a
    /// LaTeX run read or overwrite files elsewhere despite `openin_any=p`
    /// (see `latexEnvironment`). Links are not followed into, and hidden
    /// entries are checked too: kpathsea only refuses dot *file* names.
    public static func linksLeavingFolder(_ folder: URL, maxDepth: Int = 12,
                                          maxEntries: Int = 20_000) -> LinkScan {
        var scan = LinkScan()
        guard let root = resolvedPath(folder.path) else { return LinkScan(complete: false) }
        let fm = FileManager.default
        var seen = 0

        func isInside(_ path: String) -> Bool {
            root == "/" || path == root || path.hasPrefix(root + "/")
        }

        func visit(_ dir: String, relative: String, depth: Int) {
            guard scan.complete else { return }
            guard let names = try? fm.contentsOfDirectory(atPath: dir) else {
                scan.complete = false
                return
            }
            for name in names.sorted() {
                seen += 1
                guard seen <= maxEntries else { scan.complete = false; return }
                let path = dir + "/" + name
                let rel = relative.isEmpty ? name : relative + "/" + name
                // attributesOfItem uses lstat, so a link reports itself, not its target.
                let type = (try? fm.attributesOfItem(atPath: path))?[.type] as? FileAttributeType
                if type == .typeSymbolicLink {
                    if let target = resolvedPath(path), isInside(target) { continue }
                    scan.escaping.append(rel)
                } else if type == .typeDirectory {
                    guard depth < maxDepth else { scan.complete = false; return }
                    visit(path, relative: rel, depth: depth + 1)
                    guard scan.complete else { return }
                }
            }
        }
        visit(root, relative: "", depth: 1)
        return scan
    }

    /// `path` with every symbolic link resolved, also when the file (or a
    /// link's target) doesn't exist yet: the existing part is resolved and the
    /// rest appended. `nil` when it can't be worked out (link loop, a trailing
    /// `..` below a missing folder) — callers treat that as "outside".
    static func resolvedPath(_ path: String, hops: Int = 0) -> String? {
        guard hops < 64 else { return nil }
        if let real = realpath(path, nil) {
            defer { free(real) }
            return String(cString: real)
        }
        let name = (path as NSString).lastPathComponent
        let parentPath = (path as NSString).deletingLastPathComponent
        guard !name.isEmpty, name != ".", name != "..", name != "/",
              !parentPath.isEmpty, parentPath != path,
              let parent = resolvedPath(parentPath, hops: hops + 1) else { return nil }
        let joined = (parent as NSString).appendingPathComponent(name)
        // A dangling link: follow it by hand, relative to its own folder.
        if let dest = try? FileManager.default.destinationOfSymbolicLink(atPath: joined) {
            let next = dest.hasPrefix("/") ? dest : (parent as NSString).appendingPathComponent(dest)
            return resolvedPath(next, hops: hops + 1)
        }
        return joined
    }

    // MARK: - LibreOffice

    /// Arguments to convert `input` to PDF in `outputDirectory`, using the
    /// throwaway profile `profileDirectory` so no settings or macros from the
    /// user's own LibreOffice profile apply (and a running LibreOffice doesn't
    /// swallow the job).
    public static func sofficeArguments(input: URL, outputDirectory: URL, profileDirectory: URL) -> [String] {
        let profile = URL(fileURLWithPath: profileDirectory.path, isDirectory: true)
        return ["-env:UserInstallation=\(profile.absoluteString)", "--headless",
                "--convert-to", "pdf", "--outdir", outputDirectory.path, input.path]
    }

    /// A fresh, not yet existing folder under the temp directory — e.g. for a
    /// throwaway LibreOffice profile. The caller removes it afterwards.
    public static func throwawayDirectory(prefix: String) -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("\(prefix)-\(UUID().uuidString)", isDirectory: true)
    }

    // MARK: - Running

    /// What `run` observed.
    public struct RunResult {
        public var status: Int32          // exit status (or signal number); -1 if it never started
        public var output: String         // the last `outputLimit` bytes of stdout + stderr
        public var timedOut = false       // stopped because the time limit expired
        public var cancelled = false      // stopped through the cancel token
        public var launchError: String?   // why the process could not be started
    }

    /// A thread-safe stop switch for `run` (e.g. the compile HUD's Cancel button).
    public final class CancelToken: @unchecked Sendable {
        private let lock = NSLock()
        private var cancelled = false

        public init() {}

        public var isCancelled: Bool {
            lock.lock(); defer { lock.unlock() }
            return cancelled
        }

        public func cancel() {
            lock.lock(); defer { lock.unlock() }
            cancelled = true
        }
    }

    /// Keeps only the last `limit` bytes appended — the end of a log is the
    /// interesting part, and a chatty process must not grow memory unbounded.
    private final class TailBuffer: @unchecked Sendable {
        private let lock = NSLock()
        private var data = Data()
        private let limit: Int

        init(limit: Int) { self.limit = max(0, limit) }

        func append(_ chunk: Data) {
            lock.lock(); defer { lock.unlock() }
            data.append(chunk)
            if data.count > limit { data = Data(data.suffix(limit)) }
        }

        var contents: Data {
            lock.lock(); defer { lock.unlock() }
            return data
        }
    }

    /// Runs `executable` synchronously — call it off the main actor. stdout and
    /// stderr share one pipe that a background thread drains while the process
    /// runs (so it can never block on a full pipe). The process is terminated
    /// when `timeout` expires or `cancel` fires, and killed if it is still
    /// running 2 s later.
    public static func run(executable: URL, arguments: [String], environment: [String: String]?,
                    currentDirectory: URL?, timeout: TimeInterval,
                    outputLimit: Int = 64 * 1024, cancel: CancelToken? = nil) -> RunResult {
        let process = Process()
        process.executableURL = executable
        process.arguments = arguments
        if let environment { process.environment = environment }
        if let currentDirectory { process.currentDirectoryURL = currentDirectory }
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe
        process.standardInput = FileHandle.nullDevice   // nothing may wait for a keypress

        let exited = DispatchSemaphore(value: 0)
        process.terminationHandler = { _ in exited.signal() }

        do { try process.run() } catch {
            return RunResult(status: -1, output: "", launchError: error.localizedDescription)
        }

        let buffer = TailBuffer(limit: outputLimit)
        let drained = DispatchSemaphore(value: 0)
        let reader = pipe.fileHandleForReading
        Thread.detachNewThread {
            while let chunk = try? reader.read(upToCount: 64 * 1024), !chunk.isEmpty {
                buffer.append(chunk)
            }
            drained.signal()
        }

        // Foundation normally starts the child as the leader of its own process
        // group; then stop signals go to the whole group, so grandchildren
        // (latexmk → pdflatex, soffice → soffice.bin) are stopped too.
        let pid = process.processIdentifier
        let ownGroup = getpgid(pid) == pid
        func stop(_ signal: Int32) {
            if ownGroup { kill(-pid, signal) }
            if process.isRunning { kill(pid, signal) }
        }

        let deadline = Date().addingTimeInterval(timeout)
        var timedOut = false
        var cancelled = false
        var killAt: Date?             // set once we asked the process to stop
        while exited.wait(timeout: .now() + .milliseconds(100)) == .timedOut {
            if let due = killAt {
                if Date() >= due {
                    stop(SIGKILL)     // ignored SIGTERM
                    killAt = .distantFuture
                }
                continue
            }
            if cancel?.isCancelled == true {
                cancelled = true
            } else if Date() >= deadline {
                timedOut = true
            }
            if cancelled || timedOut {
                stop(SIGTERM)
                killAt = Date().addingTimeInterval(2)
            }
        }
        process.waitUntilExit()   // already exited; makes terminationStatus valid

        // A grandchild can keep the pipe open after its parent is gone; don't
        // wait for it forever — and after a stop, don't leave it running.
        if drained.wait(timeout: .now() + 2) == .timedOut, ownGroup, cancelled || timedOut {
            kill(-pid, SIGKILL)
            _ = drained.wait(timeout: .now() + 1)
        }
        return RunResult(status: process.terminationStatus,
                         output: String(decoding: buffer.contents, as: UTF8.self),
                         timedOut: timedOut, cancelled: cancelled)
    }
}
