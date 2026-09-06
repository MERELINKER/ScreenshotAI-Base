import Foundation
import Testing
@testable import ScreenshotAIKit

@Test
func defaultHotKeysHaveReadableLabels() {
    let preferences = HotKeyPreferences(defaults: .ephemeralHotKeyDefaults())

    #expect(preferences.shortcut(for: .manualCapture).displayText == "⌃⌥⌘S")
    #expect(preferences.shortcut(for: .autoCapture).displayText == "⌃⌥⌘A")
    #expect(preferences.shortcut(for: .openTaskCenter).displayText == "⌃⌥⌘T")
    #expect(preferences.shortcut(for: .localOCRCapture).displayText == "⌃⌥⌘O")
    #expect(HotKeyAction.manualCapture.title == "按当前模式截图")
    #expect(HotKeyAction.localOCRCapture.title == "截图并本地 OCR")
}

@Test
func customHotKeyPersistsAndOverridesDefault() throws {
    let defaults = UserDefaults.ephemeralHotKeyDefaults()
    let preferences = HotKeyPreferences(defaults: defaults)
    let custom = KeyboardShortcutDefinition(
        keyCode: 8,
        modifiers: [.command, .shift]
    )

    try preferences.setShortcut(custom, for: .manualCapture)

    let reloadedPreferences = HotKeyPreferences(defaults: defaults)
    #expect(reloadedPreferences.shortcut(for: .manualCapture) == custom)
    #expect(reloadedPreferences.shortcut(for: .manualCapture).displayText == "⇧⌘C")
}

@Test
func matchingShortcutFindsConflictingAction() throws {
    let defaults = UserDefaults.ephemeralHotKeyDefaults()
    let preferences = HotKeyPreferences(defaults: defaults)
    let custom = KeyboardShortcutDefinition(
        keyCode: 8,
        modifiers: [.command, .shift]
    )

    try preferences.setShortcut(custom, for: .autoCapture)

    #expect(preferences.action(matching: custom, excluding: .manualCapture) == .autoCapture)
    #expect(preferences.action(matching: custom, excluding: .autoCapture) == nil)
}

private extension UserDefaults {
    static func ephemeralHotKeyDefaults() -> UserDefaults {
        let suiteName = "ScreenshotAIKitTests-\(UUID().uuidString)"
        return UserDefaults(suiteName: suiteName)!
    }
}
