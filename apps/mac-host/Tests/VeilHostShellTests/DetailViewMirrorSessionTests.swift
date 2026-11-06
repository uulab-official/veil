import Foundation
import Testing
import VeilHostCore

@testable import VeilHostShell

@MainActor
@Suite("Launcher active app window")
struct DetailViewMirrorSessionTests {
    @Test("a stopped or suspended Windows names no open app window")
    func stoppedWindowsHasNoOpenApp() {
        let sessions = [Self.session()]

        #expect(DetailView.activeMirrorSession(in: sessions, runtimeState: .running)?.window.title == "Paint")
        #expect(DetailView.activeMirrorSession(in: sessions, runtimeState: .stopped) == nil)
        #expect(DetailView.activeMirrorSession(in: sessions, runtimeState: .suspended) == nil)
        #expect(DetailView.activeMirrorSession(in: sessions, runtimeState: nil) == nil)
    }

    private static func session() -> WindowMirrorSession {
        WindowMirrorSession(
            window: WindowCreatedEvent(windowId: "hwnd:0003029A", processId: 1, appId: "winapp_paint", title: "Paint", bounds: WindowBounds(x: 0, y: 0, width: 1, height: 1), state: "normal", focused: true),
            connectionMode: .agent,
            captureState: .streaming
        )
    }
}
