import Testing
import VeilHostCore
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

    @Test("keeps the desktop resize fallback when it connects")
    @MainActor
    func keepsResizeFallbackWhenConnecting() {
        let model = RFBEmbeddedDisplayModel()
        defer { model.stop() }

        // The view installs the fallback and then connects; connecting stops any previous session first.
        model.setDisplayResizeFallback { _, _ in }
        model.connectIfNeeded(to: VMConsoleDisplaySurface(
            kind: .vncLoopback,
            endpoint: "127.0.0.1:1",
            screenshotPath: nil,
            isLiveCapable: true
        ))

        #expect(model.hasDisplayResizeFallback)
    }

    @Test("a dropped connection before any picture keeps the specific socket error")
    @MainActor
    func socketErrorStaysVisibleWithoutAPicture() {
        let model = RFBEmbeddedDisplayModel()
        let surface = VMConsoleDisplaySurface(kind: .vncLoopback, endpoint: "127.0.0.1:1", screenshotPath: nil, isLiveCapable: true)

        model.showConnectionFailure("RFB loopback socket closed before the requested bytes were received.")

        // Without a picture the specific error is all the user has to go on.
        #expect(model.statusTitle(for: surface) == "RFB loopback socket closed before the requested bytes were received.")
    }
}
