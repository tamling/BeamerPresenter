import SwiftUI
import UIKit

/// A thin wrapper around `UIActivityViewController` so the exported PDF can be
/// saved to Files, AirDropped, mailed, etc.
struct ShareSheet: UIViewControllerRepresentable {
    let items: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }
    func updateUIViewController(_ controller: UIActivityViewController, context: Context) {}
}
