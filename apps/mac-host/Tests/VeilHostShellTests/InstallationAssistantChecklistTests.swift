import Testing
import VeilHostCore

@testable import VeilHostShell

@Suite("Installation Assistant checklist")
struct InstallationAssistantChecklistTests {
    private func step(_ id: String, _ state: VMInstallationStepState) -> VMInstallationStep {
        VMInstallationStep(id: id, title: "runtime title", detail: "runtime detail", state: state)
    }

    @Test("what continuing creates is shown as waiting, not as a problem")
    func notYetCreatedIsWaiting() {
        let items = InstallationAssistantChecklistItem.items(for: [
            step("windows-installer", .complete),
            step("virtual-disk", .blocked),
            step("shared-folder", .pending),
            step("auto-install-answer-file", .blocked),
            step("guest-agent", .pending)
        ])

        #expect(items.map(\.state) == [.complete, .pending, .pending, .pending, .pending])
        #expect(items.map(\.title) == [
            "Windows 11 installer", "Virtual disk", "Shared folder", "Automatic Windows Setup", "Veil tools for Windows"
        ])
        #expect(items[0].detail == "Ready")
        #expect(items[1].detail == "Created when you continue")
        #expect(items[4].detail == "Installed automatically at the end of Windows Setup")
        // The runtime's own wording stays available as the tooltip.
        #expect(items.allSatisfy { $0.technicalDetail == "runtime detail" })
    }

    @Test("an installer Veil cannot read is the one problem to fix")
    func unreadableInstallerIsBlocked() {
        let items = InstallationAssistantChecklistItem.items(for: [step("windows-installer", .blocked)])

        #expect(items.first?.state == .blocked)
        #expect(items.first?.detail == "Veil can't read this file. Choose the installer again.")
    }

    @Test("finished steps read as ready, and installed tools as installed")
    func completeSteps() {
        let items = InstallationAssistantChecklistItem.items(for: [
            step("virtual-disk", .complete),
            step("guest-agent", .complete)
        ])

        #expect(items.map(\.detail) == ["Ready", "Installed"])
        #expect(items.allSatisfy { $0.state == .complete })
    }

    @Test("a step the assistant does not know is shown as the runtime describes it")
    func unknownStepPassesThrough() {
        let items = InstallationAssistantChecklistItem.items(for: [step("something-new", .blocked)])

        #expect(items == [
            InstallationAssistantChecklistItem(
                id: "something-new", title: "runtime title", detail: "runtime detail",
                state: .blocked, technicalDetail: "runtime detail"
            )
        ])
    }
}
