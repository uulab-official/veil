import Foundation
import Testing
@testable import VeilHostCore

struct GuestTextCompositionTests {
    @Test("typing 안녕 shows every step in the guest and commits without retyping")
    func typesHangulInline() {
        var composition = GuestTextComposition()
        // Two-set Korean: ㅇ → 아 → 안, then ㄴ commits 안 and opens ㄴ, → 녀 → 녕.
        #expect(composition.update(to: "ㅇ") == GuestTextReplacement(replaceLength: 0, text: "ㅇ"))
        #expect(composition.update(to: "아") == GuestTextReplacement(replaceLength: 1, text: "아"))
        #expect(composition.update(to: "안") == GuestTextReplacement(replaceLength: 1, text: "안"))
        #expect(composition.commit("안") == nil)
        #expect(composition.update(to: "ㄴ") == GuestTextReplacement(replaceLength: 0, text: "ㄴ"))
        #expect(composition.update(to: "녀") == GuestTextReplacement(replaceLength: 1, text: "녀"))
        #expect(composition.update(to: "녕") == GuestTextReplacement(replaceLength: 1, text: "녕"))
        #expect(composition.shown == "녕")
    }

    @Test("a final consonant that moves to the next syllable rewrites only the last character")
    func movesFinalConsonant() {
        var composition = GuestTextComposition()
        _ = composition.update(to: "안")
        // 안 + ㅕ: the IME commits 아 and opens 녀.
        #expect(composition.commit("아") == GuestTextReplacement(replaceLength: 1, text: "아"))
        #expect(composition.update(to: "녀") == GuestTextReplacement(replaceLength: 0, text: "녀"))
    }

    @Test("Backspace over the last jamo deletes it from the guest")
    func backspaceRemovesComposition() {
        var composition = GuestTextComposition()
        _ = composition.update(to: "ㄱ")
        #expect(composition.update(to: "") == GuestTextReplacement(replaceLength: 1, text: ""))
        #expect(composition.shown.isEmpty)
    }

    @Test("a multi-character composition sends only what changed")
    func sendsOnlyTheDifference() {
        var composition = GuestTextComposition()
        _ = composition.update(to: "にほ")
        #expect(composition.update(to: "にほん") == GuestTextReplacement(replaceLength: 0, text: "ん"))
        #expect(composition.commit("日本") == GuestTextReplacement(replaceLength: 3, text: "日本"))
    }

    @Test("an abandoned composition stays in the guest as typed")
    func abandonKeepsText() {
        var composition = GuestTextComposition()
        _ = composition.update(to: "한")
        composition.abandon()
        #expect(composition.update(to: "ㄱ") == GuestTextReplacement(replaceLength: 0, text: "ㄱ"))
    }

    @Test("a correction may delete without typing, but never nothing at all")
    func sendability() {
        #expect(InputTextEvent.isSendable("", replaceLength: 1))
        #expect(!InputTextEvent.isSendable("", replaceLength: 0))
        #expect(!InputTextEvent.isSendable("a", replaceLength: -1))
        #expect(InputTextEvent.isSendable("녕", replaceLength: 1))
    }

    @Test("plain committed text leaves replaceLength off the wire")
    func encodesWithoutReplaceLength() throws {
        let plain = String(decoding: try JSONEncoder().encode(InputTextEvent(windowId: "hwnd:1", text: "a")), as: UTF8.self)
        #expect(!plain.contains("replaceLength"))
        let correction = String(
            decoding: try JSONEncoder().encode(InputTextEvent(windowId: "hwnd:1", text: "녕", replaceLength: 1)),
            as: UTF8.self
        )
        #expect(correction.contains("\"replaceLength\":1"))
    }
}

struct GuestImeModeTests {
    @Test("a plain keyboard layout that lists Korean is still not an input method")
    func layoutIsNotInputMethod() {
        #expect(!MacInputSourceKind.isComposing(languages: ["ko"], isInputMode: false))
        #expect(MacInputSourceKind.isComposing(languages: ["ja", "en"], isInputMode: true))
        #expect(MacInputSourceKind.isComposing(languages: ["ko"], isInputMode: true))
    }

    @Test("input.ime.set encodes the documented shape")
    func encodesRequest() throws {
        let json = String(decoding: try JSONEncoder().encode(InputImeSetRequest(requestId: "r", mode: .native)), as: UTF8.self)
        #expect(json.contains("\"type\":\"input.ime.set\""))
        #expect(json.contains("\"mode\":\"native\""))
    }
}
