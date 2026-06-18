import SwiftUI

extension Color {
    /// The app's brand colour, matching the logo's indigo→violet gradient.
    static let brand = Color(red: 0.486, green: 0.361, blue: 0.965)   // #7C5CF6
    static let brandIndigo = Color(red: 0.329, green: 0.408, blue: 1.0)   // #5468FF
    static let brandViolet = Color(red: 0.545, green: 0.361, blue: 0.965) // #8B5CF6
}

extension LinearGradient {
    /// The logo's indigo→violet gradient, for headers and primary buttons.
    static let brand = LinearGradient(colors: [.brandIndigo, .brandViolet],
                                      startPoint: .topLeading, endPoint: .bottomTrailing)
}

@main
struct BeamerPresenterApp: App {
    @StateObject private var model = PresentationModel()
    @StateObject private var external = ExternalDisplayManager()
    @StateObject private var presenterLink = RemoteLink(role: .presenter)

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(model)
                .environmentObject(external)
                .environmentObject(presenterLink)
                .preferredColorScheme(.dark)
                .tint(.brand)
                .statusBarHidden(model.document != nil)
                .task { external.start(model: model) }
        }
    }
}
