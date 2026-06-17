import SwiftUI

extension Color {
    /// The app's brand colour, matching the logo's indigo→violet gradient.
    static let brand = Color(red: 0.486, green: 0.361, blue: 0.965)   // #7C5CF6
}

@main
struct BeamerPresenterApp: App {
    @StateObject private var model = PresentationModel()
    @StateObject private var external = ExternalDisplayManager()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(model)
                .environmentObject(external)
                .preferredColorScheme(.dark)
                .tint(.brand)
                .statusBarHidden(model.document != nil)
                .task { external.start(model: model) }
        }
    }
}
