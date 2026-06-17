import Foundation

/// Lightweight startup checks for optional external tools (a LaTeX install lets
/// you compile a `.tex` to its PDF). Nothing here is required to present a PDF.
enum Dependencies {
    /// Names of the LaTeX engines we consider, in order of preference.
    private static let latexTools = ["latexmk", "pdflatex", "lualatex", "xelatex"]
    /// Common install locations (MacTeX / TeX Live, Homebrew).
    private static let searchDirs = [
        "/Library/TeX/texbin", "/usr/texbin",
        "/opt/homebrew/bin", "/usr/local/bin", "/usr/bin",
    ]

    /// Returns the first LaTeX engine found on disk, or `nil` if none.
    static func latexEngine() -> String? {
        let fm = FileManager.default
        for dir in searchDirs {
            for tool in latexTools where fm.isExecutableFile(atPath: "\(dir)/\(tool)") {
                return tool
            }
        }
        return nil
    }
}
