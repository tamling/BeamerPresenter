import SwiftUI
import UniformTypeIdentifiers

/// The shared pen palette, used by the toolbar and Settings.
enum AppColors {
    static let palette: [(name: String, color: Color)] = [
        ("Red", .red), ("Orange", .orange), ("Yellow", .yellow),
        ("Green", .green), ("Blue", .blue), ("White", .white)
    ]
    static func color(_ name: String) -> Color {
        palette.first { $0.name == name }?.color ?? .red
    }
    static func name(_ color: Color) -> String {
        palette.first { $0.color == color }?.name ?? "Red"
    }
}

/// App-wide preferences, persisted in `UserDefaults` via `@AppStorage`.
struct SettingsView: View {
    @Environment(\.dismiss) private var dismiss

    @AppStorage("pencilOnly") private var pencilOnly = false
    @AppStorage("defaultPenColorName") private var penColorName = "Red"
    @AppStorage("defaultPenWidth") private var penWidth = 0.004
    @AppStorage("startBlackedOut") private var startBlackedOut = false
    @AppStorage("blackoutMessage") private var blackoutMessage = ""
    @AppStorage("blackoutShowClock") private var blackoutShowClock = true
    @AppStorage("blackoutImagePath") private var blackoutImagePath = ""

    @State private var importingImage = false

    private let weights: [(String, Double)] = [("Thin", 0.0025), ("Medium", 0.004), ("Thick", 0.007)]

    var body: some View {
        NavigationStack {
            Form {
                Section("Pen") {
                    Toggle("Apple Pencil only (palm rejection)", isOn: $pencilOnly)
                    Picker("Default colour", selection: $penColorName) {
                        ForEach(AppColors.palette, id: \.name) { item in
                            Label {
                                Text(item.name)
                            } icon: {
                                Circle().fill(item.color).frame(width: 14, height: 14)
                            }.tag(item.name)
                        }
                    }
                    Picker("Default line weight", selection: $penWidth) {
                        ForEach(weights, id: \.1) { Text($0.0).tag($0.1) }
                    }
                }

                Section("Black-out screen") {
                    Toggle("Start presentations blacked out", isOn: $startBlackedOut)
                    Toggle("Show clock", isOn: $blackoutShowClock)
                    Picker("Message", selection: $blackoutMessage) {
                        Text("None").tag("")
                        ForEach(BlackoutView.presets, id: \.self) { Text($0).tag($0) }
                    }
                    TextField("Custom message", text: $blackoutMessage)

                    if blackoutImagePath.isEmpty {
                        Button { importingImage = true } label: {
                            Label("Choose background image…", systemImage: "photo")
                        }
                    } else {
                        HStack {
                            Label("Background image set", systemImage: "photo.fill")
                            Spacer()
                            Button("Remove", role: .destructive) { clearImage() }
                        }
                    }
                }

                Section("About") {
                    LabeledContent("App", value: "BeamerPresenter for iPadOS")
                    LabeledContent("Version", value: appVersion)
                }
            }
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
            .fileImporter(isPresented: $importingImage,
                          allowedContentTypes: [.image]) { result in
                if case .success(let url) = result { importImage(url) }
            }
        }
    }

    private var appVersion: String {
        let v = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
        let b = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "1"
        return "\(v) (\(b))"
    }

    /// Copy the chosen image into Application Support so it survives relaunches.
    private func importImage(_ url: URL) {
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }
        guard let data = try? Data(contentsOf: url) else { return }
        let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let dest = dir.appendingPathComponent("blackout-bg.img")
        if (try? data.write(to: dest)) != nil { blackoutImagePath = dest.path }
    }

    private func clearImage() {
        if !blackoutImagePath.isEmpty { try? FileManager.default.removeItem(atPath: blackoutImagePath) }
        blackoutImagePath = ""
    }
}
