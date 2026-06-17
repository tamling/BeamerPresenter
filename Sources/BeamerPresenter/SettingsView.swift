import SwiftUI
import AppKit

/// Native macOS settings (⌘,): the folder shown on the start screen, and the
/// audience black-screen behaviour. Values persist via `@AppStorage`.
struct SettingsView: View {
    @AppStorage(Prefs.startBlackedOut) private var startBlackedOut = true
    @AppStorage(Prefs.blackScreenMessage) private var blackMessage = ""

    var body: some View {
        Form {
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
        .frame(width: 460, height: 280)
    }
}

/// UserDefaults keys shared across the app.
enum Prefs {
    static let startBlackedOut = "startBlackedOut"
    static let blackScreenMessage = "blackScreenMessage"
}
