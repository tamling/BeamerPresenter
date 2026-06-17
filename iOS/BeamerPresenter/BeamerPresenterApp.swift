import SwiftUI

@main
struct BeamerPresenterApp: App {
    @StateObject private var model = PresentationModel()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(model)
                .preferredColorScheme(.dark)
                .statusBarHidden(model.document != nil)
        }
    }
}
