import SwiftUI

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
                .statusBarHidden(model.document != nil)
                .task { external.start(model: model) }
        }
    }
}
