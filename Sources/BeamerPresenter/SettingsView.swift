import SwiftUI
import AppKit
import ServiceManagement

/// Native macOS settings (⌘,): general (menu bar icon + login item), and the
/// audience black-screen behaviour. Values persist via `@AppStorage`.
struct SettingsView: View {
    @AppStorage(Prefs.startBlackedOut) private var startBlackedOut = true
    @AppStorage(Prefs.blackScreenMessage) private var blackMessage = ""
    @AppStorage(Prefs.showStatusItem) private var showStatusItem = true

    var body: some View {
        Form {
            Section("General") {
                Toggle("Open at login", isOn: loginItem)
                Toggle("Show icon in the menu bar", isOn: $showStatusItem)
                    .onChange(of: showStatusItem) { _ in
                        NotificationCenter.default.post(name: .statusItemPrefChanged, object: nil)
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
        .frame(width: 460, height: 320)
    }

    /// Reflects and toggles the macOS "open at login" item for the app bundle.
    private var loginItem: Binding<Bool> {
        Binding(
            get: { SMAppService.mainApp.status == .enabled },
            set: { enabled in
                do {
                    if enabled { try SMAppService.mainApp.register() }
                    else { try SMAppService.mainApp.unregister() }
                } catch {
                    NSLog("BeamerPresenter: login item change failed: \(error)")
                }
            }
        )
    }
}

/// UserDefaults keys shared across the app.
enum Prefs {
    static let startBlackedOut = "startBlackedOut"
    static let blackScreenMessage = "blackScreenMessage"
    static let showStatusItem = "showStatusItem"
}
