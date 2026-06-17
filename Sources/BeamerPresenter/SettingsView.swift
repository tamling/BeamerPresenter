import SwiftUI
import AppKit

/// Native macOS settings (⌘,): the folder shown on the start screen, and the
/// audience black-screen behaviour. Values persist via `@AppStorage`.
struct SettingsView: View {
    @AppStorage(Prefs.browseFolder) private var browseFolderPath = ""
    @AppStorage(Prefs.startBlackedOut) private var startBlackedOut = true
    @AppStorage(Prefs.blackScreenMessage) private var blackMessage = ""

    var body: some View {
        Form {
            Section("Library") {
                LabeledContent("Start-screen folder") {
                    HStack(spacing: 8) {
                        Text(displayPath)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .truncationMode(.middle)
                        Spacer(minLength: 8)
                        Button("Choose…", action: chooseFolder)
                        if !browseFolderPath.isEmpty {
                            Button("Default") { browseFolderPath = "" }
                        }
                    }
                }
            }

            Section("Audience screen") {
                Toggle("Start with a black audience screen", isOn: $startBlackedOut)
                TextField("Black-screen message",
                          text: $blackMessage,
                          prompt: Text("e.g. Back in 5 minutes"))
                Text("Shown centered on the black screen — leave empty to show the clock instead.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section {
                LabeledContent("Version", value: AppInfo.versionLine)
                LabeledContent("Author", value: AppInfo.author)
            }
        }
        .formStyle(.grouped)
        .frame(width: 480, height: 340)
    }

    private var displayPath: String {
        browseFolderPath.isEmpty ? "Documents (default)" : (browseFolderPath as NSString).abbreviatingWithTildeInPath
    }

    private func chooseFolder() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.prompt = "Choose"
        if panel.runModal() == .OK, let url = panel.url {
            browseFolderPath = url.path
        }
    }
}

/// UserDefaults keys shared across the app.
enum Prefs {
    static let browseFolder = "browseFolderPath"
    static let startBlackedOut = "startBlackedOut"
    static let blackScreenMessage = "blackScreenMessage"

    /// The folder whose PDFs are listed on the start screen (Documents by default).
    static var browseFolderURL: URL {
        let path = UserDefaults.standard.string(forKey: browseFolder) ?? ""
        if !path.isEmpty { return URL(fileURLWithPath: path, isDirectory: true) }
        return FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first
            ?? FileManager.default.homeDirectoryForCurrentUser
    }
}
