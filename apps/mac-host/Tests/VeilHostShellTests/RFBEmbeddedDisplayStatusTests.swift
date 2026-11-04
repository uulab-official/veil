import Testing
@testable import VeilHostShell

@Suite("RFB embedded display status")
struct RFBEmbeddedDisplayStatusTests {
    @Test("connection failure remains visible while reconnect is pending")
    @MainActor
    func connectionFailureRemainsVisibleWhileReconnectIsPending() {
        let model = RFBEmbeddedDisplayModel()

        model.showConnectionFailure("Windows display timed out")

        #expect(model.status == .failed("Windows display timed out"))
        #expect(model.statusSymbolName == "exclamationmark.triangle")
    }
}
