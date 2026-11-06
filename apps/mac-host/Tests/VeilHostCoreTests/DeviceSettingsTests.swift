import Foundation
import Testing

@testable import VeilHostCore

@Suite("Device settings")
struct DeviceSettingsTests {
    // MARK: Keyboard

    @Test("Command stays Control by default and becomes the Windows key when chosen")
    func commandKeyMapping() {
        let control = QEMUConsoleKeyboardInputMapper()
        #expect(control.key(charactersIgnoringModifiers: "c", keyCode: 8, modifiers: [.command]) == "ctrl-c")

        let windows = QEMUConsoleKeyboardInputMapper(commandKeyMapping: .windows)
        #expect(windows.key(charactersIgnoringModifiers: "e", keyCode: 14, modifiers: [.command]) == "meta_l-e")
        #expect(windows.key(charactersIgnoringModifiers: "c", keyCode: 8, modifiers: [.control]) == "ctrl-c")
        #expect(
            windows.key(charactersIgnoringModifiers: "s", keyCode: 1, modifiers: [.command, .shift]) == "meta_l-shift-s"
        )
    }

    @Test("Windows key shortcuts are valid QMP key names")
    func windowsShortcutIsSendable() throws {
        let windows = QEMUConsoleKeyboardInputMapper(commandKeyMapping: .windows)
        let key = try #require(windows.key(charactersIgnoringModifiers: "r", keyCode: 15, modifiers: [.command]))
        let command = try QEMUQMPKeyboardCommandBuilder.sendKeyCommand(for: key)
        #expect(command.contains("\"meta_l\""))
    }

    // MARK: Port forwarding

    @Test("port forward rules refuse Veil's ports, privileged ports, and duplicates")
    func validatesRules() throws {
        try VMPortForwardRuleValidator.validate([
            VMPortForwardRule(hostPort: 8_080, guestPort: 80),
            VMPortForwardRule(transport: .udp, hostPort: 8_080, guestPort: 53)
        ])

        #expect(throws: VMPortForwardRuleError.reservedHostPort(18_444)) {
            try VMPortForwardRuleValidator.validate([VMPortForwardRule(hostPort: 18_444, guestPort: 80)])
        }
        #expect(throws: VMPortForwardRuleError.reservedGuestPort(18_444)) {
            try VMPortForwardRuleValidator.validate([VMPortForwardRule(hostBinding: .allInterfaces, hostPort: 9_000, guestPort: 18_444)])
        }
        #expect(throws: VMPortForwardRuleError.reservedGuestPort(445)) {
            try VMPortForwardRuleValidator.validate([VMPortForwardRule(hostPort: 9_445, guestPort: 445)])
        }
        #expect(throws: VMPortForwardRuleError.privilegedHostPort(80)) {
            try VMPortForwardRuleValidator.validate([VMPortForwardRule(hostPort: 80, guestPort: 80)])
        }
        #expect(throws: VMPortForwardRuleError.portOutOfRange(70_000)) {
            try VMPortForwardRuleValidator.validate([VMPortForwardRule(hostPort: 8_080, guestPort: 70_000)])
        }
        #expect(throws: VMPortForwardRuleError.duplicateHostPort(8_080)) {
            try VMPortForwardRuleValidator.validate([
                VMPortForwardRule(hostPort: 8_080, guestPort: 80),
                VMPortForwardRule(hostBinding: .allInterfaces, hostPort: 8_080, guestPort: 81)
            ])
        }
    }

    @Test("user forwards join Veil's own on the single NAT netdev, loopback unless asked")
    func planIncludesForwards() throws {
        var profile = installedProfile()
        profile.portForwards = [
            VMPortForwardRule(id: "web", hostPort: 8_080, guestPort: 80),
            VMPortForwardRule(id: "rdp", hostBinding: .allInterfaces, hostPort: 13_389, guestPort: 3_389),
            VMPortForwardRule(id: "busy", hostPort: 9_000, guestPort: 9_000)
        ]

        let plan = try planner(unavailable: ["busy"]).makePlan(for: profile)
        let netdev = try #require(value(after: "-netdev", in: plan.arguments))

        #expect(netdev.contains("hostfwd=tcp:127.0.0.1:18444-:18444"))
        #expect(netdev.contains("hostfwd=tcp:127.0.0.1:8080-:80"))
        #expect(netdev.contains("hostfwd=tcp:0.0.0.0:13389-:3389"))
        #expect(!netdev.contains(":9000-"))
        #expect(plan.arguments.filter { $0 == "-netdev" }.count == 1)
        #expect(plan.warnings.contains { $0.contains("every network interface") && $0.contains("13389") })
        #expect(plan.warnings.contains { $0.contains("9000") && $0.contains("in use") })
    }

    @Test("a hand-edited profile that shadows the agent port gets no user forwards")
    func planRejectsReservedForwards() throws {
        var profile = installedProfile()
        profile.portForwards = [VMPortForwardRule(hostBinding: .allInterfaces, hostPort: 9_000, guestPort: 18_444)]

        let plan = try planner().makePlan(for: profile)
        let netdev = try #require(value(after: "-netdev", in: plan.arguments))

        #expect(!netdev.contains("9000"))
        #expect(plan.warnings.contains { $0.contains("Port forwarding rules were left out") })
    }

    @Test("forwards are saved to the profile and invalid ones are refused")
    func savesForwardsAndKeyboard() async throws {
        let (service, store) = try makeService()

        let saved = try await service.updatePortForwards([VMPortForwardRule(id: "web", hostPort: 8_080, guestPort: 80)])
        #expect(saved.portForwards?.map(\.id) == ["web"])

        await #expect(throws: VMPortForwardRuleError.reservedHostPort(18_445)) {
            _ = try await service.updatePortForwards([VMPortForwardRule(hostPort: 18_445, guestPort: 80)])
        }

        let keyboard = try await service.updateCommandKeyMapping(.windows)
        #expect(keyboard.commandKeyMapping == .windows)
        let profile = try #require(await store.load())
        #expect(profile.portForwards?.count == 1)
        #expect(profile.commandKeyMapping == .windows)
    }

    // MARK: Removable media

    @Test("every plan has an empty removable CD drive with a tray")
    func planHasRemovableDrive() throws {
        let plan = try planner().makePlan(for: installedProfile())
        #expect(VMRemovableOpticalDrive.isPresent(in: plan.arguments))
        #expect(plan.arguments.contains("ide-cd,bus=veil-cd-ahci.0,drive=veil-cd,id=veil-cd0"))
        #expect(plan.arguments.contains("if=none,id=veil-cd,media=cdrom,readonly=on"))
    }

    @Test("disc insert and eject are QMP commands against the drive's qdev id")
    func removableMediaCommands() throws {
        let insert = try QEMUQMPCommand
            .changeRemovableMedium(deviceID: "veil-cd0", filePath: "/Users/test/My, Disc.iso")
            .jsonLine(id: "1")
        #expect(insert.contains(#""execute":"blockdev-change-medium""#))
        #expect(insert.contains(#""filename":"\/Users\/test\/My, Disc.iso""#))
        #expect(insert.contains(#""read-only-mode":"read-only""#))
        #expect(insert.contains(#""id":"veil-cd0""#))

        let eject = try QEMUQMPCommand.ejectRemovableMedium(deviceID: "veil-cd0").jsonLine(id: "2")
        #expect(eject.contains(#""execute":"eject""#))
        #expect(eject.contains(#""force":true"#))
    }

    @Test("info block output names the inserted disc")
    func parsesInfoBlock() {
        let inserted = VMRemovableMediaStatus.parse(infoBlock: """
        veil-cd (#block173): /Users/test/Disc (1).iso (raw, read-only)
            Attached to:      veil-cd0
            Removable device: not locked, tray closed
        """)
        #expect(inserted == VMRemovableMediaStatus(isDriveAvailable: true, insertedPath: "/Users/test/Disc (1).iso"))

        let empty = VMRemovableMediaStatus.parse(infoBlock: "veil-cd: [not inserted]\r\n    Attached to:      veil-cd0\r\n")
        #expect(empty == VMRemovableMediaStatus(isDriveAvailable: true))

        #expect(VMRemovableMediaStatus.parse(infoBlock: "Device 'veil-cd' not found").isDriveAvailable == false)
    }

    @Test("inserting a disc sends the change only to a running QEMU that has the drive")
    func insertsIntoRunningDrive() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let iso = directory.appendingPathComponent("Tools.iso")
        try Data([0]).write(to: iso)
        let qmp = RecordingQMP(monitorText: "veil-cd (#block12): \(iso.path) (raw, read-only)\r\n")

        let (service, _) = try makeService(
            launchArguments: VMRemovableOpticalDrive.arguments,
            qmp: qmp
        )
        let status = try await service.insertRemovableMedia(path: iso.path)
        #expect(status.insertedPath == iso.path)
        #expect(await qmp.executeNames == ["blockdev-change-medium", "human-monitor-command"])

        let (oldService, _) = try makeService(launchArguments: ["-device", "usb-storage,drive=installer"], qmp: qmp)
        await #expect(throws: VMRemovableMediaError.driveMissing) {
            _ = try await oldService.insertRemovableMedia(path: iso.path)
        }
        await #expect(throws: VMRemovableMediaError.unsupportedMedia(directory.appendingPathComponent("Tools.dmg").path)) {
            _ = try await service.insertRemovableMedia(path: directory.appendingPathComponent("Tools.dmg").path)
        }
        #expect(await qmp.executeNames.count == 2)
    }

    // MARK: Helpers

    private func installedProfile() -> VMProfile {
        var profile = VMProfile.defaultWindows11Arm(createdAt: Date(timeIntervalSince1970: 1_782_752_400))
        profile.virtualDiskPath = "/Users/test/Virtual Machines/Veil/Windows 11 Arm.img"
        profile.sharedFolderPath = "/Users/test/Veil Shared"
        profile.windowsInstalled = true
        return profile
    }

    private func planner(unavailable: Set<String> = []) -> QEMUWindowsBootPlanner {
        QEMUWindowsBootPlanner(
            executablePath: "/opt/homebrew/bin/qemu-system-aarch64",
            isExecutableAvailable: true,
            unavailablePortForwardRuleIDs: unavailable
        )
    }

    private func value(after flag: String, in arguments: [String]) -> String? {
        guard let index = arguments.firstIndex(of: flag), index + 1 < arguments.count else {
            return nil
        }
        return arguments[index + 1]
    }

    private func makeService(
        launchArguments: [String] = [],
        qmp: RecordingQMP = RecordingQMP(monitorText: "")
    ) throws -> (LocalVMRuntimeService, JSONVMProfileStore) {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        let home = directory.appendingPathComponent("Home", isDirectory: true)
        try FileManager.default.createDirectory(at: home, withIntermediateDirectories: true)
        let store = JSONVMProfileStore(directory: directory)
        let record = QEMULaunchRecord(
            pid: 4_242,
            executablePath: "/opt/homebrew/bin/qemu-system-aarch64",
            arguments: launchArguments,
            processLogPath: directory.appendingPathComponent("qemu.log").path,
            monitorSocketPath: directory.appendingPathComponent("monitor.sock").path,
            qmpSocketPath: directory.appendingPathComponent("qmp.sock").path,
            startedAt: Date(timeIntervalSince1970: 1_782_752_400)
        )
        let service = LocalVMRuntimeService(
            profileStore: store,
            defaultHomeDirectory: home,
            qemuLaunchRecordStore: FixedLaunchRecordStore(record: record),
            qemuLaunchProcessIsRunning: { $0 == 4_242 },
            qmpController: qmp
        )
        return (service, store)
    }
}

private struct FixedLaunchRecordStore: QEMULaunchRecordStore {
    var record: QEMULaunchRecord?

    func loadLatest() async throws -> QEMULaunchRecord? {
        record
    }
}

private actor RecordingQMP: QEMUQMPControlling {
    private let monitorText: String
    private(set) var executeNames: [String] = []

    init(monitorText: String) {
        self.monitorText = monitorText
    }

    func execute(
        _ commands: [QEMUQMPCommand],
        socketPath: String,
        idleTimeoutSeconds: Int
    ) async throws -> [QEMUQMPReply] {
        commands.enumerated().map { index, command in
            executeNames.append(command.executeName)
            return QEMUQMPReply(
                id: "veil-qmp-\(index)",
                isSuccess: true,
                textReturn: command.executeName == "human-monitor-command" ? monitorText : nil
            )
        }
    }
}
