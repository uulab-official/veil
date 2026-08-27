import Testing

@testable import VeilHostCore

@Suite("Mac text input routing")
struct MacTextInputRouterTests {
    private let router = MacTextInputRouter()

    @Test("routes text the Windows virtual key map cannot express as committed Unicode")
    func routesUnmappableTextAsCommittedUnicode() {
        // These are exactly the characters the virtual-key mapper returns nil for, which used to mean
        // they were dropped without a trace.
        for text in ["안녕하세요", "こんにちは", "你好", "café", "-", ",", " ", "!", "😀"] {
            #expect(router.route(committedText: text) == .committedText(text), "\(text)")
        }
    }

    @Test("keeps Enter and Tab on the virtual key path even when an IME commits them as text")
    func keepsEnterAndTabOnVirtualKeyPath() {
        // WM_CHAR would insert a control character instead of submitting or moving focus.
        #expect(router.route(committedText: "\r") == .virtualKey(MacKeyboardInput(key: "enter", windowsVirtualKey: 13)))
        #expect(router.route(committedText: "\r\n") == .virtualKey(MacKeyboardInput(key: "enter", windowsVirtualKey: 13)))
        #expect(router.route(committedText: "\n") == .virtualKey(MacKeyboardInput(key: "enter", windowsVirtualKey: 13)))
        #expect(router.route(committedText: "\t") == .virtualKey(MacKeyboardInput(key: "tab", windowsVirtualKey: 9)))
    }

    @Test("refuses empty and oversized committed text")
    func refusesEmptyAndOversizedCommittedText() {
        #expect(router.route(committedText: "") == .unsupported)
        #expect(
            router.route(committedText: String(repeating: "가", count: InputTextEvent.maximumUTF16Length + 1))
                == .unsupported
        )
    }

    @Test("accepts committed text exactly at the posted-message bound")
    func acceptsCommittedTextAtBound() {
        let text = String(repeating: "a", count: InputTextEvent.maximumUTF16Length)

        #expect(router.route(committedText: text) == .committedText(text))
    }

    @Test("counts surrogate pairs against the UTF-16 bound, not the character count")
    func countsSurrogatePairsAgainstUTF16Bound() {
        // Each emoji is one Character but two UTF-16 code units, and the guest posts one WM_CHAR per
        // code unit.
        let halfBound = InputTextEvent.maximumUTF16Length / 2
        #expect(InputTextEvent.isSendable(String(repeating: "😀", count: halfBound)))
        #expect(!InputTextEvent.isSendable(String(repeating: "😀", count: halfBound + 1)))
    }

    @Test("offers ordinary text keys to the input method")
    func offersOrdinaryTextKeysToInputMethod() {
        // Space is text and is also how a Korean or Japanese IME commits a candidate, so it must reach
        // the input method.
        #expect(router.shouldOfferToInputMethod(keyCode: 49, modifiers: [], isComposing: false))
        #expect(router.shouldOfferToInputMethod(keyCode: 4, modifiers: [], isComposing: false))
        #expect(router.shouldOfferToInputMethod(keyCode: 4, modifiers: [.shift], isComposing: false))
        #expect(router.shouldOfferToInputMethod(keyCode: 4, modifiers: [.option], isComposing: false))
    }

    @Test("keeps shortcut chords and non-text keys away from the input method")
    func keepsShortcutsAndNonTextKeysAwayFromInputMethod() {
        #expect(!router.shouldOfferToInputMethod(keyCode: 8, modifiers: [.command], isComposing: false))
        #expect(!router.shouldOfferToInputMethod(keyCode: 8, modifiers: [.control], isComposing: false))

        for keyCode in [UInt16(36), 48, 51, 53, 123, 124, 125, 126, 117, 115, 119] {
            #expect(
                !router.shouldOfferToInputMethod(keyCode: keyCode, modifiers: [], isComposing: false),
                "\(keyCode)"
            )
        }
    }

    @Test("hands every key to the input method while a composition is open")
    func handsEveryKeyToInputMethodWhileComposing() {
        // Backspace deletes a jamo, arrows move inside the composition, and Enter commits it. Stealing
        // those would leave the IME and the guest disagreeing about what has been typed.
        for keyCode in [UInt16(36), 48, 51, 53, 123, 126] {
            #expect(
                router.shouldOfferToInputMethod(keyCode: keyCode, modifiers: [], isComposing: true),
                "\(keyCode)"
            )
        }
    }

    @Test("routes a declined key through the virtual key mapper when it has an entry")
    func routesDeclinedKeyThroughVirtualKeyMapper() {
        #expect(
            router.route(charactersIgnoringModifiers: "c", keyCode: 8, modifiers: [.command])
                == .virtualKey(MacKeyboardInput(key: "c", windowsVirtualKey: 67, modifiers: ["ctrl"]))
        )
        #expect(
            router.route(charactersIgnoringModifiers: nil, keyCode: 126, modifiers: [])
                == .virtualKey(MacKeyboardInput(key: "arrowUp", windowsVirtualKey: 38))
        )
    }

    @Test("falls back to committed text for printable keys the virtual key mapper drops")
    func fallsBackToCommittedTextForUnmappedPrintableKeys() {
        // The mapper has no virtual key for punctuation or space, so before this fallback these
        // keystrokes reached the guest as nothing at all.
        #expect(router.route(charactersIgnoringModifiers: "-", keyCode: 27, modifiers: []) == .committedText("-"))
        #expect(router.route(charactersIgnoringModifiers: " ", keyCode: 49, modifiers: []) == .committedText(" "))
    }

    @Test("never turns a shortcut chord into committed text")
    func neverTurnsShortcutChordIntoCommittedText() {
        // Command-minus is a shortcut, not a hyphen the guest should insert.
        #expect(router.route(charactersIgnoringModifiers: "-", keyCode: 27, modifiers: [.command]) == .unsupported)
        #expect(router.route(charactersIgnoringModifiers: "-", keyCode: 27, modifiers: [.control]) == .unsupported)
    }

    @Test("rejects control characters as committed text")
    func rejectsControlCharactersAsCommittedText() {
        #expect(!InputTextEvent.isSendable("\u{0}"))
        #expect(!InputTextEvent.isSendable("bell\u{7}"))
        #expect(!InputTextEvent.isSendable("escape\u{1B}"))
    }
}
