import Testing
@testable import VeilHostCore

@Suite("Windows Korean/English follows the Mac")
struct GuestHangulModeTrackerTests {
    @Test("Korean input sources are told apart by language")
    func koreanInputSource() {
        #expect(GuestHangulModeTracker.isKorean(languages: ["ko"]))
        #expect(GuestHangulModeTracker.isKorean(languages: ["ko-KR", "en"]))
        #expect(!GuestHangulModeTracker.isKorean(languages: ["en", "ko"]))
        #expect(!GuestHangulModeTracker.isKorean(languages: ["ja"]))
        #expect(!GuestHangulModeTracker.isKorean(languages: []))
    }

    @Test("A new Windows app starts in English, so only a Korean Mac presses the key")
    func newAppStartsInEnglish() {
        var tracker = GuestHangulModeTracker()
        func align(_ windowId: String, _ processId: Int, korean: Bool) -> Bool {
            tracker.align(windowId: windowId, processId: processId, macIsKorean: korean)
        }
        #expect(!align("w1", 10, korean: false))
        #expect(align("w2", 20, korean: true))
    }

    @Test("The key is pressed only when the app's mode differs from the Mac")
    func pressesOnlyOnDifference() {
        var tracker = GuestHangulModeTracker()
        func align(_ windowId: String, _ processId: Int, korean: Bool) -> Bool {
            tracker.align(windowId: windowId, processId: processId, macIsKorean: korean)
        }
        #expect(align("w1", 10, korean: true))
        #expect(!align("w1", 10, korean: true))
        #expect(align("w1", 10, korean: false))
        #expect(!align("w1", 10, korean: false))
    }

    @Test("A switch made in another Mac app is caught up when the Windows app comes forward")
    func catchesUpAfterSwitchElsewhere() {
        var tracker = GuestHangulModeTracker()
        func align(_ windowId: String, _ processId: Int, korean: Bool) -> Bool {
            tracker.align(windowId: windowId, processId: processId, macIsKorean: korean)
        }
        #expect(align("w1", 10, korean: true))
        // The user went to Safari, switched to English there, and came back: one press, not an inversion.
        #expect(align("w1", 10, korean: false))
    }

    @Test("Each app keeps its own mode, and a dialog shares its app's")
    func modePerProcess() {
        var tracker = GuestHangulModeTracker()
        func align(_ windowId: String, _ processId: Int, korean: Bool) -> Bool {
            tracker.align(windowId: windowId, processId: processId, macIsKorean: korean)
        }
        #expect(align("notepad", 10, korean: true))
        #expect(align("paint", 20, korean: true))
        // Notepad's Save dialog belongs to Notepad, which is already Korean.
        #expect(!align("notepad-save", 10, korean: true))
    }

    @Test("The right Command realignment leaves Windows matching the Mac")
    func realignment() {
        var tracker = GuestHangulModeTracker()
        func align(_ windowId: String, _ processId: Int, korean: Bool) -> Bool {
            tracker.align(windowId: windowId, processId: processId, macIsKorean: korean)
        }
        // Windows was switched behind the host's back; the user pressed right Command to fix it.
        tracker.realigned(windowId: "w1", processId: 10, macIsKorean: true)
        #expect(!align("w1", 10, korean: true))
        #expect(align("w1", 10, korean: false))
    }

    @Test("An app is forgotten when its last window closes, since a new one starts in English")
    func forgetsClosedApp() {
        var tracker = GuestHangulModeTracker()
        func align(_ windowId: String, _ processId: Int, korean: Bool) -> Bool {
            tracker.align(windowId: windowId, processId: processId, macIsKorean: korean)
        }
        #expect(align("w1", 10, korean: true))
        #expect(!align("w2", 10, korean: true))
        tracker.windowClosed(windowId: "w1")
        // Another window of the app is still open: still Korean.
        #expect(!align("w2", 10, korean: true))
        tracker.windowClosed(windowId: "w2")
        #expect(align("w3", 10, korean: true))
    }
}
