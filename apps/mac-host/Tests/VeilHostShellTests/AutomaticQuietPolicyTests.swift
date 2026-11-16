import Testing

@testable import VeilHostShell

@Suite("Automatic quiet policy")
struct AutomaticQuietPolicyTests {
    @Test("quiets only after the user closed the last app window")
    func quietsOnlyAfterUserClose() {
        #expect(AutomaticQuietPolicy.allowsQuiet(lastAppWindowClosedByUser: true))
        // Windows dropped because the agent restarted leave Windows running with its apps open.
        #expect(!AutomaticQuietPolicy.allowsQuiet(lastAppWindowClosedByUser: false))
    }
}
