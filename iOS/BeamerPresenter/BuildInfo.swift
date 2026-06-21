// Build stamp. Overwritten at build time by the Xcode pre-build script (see
// iOS/project.yml); the committed value is a fallback for fresh checkouts.
//
// The id is "<YYMMDD>-<commit>", where the commit is the short hash as a decimal.
enum BuildInfo {
    static let id = "260621-1901175"
}
