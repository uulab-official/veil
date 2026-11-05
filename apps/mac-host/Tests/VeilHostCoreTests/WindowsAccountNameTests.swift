import Foundation
import Testing

@testable import VeilHostCore

private struct StubInstallMediaBuilder: AutomaticInstallMediaBuilding {
    func prepareMedia(answerFileURL: URL, mediaURL: URL) throws {
        try FileManager.default.createDirectory(at: mediaURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data("media".utf8).write(to: mediaURL)
    }
}

@Suite("Windows account name")
struct WindowsAccountNameTests {
    @Test("names follow Windows local account rules")
    func sanitizesNames() {
        #expect(WindowsAccountName.sanitized("  Jamie  ") == "Jamie")
        #expect(WindowsAccountName.sanitized("최지민") == "최지민")
        #expect(WindowsAccountName.sanitized("a/b\\c[d]e:f;g|h=i,j+k*l?m<n>o@p\"q") == "abcdefghijklmnopq")
        #expect(WindowsAccountName.sanitized("abcdefghijklmnopqrstuvwxyz") == "abcdefghijklmnopqrst")
        #expect(WindowsAccountName.sanitized("name.") == "name")
        #expect(WindowsAccountName.sanitized("Administrator") == nil)
        #expect(WindowsAccountName.sanitized("   ") == nil)
    }

    @Test("the user's choice wins, then this Mac's user name, then Veil")
    func resolvesAccountName() {
        #expect(WindowsAccountName.resolve(preferred: "Jamie", macUserName: "uulab") == "Jamie")
        #expect(WindowsAccountName.resolve(preferred: nil, macUserName: "uulab") == "uulab")
        #expect(WindowsAccountName.resolve(preferred: "///", macUserName: "uulab") == "uulab")
        #expect(WindowsAccountName.resolve(preferred: nil, macUserName: "guest") == "Veil")
    }

    @Test("the answer file creates the account and signs in to it once")
    func answerFileCreatesLocalAccount() {
        let answerFile = LocalVMRuntimeService.automaticInstallAnswerFile(accountName: "Jamie & Co")

        #expect(answerFile.contains("<HideLocalAccountScreen>true</HideLocalAccountScreen>"))
        #expect(answerFile.contains("<Name>Jamie &amp; Co</Name>"))
        #expect(answerFile.contains("<Group>Administrators</Group>"))
        #expect(answerFile.contains("<Username>Jamie &amp; Co</Username>"))
        #expect(answerFile.contains("<LogonCount>1</LogonCount>"))
        #expect(!answerFile.contains("Jamie & Co"))
    }

    @Test("Setup skips Dynamic Update instead of waiting on the VM network")
    func answerFileDisablesDynamicUpdate() {
        let answerFile = LocalVMRuntimeService.automaticInstallAnswerFile(accountName: "Jamie")

        #expect(answerFile.contains("<DynamicUpdate>\n        <Enable>false</Enable>\n        <WillShowUI>Never</WillShowUI>\n      </DynamicUpdate>"))
    }

    @Test("a saved name reaches the next install's answer file")
    func savedNameReachesAnswerFile() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        let home = directory.appendingPathComponent("Home", isDirectory: true)
        try FileManager.default.createDirectory(at: home, withIntermediateDirectories: true)
        let store = JSONVMProfileStore(directory: directory)
        try await store.save(VMProfile.defaultWindows11Arm(createdAt: Date(timeIntervalSince1970: 1_782_752_400), homeDirectory: home))
        let service = LocalVMRuntimeService(
            profileStore: store,
            defaultHomeDirectory: home,
            automaticInstallMediaBuilder: StubInstallMediaBuilder()
        )

        let snapshot = try await service.updateWindowsAccountName("  Jamie  ")
        #expect(snapshot.windowsAccountName == "Jamie")
        #expect(try await store.load()?.windowsAccountName == "Jamie")

        let prepared = try await service.prepareDefaultVM()
        let answerFilePath = try #require(prepared.automaticInstallAnswerFilePath)
        let answerFile = try String(contentsOfFile: answerFilePath, encoding: .utf8)
        #expect(answerFile.contains("<Name>Jamie</Name>"))
    }
}
