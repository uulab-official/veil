import Foundation

/// Where a piece of keyboard input should go.
public enum MacTextInputRoute: Equatable, Sendable {
    /// Send as `input.key` with a Windows virtual key.
    case virtualKey(MacKeyboardInput)
    /// Send as `input.text` committed Unicode.
    case committedText(String)
    /// Nothing safe to send.
    case unsupported
}

/// Decides whether keyboard input belongs on the virtual-key path or the committed-text path.
///
/// This exists because `MacKeyboardInputMapper` can only produce a Windows virtual key for letters,
/// digits, and a handful of named keys. Space, every punctuation mark, and every non-Latin character
/// resolve to `nil` there, which means they were silently dropped before this type existed -- not just
/// Hangul and kana, but `,` and `-` too.
///
/// Text therefore travels as committed Unicode by default. Only keys whose guest behavior depends on
/// being a *key* rather than a character stay on the virtual-key path: Enter submits, Tab moves focus,
/// arrows navigate, Escape cancels. `WM_CHAR` would not reproduce any of those.
///
/// Kept free of AppKit so the decisions are unit testable without a window or an input context.
public struct MacTextInputRouter: Sendable {
    /// macOS key codes whose guest meaning is the key itself, not a character.
    ///
    /// Space (49) is deliberately absent: it is real text, and it is also how a Korean or Japanese IME
    /// commits a candidate, so it has to reach the input method.
    static let nonTextKeyCodes: Set<UInt16> = [
        36,  // Return
        48,  // Tab
        51,  // Delete (backspace)
        53,  // Escape
        76,  // Numpad Enter
        114, // Help / Insert
        115, // Home
        116, // Page Up
        117, // Forward Delete
        119, // End
        121, // Page Down
        122, // F1
        120, // F2
        99,  // F3
        118, // F4
        96,  // F5
        97,  // F6
        98,  // F7
        100, // F8
        101, // F9
        109, // F10
        103, // F11
        111, // F12
        123, // Left arrow
        124, // Right arrow
        125, // Down arrow
        126  // Up arrow
    ]

    private let keyboardMapper: MacKeyboardInputMapper

    public init(keyboardMapper: MacKeyboardInputMapper = MacKeyboardInputMapper()) {
        self.keyboardMapper = keyboardMapper
    }

    /// Whether a `keyDown` should be handed to the macOS input context so an IME can compose it.
    public func shouldOfferToInputMethod(
        keyCode: UInt16,
        modifiers: MacKeyboardModifier,
        isComposing: Bool
    ) -> Bool {
        // While a composition is open every key belongs to the input method: backspace deletes a jamo,
        // arrows move inside the composition, and Enter commits it. Stealing those would leave the IME
        // and the guest disagreeing about what has been typed.
        if isComposing {
            return true
        }

        // Command and Control chords are shortcuts, never text.
        if modifiers.contains(.command) || modifiers.contains(.control) {
            return false
        }

        return !Self.nonTextKeyCodes.contains(keyCode)
    }

    /// Route for text that the macOS input context committed.
    public func route(committedText text: String) -> MacTextInputRoute {
        guard !text.isEmpty else {
            return .unsupported
        }

        // An IME can commit Return or Tab as text. They still need to arrive as keys so the guest
        // submits or moves focus instead of inserting a control character.
        if text == "\r" || text == "\r\n" || text == "\n" {
            return namedKeyRoute(keyCode: 36)
        }
        if text == "\t" {
            return namedKeyRoute(keyCode: 48)
        }

        guard InputTextEvent.isSendable(text) else {
            return .unsupported
        }

        return .committedText(text)
    }

    /// Route for a `keyDown` the input method declined to handle.
    public func route(
        charactersIgnoringModifiers: String?,
        keyCode: UInt16,
        modifiers: MacKeyboardModifier
    ) -> MacTextInputRoute {
        if let input = keyboardMapper.input(
            charactersIgnoringModifiers: charactersIgnoringModifiers,
            keyCode: keyCode,
            modifiers: modifiers
        ) {
            return .virtualKey(input)
        }

        // The virtual-key mapper has no entry for this key. If it produced printable text, send it as
        // committed Unicode rather than dropping it, which is what used to happen to every punctuation
        // mark and space.
        guard !modifiers.contains(.command),
              !modifiers.contains(.control),
              let charactersIgnoringModifiers else {
            return .unsupported
        }

        return route(committedText: charactersIgnoringModifiers)
    }

    private func namedKeyRoute(keyCode: UInt16) -> MacTextInputRoute {
        guard let input = keyboardMapper.input(
            charactersIgnoringModifiers: nil,
            keyCode: keyCode
        ) else {
            return .unsupported
        }

        return .virtualKey(input)
    }
}
