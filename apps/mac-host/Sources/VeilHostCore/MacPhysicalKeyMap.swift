import Foundation

/// Windows virtual keys for Mac keys by position (ANSI layout), whatever the macOS input source produces.
///
/// The Windows IME composes Hangul from key positions, the way UTM and Parallels pass keys through. Mapping
/// by the character macOS produced would send ㅁ instead of A with a Korean input source, and would lose every
/// key without an ASCII character. Key codes are `kVK_*` from Carbon's Events.h; virtual keys are from
/// https://learn.microsoft.com/windows/win32/inputdev/virtual-key-codes.
public enum MacPhysicalKeyMap {
    public static func windowsVirtualKey(forMacKeyCode keyCode: UInt16) -> Int? {
        table[keyCode]
    }

    /// The `key` name sent with `input.key`, for logs and the agent's error messages.
    public static func keyName(forMacKeyCode keyCode: UInt16) -> String? {
        guard let virtualKey = table[keyCode] else {
            return nil
        }
        return names[keyCode] ?? String(format: "vk%02X", virtualKey)
    }

    private static let table: [UInt16: Int] = [
        // Letters: VK_A ... VK_Z are their uppercase ASCII codes.
        0: 0x41, 11: 0x42, 8: 0x43, 2: 0x44, 14: 0x45, 3: 0x46, 5: 0x47, 4: 0x48, 34: 0x49, 38: 0x4A,
        40: 0x4B, 37: 0x4C, 46: 0x4D, 45: 0x4E, 31: 0x4F, 35: 0x50, 12: 0x51, 15: 0x52, 1: 0x53, 17: 0x54,
        32: 0x55, 9: 0x56, 13: 0x57, 7: 0x58, 16: 0x59, 6: 0x5A,
        // Digits row.
        29: 0x30, 18: 0x31, 19: 0x32, 20: 0x33, 21: 0x34, 23: 0x35, 22: 0x36, 26: 0x37, 28: 0x38, 25: 0x39,
        // Punctuation (VK_OEM_*).
        41: 0xBA, 24: 0xBB, 43: 0xBC, 27: 0xBD, 47: 0xBE, 44: 0xBF, 50: 0xC0, 33: 0xDB, 42: 0xDC, 30: 0xDD,
        39: 0xDE,
        // Editing and navigation.
        36: 0x0D, 76: 0x0D, 48: 0x09, 49: 0x20, 51: 0x08, 53: 0x1B, 117: 0x2E, 115: 0x24, 119: 0x23,
        116: 0x21, 121: 0x22, 123: 0x25, 124: 0x27, 125: 0x28, 126: 0x26,
        // Function keys.
        122: 0x70, 120: 0x71, 99: 0x72, 118: 0x73, 96: 0x74, 97: 0x75, 98: 0x76, 100: 0x77, 101: 0x78,
        109: 0x79, 103: 0x7A, 111: 0x7B,
    ]

    private static let names: [UInt16: String] = [
        36: "enter", 76: "enter", 48: "tab", 49: "space", 51: "backspace", 53: "escape", 117: "delete",
        115: "home", 119: "end", 116: "pageUp", 121: "pageDown", 123: "arrowLeft", 124: "arrowRight",
        125: "arrowDown", 126: "arrowUp",
    ]
}
