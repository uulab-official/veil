import Testing
@testable import VeilHostCore

@Suite("Typing commands into Windows")
struct GuestTypingSafetyTests {
    @Test("a fresh Windows without the tools may be typed into")
    func allowsFirstInstall() {
        #expect(GuestTypingSafety.refusal(hasLiveAgent: false, openWindowCount: 0, toolsWereInstalled: false) == nil)
    }

    @Test("connected tools that report no window allow typing")
    func allowsEmptyDesktop() {
        #expect(GuestTypingSafety.refusal(hasLiveAgent: true, openWindowCount: 0, toolsWereInstalled: true) == nil)
    }

    @Test("open app windows refuse typing, with or without the tools connected")
    func refusesOverOpenApps() {
        #expect(GuestTypingSafety.refusal(hasLiveAgent: true, openWindowCount: 2, toolsWereInstalled: true) == .appsAreOpen)
        #expect(GuestTypingSafety.refusal(hasLiveAgent: false, openWindowCount: 1, toolsWereInstalled: true) == .appsAreOpen)
    }

    @Test("tools that stopped answering refuse typing, because the open apps cannot be seen")
    func refusesWhenToolsDoNotAnswer() {
        // The live case: the tools crashed while Notepad and Paint were open, the host showed no window
        // any more, and the repair typed into Windows.
        #expect(
            GuestTypingSafety.refusal(hasLiveAgent: false, openWindowCount: 0, toolsWereInstalled: true)
                == .toolsDoNotAnswer
        )
    }
}
