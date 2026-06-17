import SwiftUI
import AppKit

/// Brief launch splash: app icon, name, tagline, and version with a small
/// activity spinner — shown for a moment at startup, then faded out.
struct SplashView: View {
    let icon: NSImage?
    let version: String

    var body: some View {
        VStack(spacing: 12) {
            if let icon {
                Image(nsImage: icon)
                    .resizable()
                    .interpolation(.high)
                    .frame(width: 96, height: 96)
                    .shadow(color: .black.opacity(0.25), radius: 8, y: 3)
            } else {
                Image(systemName: "rectangle.on.rectangle.angled")
                    .font(.system(size: 72))
                    .foregroundStyle(.tint)
            }

            Text(AppInfo.name)
                .font(.system(size: 26, weight: .bold))

            Text("Present LaTeX Beamer PDFs with speaker notes.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)

            VStack(spacing: 5) {
                HStack(spacing: 8) {
                    ProgressView().controlSize(.small)
                    Text(version)
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                }
                Text("by \(AppInfo.author)")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
            .padding(.top, 2)
        }
        .padding(28)
        .frame(width: 440, height: 280)
        .background(.regularMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .strokeBorder(.white.opacity(0.08), lineWidth: 1)
        )
    }
}

/// Small HUD shown while a `.tex` is compiled to PDF.
struct CompileHUD: View {
    let name: String

    var body: some View {
        VStack(spacing: 12) {
            ProgressView()
            Text("Compiling \(name)…").font(.headline)
            Text("Running LaTeX…").font(.caption).foregroundStyle(.secondary)
        }
        .padding(24)
        .frame(width: 320, height: 120)
        .background(.regularMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous)
            .strokeBorder(.white.opacity(0.08), lineWidth: 1))
    }
}
