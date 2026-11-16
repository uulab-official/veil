import Foundation
import Testing

@testable import VeilHostCore

@Suite("UEFI boot entries")
struct UEFIBootEntriesTests {
    private func varsFile(containing title: String?) throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("\(UUID().uuidString)-uefi-vars.fd")
        var bytes = Data(repeating: 0xff, count: 4_096)
        if let title {
            bytes.append(contentsOf: title.utf16.flatMap { [UInt8($0 & 0xff), UInt8($0 >> 8)] })
        }
        bytes.append(Data(repeating: 0xff, count: 4_096))
        try bytes.write(to: url)
        return url
    }

    @Test("Setup's Windows Boot Manager entry is found in the variable store")
    func findsWindowsBootManager() throws {
        #expect(UEFIBootEntries.registersWindowsBootManager(varsURL: try varsFile(containing: "Windows Boot Manager")))
        #expect(!UEFIBootEntries.registersWindowsBootManager(varsURL: try varsFile(containing: "UEFI QEMU QEMU USB HARDDRIVE")))
        #expect(!UEFIBootEntries.registersWindowsBootManager(varsURL: try varsFile(containing: nil)))
        #expect(!UEFIBootEntries.registersWindowsBootManager(varsURL: URL(fileURLWithPath: "/nonexistent/uefi-vars.fd")))
    }

    @Test("a Windows Boot Manager entry counts as installed without the guest agent")
    func bootManagerMeansInstalled() {
        let evidence = LocalVMRuntimeService.installEvidence(
            bootPathReadiness: (isReady: true, detail: ""),
            windowsInstalled: false,
            guestAgentVersion: nil,
            virtualDiskAllocatedBytes: 18 * 1_024 * 1_024 * 1_024,
            windowsBootManagerRegistered: true
        )
        #expect(evidence.kind == .windowsBootManager)
        #expect(evidence.isInstalled)
    }
}
