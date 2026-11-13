import Foundation
import Testing

@testable import VeilHostCore

@Suite("Window list reply reader")
struct WindowListReplyReaderTests {
    private func message(_ json: String) -> Data { Data(json.utf8) }

    @Test("passes on the response and one window.created per listed window, then finishes")
    func readsTheWholeAnswer() {
        var reader = WindowListReplyReader()

        let response = reader.accept(message(
            #"{"type":"window.list.response","requestId":"events","windowIds":["hwnd:1","hwnd:2"]}"#
        ))
        let first = reader.accept(message(#"{"type":"window.created","windowId":"hwnd:1"}"#))
        let second = reader.accept(message(#"{"type":"window.created","windowId":"hwnd:2"}"#))

        #expect(response == (true, false))
        #expect(first == (true, false))
        #expect(second == (true, true))
    }

    @Test("an empty list is complete with the response")
    func emptyListFinishesAtOnce() {
        var reader = WindowListReplyReader()

        let response = reader.accept(message(#"{"type":"window.list.response","requestId":"events","windowIds":[]}"#))

        #expect(response == (true, true))
    }

    @Test("leaves events that also reach the listening connection to it")
    func skipsBroadcastEvents() {
        var reader = WindowListReplyReader()

        // The layout every new connection is sent, before the response.
        let layout = reader.accept(message(#"{"type":"window.layout","sequence":7,"windows":[]}"#))
        let response = reader.accept(message(
            #"{"type":"window.list.response","requestId":"events","windowIds":["hwnd:1"]}"#
        ))
        // A broadcast that slipped in between the response and its windows.
        let clipboard = reader.accept(message(#"{"type":"clipboard.text.set","text":"x"}"#))
        let created = reader.accept(message(#"{"type":"window.created","windowId":"hwnd:1"}"#))

        #expect(layout == (false, false))
        #expect(response == (true, false))
        #expect(clipboard == (false, false))
        #expect(created == (true, true))
    }

    @Test("an agent that does not know the request ends the read without an event")
    func oldAgentAnswersWithAnError() {
        var reader = WindowListReplyReader()

        let error = reader.accept(message(#"{"type":"error","requestId":"events","code":"unknown_message_type"}"#))

        #expect(error == (false, true))
    }

    @Test("ignores what is not a message")
    func ignoresGarbage() {
        var reader = WindowListReplyReader()

        #expect(reader.accept(message("not json")) == (false, false))
    }
}
