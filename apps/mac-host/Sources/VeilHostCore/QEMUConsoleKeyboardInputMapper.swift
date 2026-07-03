import Foundation

public struct QEMUConsoleKeyboardModifier: OptionSet, Sendable {
    public let rawValue: Int

    public init(rawValue: Int) {
        self.rawValue = rawValue
    }

    public static let command = QEMUConsoleKeyboardModifier(rawValue: 1 << 0)
    public static let control = QEMUConsoleKeyboardModifier(rawValue: 1 << 1)
    public static let shift = QEMUConsoleKeyboardModifier(rawValue: 1 << 2)
    public static let option = QEMUConsoleKeyboardModifier(rawValue: 1 << 3)
}

public struct QEMUConsoleKeyboardInputMapper: Sendable {
    public init() {}

    public func key(
        charactersIgnoringModifiers: String?,
        keyCode: UInt16,
        modifiers: QEMUConsoleKeyboardModifier = []
    ) -> String? {
        guard let baseKey = baseKey(charactersIgnoringModifiers: charactersIgnoringModifiers, keyCode: keyCode) else {
            return nil
        }

        let modifierKeys = qemuModifiers(from: modifiers)
        guard !modifierKeys.isEmpty else {
            return baseKey
        }

        return (modifierKeys + [baseKey]).joined(separator: "-")
    }

    private func baseKey(charactersIgnoringModifiers: String?, keyCode: UInt16) -> String? {
        if let specialKey = specialKey(for: keyCode) {
            return specialKey
        }

        guard let charactersIgnoringModifiers,
              let scalar = charactersIgnoringModifiers.unicodeScalars.first,
              scalar.value >= 32,
              scalar.value <= 126 else {
            return nil
        }

        return try? QEMUQMPKeyboardCommandBuilder
            .keySequence(forText: String(Character(scalar)), maximumLength: 1)
            .first
    }

    private func specialKey(for keyCode: UInt16) -> String? {
        switch keyCode {
        case 36:
            return "enter"
        case 48:
            return "tab"
        case 49:
            return "space"
        case 51:
            return "backspace"
        case 53:
            return "escape"
        case 115:
            return "home"
        case 116:
            return "pgup"
        case 117:
            return "delete"
        case 119:
            return "end"
        case 121:
            return "pgdn"
        case 123:
            return "left"
        case 124:
            return "right"
        case 125:
            return "down"
        case 126:
            return "up"
        case 122:
            return "f1"
        case 120:
            return "f2"
        case 99:
            return "f3"
        case 118:
            return "f4"
        case 96:
            return "f5"
        case 97:
            return "f6"
        case 98:
            return "f7"
        case 100:
            return "f8"
        case 101:
            return "f9"
        case 109:
            return "f10"
        case 103:
            return "f11"
        case 111:
            return "f12"
        default:
            return nil
        }
    }

    private func qemuModifiers(from modifiers: QEMUConsoleKeyboardModifier) -> [String] {
        var keys: [String] = []

        if modifiers.contains(.command) || modifiers.contains(.control) {
            keys.append("ctrl")
        }
        if modifiers.contains(.option) {
            keys.append("alt")
        }
        if modifiers.contains(.shift) {
            keys.append("shift")
        }

        return keys
    }
}
