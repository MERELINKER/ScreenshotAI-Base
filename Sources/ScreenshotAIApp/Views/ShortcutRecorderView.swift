import AppKit
import SwiftUI
import ScreenshotAIKit

struct ShortcutRecorderView: NSViewRepresentable {
    let isRecording: Bool
    let onRecord: (KeyboardShortcutDefinition) -> Void
    let onCancel: () -> Void

    func makeNSView(context: Context) -> RecorderNSView {
        let view = RecorderNSView()
        view.onRecord = onRecord
        view.onCancel = onCancel
        return view
    }

    func updateNSView(_ nsView: RecorderNSView, context: Context) {
        nsView.isRecording = isRecording
        nsView.onRecord = onRecord
        nsView.onCancel = onCancel

        if isRecording {
            DispatchQueue.main.async {
                nsView.window?.makeFirstResponder(nsView)
            }
        }
    }
}

final class RecorderNSView: NSView {
    var isRecording = false
    var onRecord: ((KeyboardShortcutDefinition) -> Void)?
    var onCancel: (() -> Void)?

    override var acceptsFirstResponder: Bool { true }

    override func keyDown(with event: NSEvent) {
        guard isRecording else {
            super.keyDown(with: event)
            return
        }

        if event.keyCode == 53 {
            onCancel?()
            return
        }

        let modifiers = KeyboardShortcutModifiers(event.modifierFlags)
        guard !modifiers.isEmpty else {
            NSSound.beep()
            return
        }

        onRecord?(
            KeyboardShortcutDefinition(
                keyCode: UInt32(event.keyCode),
                modifiers: modifiers
            )
        )
    }
}

private extension KeyboardShortcutModifiers {
    init(_ flags: NSEvent.ModifierFlags) {
        var modifiers: KeyboardShortcutModifiers = []
        let normalizedFlags = flags.intersection(.deviceIndependentFlagsMask)
        if normalizedFlags.contains(.control) { modifiers.insert(.control) }
        if normalizedFlags.contains(.option) { modifiers.insert(.option) }
        if normalizedFlags.contains(.shift) { modifiers.insert(.shift) }
        if normalizedFlags.contains(.command) { modifiers.insert(.command) }
        self = modifiers
    }
}
