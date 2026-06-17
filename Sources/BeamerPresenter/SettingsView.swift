import SwiftUI
import AppKit
import ServiceManagement

/// Native macOS settings (⌘,): general (menu bar icon + login item) and the
/// audience black-screen behaviour. Values persist via `@AppStorage`.
struct SettingsView: View {
    @AppStorage(Prefs.startBlackedOut) private var startBlackedOut = true
    @AppStorage(Prefs.blackScreenMessage) private var blackMessage = ""
    @AppStorage(Prefs.blackScreenImage) private var blackImage = ""
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

            Section("Audience black screen") {
                Toggle("Start with a black audience screen", isOn: $startBlackedOut)

                HStack {
                    TextField("Message", text: $blackMessage, prompt: Text("e.g. Back in 5 minutes"))
                    Menu("Presets") {
                        ForEach(BlackScreen.presets, id: \.self) { preset in
                            Button(preset) { blackMessage = preset }
                        }
                    }
                    .fixedSize()
                    Button("Clear") { blackMessage = "" }
                        .disabled(blackMessage.isEmpty)
                }
                Text("The clock stays beneath the message; with no message it's shown large.")
                    .font(.caption).foregroundStyle(.secondary)

                LabeledContent("Background image") {
                    HStack(spacing: 8) {
                        Text(blackImage.isEmpty ? "None" : (blackImage as NSString).lastPathComponent)
                            .foregroundStyle(.secondary)
                            .lineLimit(1).truncationMode(.middle)
                        Spacer(minLength: 8)
                        Button("Choose…", action: chooseImage)
                        if !blackImage.isEmpty { Button("Clear") { blackImage = "" } }
                    }
                }
            }

            Section {
                LabeledContent("Version", value: AppInfo.versionLine)
                LabeledContent("Author", value: AppInfo.author)
            }
        }
        .formStyle(.grouped)
        .frame(width: 500, height: 430)
    }

    private func chooseImage() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.image]
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.prompt = "Choose"
        if panel.runModal() == .OK, let url = panel.url { blackImage = url.path }
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
    static let blackScreenImage = "blackScreenImage"
    static let showStatusItem = "showStatusItem"
}

/// Predefined "be right back" messages for the black screen.
enum BlackScreen {
    static let presets = [
        "Back in 5 minutes",
        "Back in 10 minutes",
        "Back in 15 minutes",
        "Short break",
        "Lunch break",
        "Back soon",
    ]
}
