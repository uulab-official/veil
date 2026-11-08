import Foundation
import Testing

@testable import VeilHostCore

@Suite("Guest tools")
struct GuestToolsTests {
    @Test("an agent older than the bundled build needs an update")
    func outdatedAgent() {
        #expect(GuestToolsUpdatePolicy.isOutdated(installedVersion: "0.1.0", bundledVersion: "0.1.0+abc"))
        #expect(GuestToolsUpdatePolicy.isOutdated(installedVersion: "0.1.0+old", bundledVersion: "0.1.0+abc"))
        #expect(!GuestToolsUpdatePolicy.isOutdated(installedVersion: "0.1.0+abc", bundledVersion: "0.1.0+abc"))
    }

    @Test("the update disc stays inserted until the new agent connects")
    func updateDiscStaysUntilTheNewAgentConnects() {
        #expect(!GuestToolsUpdatePolicy.ejectsUpdateMedia(installedVersion: "0.1.0+old", bundledVersion: "0.1.0+abc"))
        #expect(!GuestToolsUpdatePolicy.ejectsUpdateMedia(installedVersion: nil, bundledVersion: "0.1.0+abc"))
        #expect(GuestToolsUpdatePolicy.ejectsUpdateMedia(installedVersion: "0.1.0+abc", bundledVersion: "0.1.0+abc"))
        #expect(GuestToolsUpdatePolicy.ejectsUpdateMedia(installedVersion: "0.1.0", bundledVersion: nil))
    }

    @Test("an update waits minutes for a late Windows approval")
    func updateWaitsForLateApproval() {
        #expect(GuestToolsUpdatePolicy.approvalWaitSeconds >= 600)
        #expect(GuestToolsUpdatePolicy.approvalReminderSeconds < GuestToolsUpdatePolicy.approvalWaitSeconds)
    }

    @Test("nothing is outdated without a stamped bundle or a connected agent")
    func unknownVersions() {
        #expect(!GuestToolsUpdatePolicy.isOutdated(installedVersion: "0.1.0", bundledVersion: "0.1.0"))
        #expect(!GuestToolsUpdatePolicy.isOutdated(installedVersion: "0.1.0", bundledVersion: nil))
        #expect(!GuestToolsUpdatePolicy.isOutdated(installedVersion: nil, bundledVersion: "0.1.0+abc"))
    }

    @Test("the tools inside the app win over the repository copy and report their version")
    func bundledToolsLocation() throws {
        let resources = FileManager.default.temporaryDirectory
            .appendingPathComponent("veil-tools-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: resources) }
        let tools = resources.appendingPathComponent(GuestToolsBundle.resourceDirectoryName, isDirectory: true)

        #expect(GuestToolsBundle.sourceURL(resourceURL: resources) == GuestToolsBundle.repositoryURL)

        try FileManager.default.createDirectory(at: tools.appendingPathComponent("scripts"), withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: tools.appendingPathComponent("app"), withIntermediateDirectories: true)
        try "0.1.0+abc\n".write(
            to: tools.appendingPathComponent("app/\(GuestToolsBundle.versionFileName)"),
            atomically: true,
            encoding: .utf8
        )

        #expect(GuestToolsBundle.sourceURL(resourceURL: resources) == tools)
        #expect(GuestToolsBundle.version(at: tools) == "0.1.0+abc")
    }

    @Test("the update disc carries the bundle with its own U.cmd entry point")
    func updateMediaLayout() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("veil-tools-media-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let bundle = root.appendingPathComponent("Veil Guest Agent", isDirectory: true)
        try FileManager.default.createDirectory(at: bundle, withIntermediateDirectories: true)
        try "@echo off\n".write(to: bundle.appendingPathComponent("V.cmd"), atomically: true, encoding: .utf8)
        let media = root.appendingPathComponent(GuestToolsUpdateMedia.fileName)

        var stagedEntryPoint: String?
        var volumeName: String?
        try GuestToolsUpdateMedia.build(agentBundleURL: bundle, mediaURL: media) { _, arguments in
            let staging = URL(fileURLWithPath: arguments.last!)
            stagedEntryPoint = try? String(
                contentsOf: staging.appendingPathComponent("Veil Guest Agent/U.cmd"),
                encoding: .utf8
            )
            volumeName = arguments[arguments.firstIndex(of: "-default-volume-name")! + 1]
            let output = arguments[arguments.firstIndex(of: "-o")! + 1]
            FileManager.default.createFile(atPath: output, contents: Data("iso".utf8))
            return 0
        }

        #expect(stagedEntryPoint == "@echo off\n")
        #expect(volumeName == GuestToolsUpdateMedia.volumeName)
        #expect(FileManager.default.fileExists(atPath: media.path))
    }

    @Test("the update command runs U.cmd, which an older VEIL_AUTO does not have")
    func updateCommandTargetsUpdateDisc() throws {
        #expect(QEMUGuestToolsUpdateKeySequence.commandText.contains(#"Veil Guest Agent\U.cmd"#))
        #expect(!QEMUGuestToolsUpdateKeySequence.commandText.contains("V.cmd"))
        #expect(try QEMUGuestToolsUpdateKeySequence.steps.last?.key == "ret")
    }
}
