import Foundation

public struct MacKeyboardInput: Equatable, Sendable {
    public var key: String
    public var windowsVirtualKey: Int
    public var modifiers: [String]

    public init(key: String, windowsVirtualKey: Int, modifiers: [String] = []) {
        self.key = key
        self.windowsVirtualKey = windowsVirtualKey
        self.modifiers = modifiers
    }
}

public struct MacKeyboardModifier: OptionSet, Sendable {
    public let rawValue: Int

    public init(rawValue: Int) {
        self.rawValue = rawValue
    }

    public static let command = MacKeyboardModifier(rawValue: 1 << 0)
    public static let control = MacKeyboardModifier(rawValue: 1 << 1)
    public static let shift = MacKeyboardModifier(rawValue: 1 << 2)
    public static let option = MacKeyboardModifier(rawValue: 1 << 3)
}

public struct MacKeyboardInputMapper: Sendable {
    public init() {}

    public func input(
        charactersIgnoringModifiers: String?,
        keyCode: UInt16,
        modifiers: MacKeyboardModifier = []
    ) -> MacKeyboardInput? {
        guard let key = inputKey(charactersIgnoringModifiers: charactersIgnoringModifiers, keyCode: keyCode),
              let windowsVirtualKey = windowsVirtualKey(keyCode: keyCode, key: key) else {
            return nil
        }

        return MacKeyboardInput(
            key: key,
            windowsVirtualKey: windowsVirtualKey,
            modifiers: windowsModifiers(from: modifiers)
        )
    }

    private func inputKey(charactersIgnoringModifiers: String?, keyCode: UInt16) -> String? {
        if let charactersIgnoringModifiers,
           let scalar = charactersIgnoringModifiers.unicodeScalars.first,
           scalar.value >= 32,
           scalar.value <= 126 {
            return String(Character(scalar)).lowercased()
        }

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
        case 123:
            return "arrowLeft"
        case 124:
            return "arrowRight"
        case 125:
            return "arrowDown"
        case 126:
            return "arrowUp"
        default:
            return nil
        }
    }

    private func windowsVirtualKey(keyCode: UInt16, key: String) -> Int? {
        switch key {
        case "enter":
            return 13
        case "tab":
            return 9
        case "space":
            return 32
        case "backspace":
            return 8
        case "escape":
            return 27
        case "arrowLeft":
            return 37
        case "arrowRight":
            return 39
        case "arrowDown":
            return 40
        case "arrowUp":
            return 38
        default:
            break
        }

        if let scalar = key.uppercased().unicodeScalars.first,
           scalar.value >= 65,
           scalar.value <= 90 {
            return Int(scalar.value)
        }

        if let scalar = key.unicodeScalars.first,
           scalar.value >= 48,
           scalar.value <= 57 {
            return Int(scalar.value)
        }

        return nil
    }

    private func windowsModifiers(from modifiers: MacKeyboardModifier) -> [String] {
        var result: [String] = []

        if modifiers.contains(.command) || modifiers.contains(.control) {
            result.append("ctrl")
        }
        if modifiers.contains(.shift) {
            result.append("shift")
        }
        if modifiers.contains(.option) {
            result.append("alt")
        }

        return result
    }
}
