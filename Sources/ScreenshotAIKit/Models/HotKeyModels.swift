import Foundation

public enum HotKeyAction: String, CaseIterable, Codable, Sendable {
    case manualCapture
    case autoCapture
    case openTaskCenter
    case localOCRCapture

    public var id: UInt32 {
        switch self {
        case .manualCapture:
            return 1
        case .autoCapture:
            return 2
        case .openTaskCenter:
            return 3
        case .localOCRCapture:
            return 4
        }
    }

    public var title: String {
        switch self {
        case .manualCapture:
            return "按当前模式截图"
        case .autoCapture:
            return "自动截图并执行"
        case .openTaskCenter:
            return "打开时间线"
        case .localOCRCapture:
            return "截图并本地 OCR"
        }
    }

    public var defaultShortcut: KeyboardShortcutDefinition {
        switch self {
        case .manualCapture:
            return KeyboardShortcutDefinition(keyCode: 1, modifiers: [.control, .option, .command])
        case .autoCapture:
            return KeyboardShortcutDefinition(keyCode: 0, modifiers: [.control, .option, .command])
        case .openTaskCenter:
            return KeyboardShortcutDefinition(keyCode: 17, modifiers: [.control, .option, .command])
        case .localOCRCapture:
            return KeyboardShortcutDefinition(keyCode: 31, modifiers: [.control, .option, .command])
        }
    }
}

public struct KeyboardShortcutModifiers: OptionSet, Codable, Hashable, Sendable {
    public let rawValue: UInt32

    public init(rawValue: UInt32) {
        self.rawValue = rawValue
    }

    public static let shift = KeyboardShortcutModifiers(rawValue: 1 << 0)
    public static let control = KeyboardShortcutModifiers(rawValue: 1 << 1)
    public static let option = KeyboardShortcutModifiers(rawValue: 1 << 2)
    public static let command = KeyboardShortcutModifiers(rawValue: 1 << 3)
}

public struct KeyboardShortcutDefinition: Codable, Hashable, Sendable {
    public var keyCode: UInt32
    public var modifiers: KeyboardShortcutModifiers

    public init(keyCode: UInt32, modifiers: KeyboardShortcutModifiers) {
        self.keyCode = keyCode
        self.modifiers = modifiers
    }

    public var displayText: String {
        "\(modifiers.displayText)\(Self.keyDisplayName(for: keyCode))"
    }

    public static func keyDisplayName(for keyCode: UInt32) -> String {
        keyDisplayNames[keyCode] ?? "Key \(keyCode)"
    }

    private static let keyDisplayNames: [UInt32: String] = [
        0: "A", 1: "S", 2: "D", 3: "F", 4: "H", 5: "G", 6: "Z", 7: "X",
        8: "C", 9: "V", 11: "B", 12: "Q", 13: "W", 14: "E", 15: "R",
        16: "Y", 17: "T", 18: "1", 19: "2", 20: "3", 21: "4", 22: "6",
        23: "5", 24: "=", 25: "9", 26: "7", 27: "-", 28: "8", 29: "0",
        30: "]", 31: "O", 32: "U", 33: "[", 34: "I", 35: "P", 37: "L",
        38: "J", 39: "'", 40: "K", 41: ";", 42: "\\", 43: ",", 44: "/",
        45: "N", 46: "M", 47: ".", 49: "Space", 51: "Delete", 53: "Esc",
        96: "F5", 97: "F6", 98: "F7", 99: "F3", 100: "F8", 101: "F9",
        103: "F11", 109: "F10", 111: "F12", 118: "F4", 122: "F1", 120: "F2"
    ]
}

public extension KeyboardShortcutModifiers {
    var displayText: String {
        var result = ""
        if contains(.control) { result += "⌃" }
        if contains(.option) { result += "⌥" }
        if contains(.shift) { result += "⇧" }
        if contains(.command) { result += "⌘" }
        return result
    }
}

public struct HotKeyPreferences {
    private let defaults: UserDefaults
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    public func shortcut(for action: HotKeyAction) -> KeyboardShortcutDefinition {
        guard let data = defaults.data(forKey: key(for: action)),
              let shortcut = try? decoder.decode(KeyboardShortcutDefinition.self, from: data)
        else {
            return action.defaultShortcut
        }
        return shortcut
    }

    public func setShortcut(_ shortcut: KeyboardShortcutDefinition, for action: HotKeyAction) throws {
        let data = try encoder.encode(shortcut)
        defaults.set(data, forKey: key(for: action))
    }

    public func action(matching shortcut: KeyboardShortcutDefinition, excluding excludedAction: HotKeyAction) -> HotKeyAction? {
        HotKeyAction.allCases.first { action in
            action != excludedAction && self.shortcut(for: action) == shortcut
        }
    }

    public func allShortcuts() -> [HotKeyAction: KeyboardShortcutDefinition] {
        Dictionary(uniqueKeysWithValues: HotKeyAction.allCases.map { action in
            (action, shortcut(for: action))
        })
    }

    private func key(for action: HotKeyAction) -> String {
        "hotKey.\(action.rawValue)"
    }
}
