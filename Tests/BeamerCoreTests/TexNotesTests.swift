import XCTest
@testable import BeamerCore

final class TexNotesTests: XCTestCase {

    func testNotesAreAssignedToTheirFrames() {
        let tex = #"""
        \documentclass{beamer}
        \begin{document}
        \begin{frame}{One}
          Hello \note{First \textbf{note}} % \note{commented out}
        \end{frame}
        \begin{frame}{Two}
        \end{frame}
        \frame{Three \note<2>[item]{Third note}}
        \end{document}
        """#
        let notes = TexNotes.framesWithNotes(in: tex)
        XCTAssertEqual(notes, [0: "First note", 2: "Third note"])
    }

    func testNavRangesAreZeroBased() {
        let nav = #"""
        \headcommand {\beamer@framepages {1}{1}}
        \headcommand {\beamer@framepages {2}{4}}
        """#
        XCTAssertEqual(TexNotes.framePages(nav), [0...0, 1...3])
    }

    func testUnclosedNoteFinishesQuickly() {
        let body = String(repeating: "x \\note{y ", count: 100_000)   // ~1 MB
        let tex = "\\begin{frame}\\note{" + body
        let start = Date()
        let notes = TexNotes.framesWithNotes(in: tex)
        XCTAssertLessThan(Date().timeIntervalSince(start), 1)
        XCTAssertTrue(notes.isEmpty)
    }

    // MARK: - File loading

    private var dir: URL!

    override func setUpWithError() throws {
        dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("TexNotesTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: dir)
    }

    func testLoadUsesSiblingTexAndNav() throws {
        let pdf = dir.appendingPathComponent("talk.pdf")
        try Data().write(to: pdf)
        try #"\begin{frame}\note{A}\end{frame}\begin{frame}\note{B}\end{frame}"#
            .write(to: dir.appendingPathComponent("talk.tex"), atomically: true, encoding: .utf8)
        try #"\beamer@framepages {1}{2}\beamer@framepages {3}{3}"#
            .write(to: dir.appendingPathComponent("talk.nav"), atomically: true, encoding: .utf8)
        XCTAssertEqual(TexNotes.load(forPDF: pdf, pageCount: 3), [0: "A", 1: "A", 2: "B"])
        // Pages beyond the PDF are dropped.
        XCTAssertEqual(TexNotes.load(forPDF: pdf, pageCount: 1), [0: "A"])
    }

    func testOversizedTexIsSkipped() throws {
        let pdf = dir.appendingPathComponent("big.pdf")
        try Data().write(to: pdf)
        var tex = #"\begin{frame}\note{Hidden}\end{frame}"# + "\n%"
        tex += String(repeating: "x", count: 5 * 1024 * 1024 + 10)
        try tex.write(to: dir.appendingPathComponent("big.tex"), atomically: true, encoding: .utf8)
        XCTAssertEqual(TexNotes.load(forPDF: pdf, pageCount: 1), [:])

        // The same note in a small file is found (fallback to another .tex).
        try #"\begin{frame}\note{Small}\end{frame}"#
            .write(to: dir.appendingPathComponent("other.tex"), atomically: true, encoding: .utf8)
        XCTAssertEqual(TexNotes.load(forPDF: pdf, pageCount: 1), [0: "Small"])
    }
}
