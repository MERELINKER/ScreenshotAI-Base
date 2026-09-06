import Carbon
import Foundation
import ScreenshotAIKit

final class GlobalHotKeyService: @unchecked Sendable {
    static let shared = GlobalHotKeyService()

    private var eventHandler: EventHandlerRef?
    private var hotKeys: [EventHotKeyRef?] = []
    private var handler: ((HotKeyAction) -> Void)?
    private var didInstallHandler = false

    private init() {}

    func register(handler: @escaping (HotKeyAction) -> Void) {
        self.handler = handler
        installHandlerIfNeeded()
        reloadShortcuts()
    }

    func reloadShortcuts() {
        unregisterHotKeys()
        let shortcuts = HotKeyPreferences().allShortcuts()

        for action in HotKeyAction.allCases {
            guard let shortcut = shortcuts[action] else { continue }
            var hotKeyRef: EventHotKeyRef?
            let hotKeyID = EventHotKeyID(
                signature: OSType(fourCharCode("SSAI")),
                id: action.id
            )
            let status = RegisterEventHotKey(
                shortcut.keyCode,
                carbonModifiers(from: shortcut.modifiers),
                hotKeyID,
                GetApplicationEventTarget(),
                0,
                &hotKeyRef
            )
            if status == noErr {
                hotKeys.append(hotKeyRef)
            }
        }
    }

    private func installHandlerIfNeeded() {
        guard !didInstallHandler else { return }

        var eventSpec = EventTypeSpec(
            eventClass: OSType(kEventClassKeyboard),
            eventKind: UInt32(kEventHotKeyPressed)
        )

        InstallEventHandler(
            GetApplicationEventTarget(),
            { _, event, _ in
                var hotKeyID = EventHotKeyID()
                let status = GetEventParameter(
                    event,
                    EventParamName(kEventParamDirectObject),
                    EventParamType(typeEventHotKeyID),
                    nil,
                    MemoryLayout<EventHotKeyID>.size,
                    nil,
                    &hotKeyID
                )

                guard status == noErr,
                      let action = HotKeyAction.allCases.first(where: { $0.id == hotKeyID.id })
                else {
                    return noErr
                }

                DispatchQueue.main.async {
                    GlobalHotKeyService.shared.handler?(action)
                }

                return noErr
            },
            1,
            &eventSpec,
            nil,
            &eventHandler
        )

        didInstallHandler = true
    }

    private func unregisterHotKeys() {
        for hotKey in hotKeys {
            if let hotKey {
                UnregisterEventHotKey(hotKey)
            }
        }
        hotKeys.removeAll()
    }

    private func carbonModifiers(from modifiers: KeyboardShortcutModifiers) -> UInt32 {
        var result: UInt32 = 0
        if modifiers.contains(.command) { result |= UInt32(cmdKey) }
        if modifiers.contains(.option) { result |= UInt32(optionKey) }
        if modifiers.contains(.control) { result |= UInt32(controlKey) }
        if modifiers.contains(.shift) { result |= UInt32(shiftKey) }
        return result
    }

    private func fourCharCode(_ string: String) -> FourCharCode {
        var result: FourCharCode = 0
        for scalar in string.unicodeScalars.prefix(4) {
            result = (result << 8) + FourCharCode(scalar.value)
        }
        return result
    }
}
