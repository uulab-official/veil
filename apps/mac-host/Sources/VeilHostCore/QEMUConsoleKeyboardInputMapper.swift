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
    public var commandKeyMapping: VMCommandKeyMapping

    public init(commandKeyMapping: VMCommandKeyMapping = .default) {
        self.commandKeyMapping = commandKeyMapping
    }

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

        // A Korean, Japanese, or other non-Latin input source on the Mac produces characters such as
        // "ㅁ" that have no guest key, so the physical key position stands in for them. Windows'
        // own keyboard layout and IME then decide what the key types.
        let character: Character
        if let charactersIgnoringModifiers,
           let scalar = charactersIgnoringModifiers.unicodeScalars.first,
           scalar.value >= 32,
           scalar.value <= 126 {
            character = Character(scalar)
        } else if let physicalCharacter = Self.usPhysicalKeys[keyCode] {
            character = physicalCharacter
        } else {
            return nil
        }

        return try? QEMUQMPKeyboardCommandBuilder
            .keySequence(forText: String(character), maximumLength: 1)
            .first
    }

    /// The unshifted US ANSI character printed on each Mac virtual key code.
    private static let usPhysicalKeys: [UInt16: Character] = [
        0: "a", 1: "s", 2: "d", 3: "f", 4: "h", 5: "g", 6: "z", 7: "x", 8: "c", 9: "v",
        11: "b", 12: "q", 13: "w", 14: "e", 15: "r", 16: "y", 17: "t",
        18: "1", 19: "2", 20: "3", 21: "4", 22: "6", 23: "5", 24: "=", 25: "9", 26: "7",
        27: "-", 28: "8", 29: "0", 30: "]", 31: "o", 32: "u", 33: "[", 34: "i", 35: "p",
        37: "l", 38: "j", 39: "'", 40: "k", 41: ";", 42: "\\", 43: ",", 44: "/",
        45: "n", 46: "m", 47: ".", 50: "`"
    ]

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

        let commandIsControl = commandKeyMapping == .control && modifiers.contains(.command)
        if modifiers.contains(.control) || commandIsControl {
            keys.append("ctrl")
        }
        if commandKeyMapping == .windows, modifiers.contains(.command) {
            keys.append("meta_l")
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
