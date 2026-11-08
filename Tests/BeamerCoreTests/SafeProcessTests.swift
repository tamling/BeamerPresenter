import XCTest
@testable import BeamerCore

final class SafeProcessTests: XCTestCase {

    // MARK: - Argument / environment builders

    func testLatexmkArgumentsAreLockedDown() {
        let tex = URL(fileURLWithPath: "/tmp/talk/slides.tex")
        let args = SafeProcess.latexArguments(engine: "latexmk", texURL: tex)
        XCTAssertTrue(args.contains("-norc"))
        XCTAssertTrue(args.contains("-no-shell-escape"))
        XCTAssertEqual(args.last, "./slides.tex")
    }

    func testPdflatexArgumentsBlockShellEscape() {
        let tex = URL(fileURLWithPath: "/tmp/talk/slides.tex")
        let args = SafeProcess.latexArguments(engine: "pdflatex", texURL: tex)
        XCTAssertTrue(args.contains("-no-shell-escape"))
        XCTAssertFalse(args.contains("-norc"))      // pdflatex has no such option
        XCTAssertEqual(args.last, "./slides.tex")
    }

    /// A file name that looks like an option must reach the tool as a single
    /// path argument, never as `-pdflatex=…` (which would make latexmk run it).
    func testOptionLookingFileNameStaysAPath() {
        let tex = URL(fileURLWithPath: "/tmp/talk/-pdflatex=sh evil.sh #.tex")
        for engine in ["latexmk", "pdflatex", "xelatex"] {
            let args = SafeProcess.latexArguments(engine: engine, texURL: tex)
            XCTAssertEqual(args.last, "./-pdflatex=sh evil.sh #.tex", engine)
            XCTAssertEqual(args.filter { $0.contains("evil") }.count, 1, engine)
            XCTAssertFalse(args.contains { $0.hasPrefix("-pdflatex") }, engine)
        }
    }

    func testLatexEnvironmentIsParanoidAndPrefixesPath() {
        let base = ["PATH": "/usr/bin:relative/bin::/bin", "HOME": "/home/u"]
        let env = SafeProcess.latexEnvironment(base: base, searchDirs: ["/Library/TeX/texbin"])
        XCTAssertEqual(env["openin_any"], "p")
        XCTAssertEqual(env["openout_any"], "p")
        XCTAssertEqual(env["shell_escape"], "f")
        XCTAssertEqual(env["HOME"], "/home/u")
        // Search dirs first; empty / relative entries (= the project folder) dropped.
        XCTAssertEqual(env["PATH"], "/Library/TeX/texbin:/usr/bin:/bin")
    }

    func testSofficeArgumentsUseThrowawayProfile() {
        let input = URL(fileURLWithPath: "/tmp/talk/deck.pptx")
        let out = URL(fileURLWithPath: "/tmp/out", isDirectory: true)
        let profile = SafeProcess.throwawayDirectory(prefix: "soffice-profile")
        let args = SafeProcess.sofficeArguments(input: input, outputDirectory: out,
                                                profileDirectory: profile)
        XCTAssertTrue(args.contains { $0.hasPrefix("-env:UserInstallation=file://") },
                      "\(args)")
        XCTAssertEqual(args.last, "/tmp/talk/deck.pptx")
        XCTAssertTrue(args.contains("--headless"))
    }

    // MARK: - run

    private let sh = URL(fileURLWithPath: "/bin/sh")

    func testTimeoutStopsProcess() {
        let start = Date()
        let r = SafeProcess.run(executable: sh, arguments: ["-c", "sleep 30"],
                                environment: nil, currentDirectory: nil, timeout: 1)
        XCTAssertTrue(r.timedOut)
        XCTAssertFalse(r.cancelled)
        XCTAssertLessThan(Date().timeIntervalSince(start), 4)
    }

    func testOutputKeepsOnlyTheTail() {
        let r = SafeProcess.run(executable: sh,
                                arguments: ["-c", "head -c 200000 /dev/zero | tr '\\0' a; printf END"],
                                environment: nil, currentDirectory: nil, timeout: 20,
                                outputLimit: 1000)
        XCTAssertFalse(r.timedOut)
        XCTAssertEqual(r.status, 0)
        XCTAssertEqual(r.output.utf8.count, 1000)
        XCTAssertTrue(r.output.hasSuffix("aaaEND"))
    }

    func testCancelTokenStopsProcess() {
        let token = SafeProcess.CancelToken()
        DispatchQueue.global().asyncAfter(deadline: .now() + 0.5) { token.cancel() }
        let start = Date()
        let r = SafeProcess.run(executable: sh, arguments: ["-c", "sleep 30"],
                                environment: nil, currentDirectory: nil, timeout: 60,
                                cancel: token)
        XCTAssertTrue(r.cancelled)
        XCTAssertFalse(r.timedOut)
        XCTAssertLessThan(Date().timeIntervalSince(start), 5)
    }

    func testLaunchErrorIsReported() {
        let r = SafeProcess.run(executable: URL(fileURLWithPath: "/nonexistent/tool"),
                                arguments: [], environment: nil, currentDirectory: nil,
                                timeout: 5)
        XCTAssertEqual(r.status, -1)
        XCTAssertNotNil(r.launchError)
    }
}
