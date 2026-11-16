import Testing
import VeilHostCore
@testable import VeilHostShell

struct WindowsRuntimeFailurePresentationTests {
    @Test("failed runtime prefers the user-facing error and offers recovery")
    func usesErrorMessage() {
        let presentation = WindowsRuntimeFailurePresentation.resolve(
            state: .failed,
            errorMessage: "QEMU could not attach the Windows disk.",
            snapshotDetail: "The last start attempt failed."
        )

        #expect(presentation?.title == "Windows needs attention")
        #expect(presentation?.message == "QEMU could not attach the Windows disk.")
        #expect(presentation?.refreshTitle == "Refresh status")
        #expect(presentation?.detailsTitle == "Open settings")
    }

    @Test("failed runtime falls back to snapshot detail when the model error is empty")
    func usesSnapshotDetail() {
        let presentation = WindowsRuntimeFailurePresentation.resolve(
            state: .failed,
            errorMessage: "  ",
            snapshotDetail: "The guest did not reach a usable boot state."
        )

        #expect(presentation?.message == "The guest did not reach a usable boot state.")
    }

    @Test("non-failed runtime does not show a failure banner")
    func ignoresHealthyRuntime() {
        #expect(WindowsRuntimeFailurePresentation.resolve(
            state: .running,
            errorMessage: "stale error",
            snapshotDetail: "running"
        ) == nil)
    }
}
