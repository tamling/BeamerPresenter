import SwiftUI
import UIKit

/// A transparent touch-capture layer used while the pen tool is on. Built on
/// UIKit so it can do what SwiftUI gestures can't: tell Apple Pencil from a
/// finger (palm rejection), sample coalesced touches for smooth lines, and read
/// pressure to vary the stroke width.
struct InkingOverlay: UIViewRepresentable {
    var pencilOnly: Bool
    var baseWidth: CGFloat
    let onBegin: (CGPoint, CGFloat) -> Void
    let onMove: (CGPoint, CGFloat) -> Void
    let onEnd: () -> Void

    func makeUIView(context: Context) -> InkingView {
        let view = InkingView()
        view.backgroundColor = .clear
        view.isMultipleTouchEnabled = true
        apply(to: view)
        return view
    }

    func updateUIView(_ view: InkingView, context: Context) { apply(to: view) }

    private func apply(to view: InkingView) {
        view.pencilOnly = pencilOnly
        view.baseWidth = baseWidth
        view.onBegin = onBegin
        view.onMove = onMove
        view.onEnd = onEnd
    }
}

final class InkingView: UIView {
    var pencilOnly = false
    var baseWidth: CGFloat = 0.004
    var onBegin: ((CGPoint, CGFloat) -> Void)?
    var onMove: ((CGPoint, CGFloat) -> Void)?
    var onEnd: (() -> Void)?

    private var activeTouch: UITouch?

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard activeTouch == nil else { return }
        // Prefer a pencil; reject fingers entirely in pencil-only mode (palm rejection).
        let pencil = touches.first { $0.type == .pencil }
        let candidate = pencil ?? (pencilOnly ? nil : touches.first)
        guard let touch = candidate else { return }
        activeTouch = touch
        onBegin?(unit(touch), width(for: touch))
    }

    override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard let active = activeTouch, touches.contains(active) else { return }
        // Coalesced touches give every sample the display missed between frames.
        for t in event?.coalescedTouches(for: active) ?? [active] {
            onMove?(unit(t), width(for: t))
        }
    }

    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) { finish(touches) }
    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent?) { finish(touches) }

    private func finish(_ touches: Set<UITouch>) {
        guard let active = activeTouch, touches.contains(active) else { return }
        onEnd?()
        activeTouch = nil
    }

    private func unit(_ touch: UITouch) -> CGPoint {
        let p = touch.location(in: self)
        return CGPoint(x: min(max(0, p.x / max(bounds.width, 1)), 1),
                       y: min(max(0, p.y / max(bounds.height, 1)), 1))
    }

    /// Pressure-scaled width: full range for the Pencil, a neutral value otherwise.
    private func width(for touch: UITouch) -> CGFloat {
        let maxForce = touch.maximumPossibleForce
        let norm: CGFloat = (touch.type == .pencil && maxForce > 0) ? touch.force / maxForce : 0.5
        return baseWidth * (0.35 + 1.3 * norm)
    }
}
