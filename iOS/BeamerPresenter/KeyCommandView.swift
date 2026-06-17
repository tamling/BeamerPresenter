import SwiftUI
import UIKit

/// Captures hardware-keyboard keys so Bluetooth presenter remotes (and a paired
/// keyboard) can drive the deck. Most clickers emit Page Up / Page Down or the
/// arrow keys; we also map space and a black-out key. Implemented with
/// `UIKeyCommand` so it works on iPadOS 16 (SwiftUI's `onKeyPress` is iOS 17+).
struct KeyCommandView: UIViewControllerRepresentable {
    var onNext: () -> Void
    var onPrevious: () -> Void
    var onBlackout: () -> Void
    var onEscape: () -> Void

    func makeUIViewController(context: Context) -> KeyCommandController {
        let vc = KeyCommandController()
        apply(vc); return vc
    }
    func updateUIViewController(_ vc: KeyCommandController, context: Context) { apply(vc) }

    private func apply(_ vc: KeyCommandController) {
        vc.onNext = onNext
        vc.onPrevious = onPrevious
        vc.onBlackout = onBlackout
        vc.onEscape = onEscape
    }
}

final class KeyCommandController: UIViewController {
    var onNext: (() -> Void)?
    var onPrevious: (() -> Void)?
    var onBlackout: (() -> Void)?
    var onEscape: (() -> Void)?

    override var canBecomeFirstResponder: Bool { true }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        becomeFirstResponder()
    }

    override var keyCommands: [UIKeyCommand]? {
        let next = [UIKeyCommand.inputRightArrow, UIKeyCommand.inputDownArrow,
                    UIKeyCommand.inputPageDown, " "]
            .map { UIKeyCommand(input: $0, modifierFlags: [], action: #selector(goNext)) }
        let prev = [UIKeyCommand.inputLeftArrow, UIKeyCommand.inputUpArrow,
                    UIKeyCommand.inputPageUp]
            .map { UIKeyCommand(input: $0, modifierFlags: [], action: #selector(goPrevious)) }
        let other = [
            UIKeyCommand(input: "b", modifierFlags: [], action: #selector(blackout)),
            UIKeyCommand(input: ".", modifierFlags: [], action: #selector(blackout)),
            UIKeyCommand(input: UIKeyCommand.inputEscape, modifierFlags: [], action: #selector(escape)),
        ]
        let all = next + prev + other
        all.forEach { $0.wantsPriorityOverSystemBehavior = true }
        return all
    }

    @objc private func goNext() { onNext?() }
    @objc private func goPrevious() { onPrevious?() }
    @objc private func blackout() { onBlackout?() }
    @objc private func escape() { onEscape?() }
}
