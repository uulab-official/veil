import Testing
@testable import VeilHostShell

struct WindowsRuntimeStopConfirmationTests {
    @Test("stopping with a mirrored app asks for confirmation")
    func mirroredAppNeedsConfirmation() {
        #expect(WindowsRuntimeStopConfirmation.needsConfirmation(
            hasMirroredWindowsApp: true,
            hasQueuedLaunch: false
        ))
    }

    @Test("stopping with a queued app asks for confirmation")
    func queuedLaunchNeedsConfirmation() {
        #expect(WindowsRuntimeStopConfirmation.needsConfirmation(
            hasMirroredWindowsApp: false,
            hasQueuedLaunch: true
        ))
    }

    @Test("an idle running VM stops without an extra prompt")
    func idleRuntimeDoesNotNeedConfirmation() {
        #expect(!WindowsRuntimeStopConfirmation.needsConfirmation(
            hasMirroredWindowsApp: false,
            hasQueuedLaunch: false
        ))
    }

    @Test("confirmation copy explains the destructive consequence")
    func copyNamesWhatWillClose() {
        #expect(WindowsRuntimeStopConfirmation.message(
            hasMirroredWindowsApp: true,
            hasQueuedLaunch: true
        ) == "Stopping Windows closes mirrored app windows. The queued app launch will remain pending until Windows reconnects.")
        #expect(WindowsRuntimeStopConfirmation.message(
            hasMirroredWindowsApp: true,
            hasQueuedLaunch: false
        ) == "Stopping Windows closes the mirrored Windows app window.")
        #expect(WindowsRuntimeStopConfirmation.message(
            hasMirroredWindowsApp: false,
            hasQueuedLaunch: true
        ) == "The queued app launch will remain pending until Windows reconnects.")
    }
}
