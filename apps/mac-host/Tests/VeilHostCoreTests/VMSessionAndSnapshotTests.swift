import Foundation
import Testing

@testable import VeilHostCore

@Suite("QEMU QMP client")
struct QEMUQMPClientTests {
    @Test("builds QMP command lines with correlation ids")
    func buildsCommandLinesWithCorrelationIds() throws {
        #expect(try QEMUQMPCommand.stop.jsonLine(id: "veil-qmp-0") == #"{"execute":"stop","id":"veil-qmp-0"}"#)
        #expect(try QEMUQMPCommand.cont.jsonLine(id: "veil-qmp-1") == #"{"execute":"cont","id":"veil-qmp-1"}"#)
        #expect(
            try QEMUQMPCommand.capabilities.jsonLine(id: QEMUQMPClient.handshakeId)
                == #"{"execute":"qmp_capabilities","id":"veil-qmp-capabilities"}"#
        )
    }

    @Test("shell quotes memory state paths containing spaces")
    func shellQuotesMemoryStatePathsWithSpaces() throws {
        let line = try QEMUQMPCommand
            .saveMemoryState(filePath: "/Users/test/Virtual Machines/Veil/Windows 11 Arm.vmsave")
            .jsonLine(id: "veil-qmp-0")

        // JSONSerialization escapes forward slashes in the JSON string representation.
        #expect(line.replacingOccurrences(of: #"\/"#, with: "/")
            .contains(#"exec:cat > '/Users/test/Virtual Machines/Veil/Windows 11 Arm.vmsave'"#))
        #expect(line.contains(#""execute":"migrate""#))
    }

    @Test("escapes single quotes so a crafted path cannot break out of the exec URI")
    func escapesSingleQuotesInMemoryStatePaths() {
        #expect(
            QEMUQMPCommand.shellSingleQuoted("/tmp/it's here/rm -rf")
                == #"'/tmp/it'\''s here/rm -rf'"#
        )
    }

    @Test("parses replies while skipping the greeting and asynchronous events")
    func parsesRepliesSkippingGreetingAndEvents() {
        let output = """
        {"QMP": {"version": {"qemu": {"major": 9}}, "capabilities": []}}
        {"return": {}, "id": "veil-qmp-capabilities"}
        {"timestamp": {"seconds": 1}, "event": "STOP"}
        {"return": {"status": "paused", "running": false}, "id": "veil-qmp-0"}
        {"return": "snapshot list", "id": "veil-qmp-1"}
        {"error": {"class": "GenericError", "desc": "Device has no medium"}, "id": "veil-qmp-2"}
        """

        let replies = QEMUQMPClient.parseReplies(from: output)

        #expect(replies.count == 4)
        #expect(replies[1].statusReturn == "paused")
        #expect(replies[1].isRunning == false)
        #expect(replies[2].textReturn == "snapshot list")
        #expect(replies[3].isSuccess == false)
        #expect(replies[3].errorClass == "GenericError")
        #expect(replies[3].errorMessage == "Device has no medium")
        #expect(QEMUQMPClient.parseEventNames(from: output) == ["STOP"])
    }

    @Test("correlates replies back to the command order that produced them")
    func correlatesRepliesToCommandOrder() async throws {
        let client = QEMUQMPClient(
            fileExists: { _ in true },
            processRunner: { _, _ in
                QEMUProcessOutcome(
                    terminationStatus: 0,
                    standardOutput: """
                    {"QMP": {"version": {}}}
                    {"return": {}, "id": "veil-qmp-capabilities"}
                    {"return": {"status": "running", "running": true}, "id": "veil-qmp-1"}
                    {"return": {}, "id": "veil-qmp-0"}
                    """
                )
            }
        )

        let replies = try await client.execute([.stop, .queryStatus], socketPath: "/tmp/veil.qmp.sock")

        #expect(replies.count == 2)
        #expect(replies[0].id == "veil-qmp-0")
        #expect(replies[1].statusReturn == "running")
    }

    @Test("fails loudly when the QMP socket is missing")
    func failsWhenSocketMissing() async {
        let client = QEMUQMPClient(fileExists: { _ in false })

        await #expect(throws: QEMUQMPClientError.socketUnavailable("/tmp/missing.sock")) {
            _ = try await client.execute([.stop], socketPath: "/tmp/missing.sock")
        }
    }

    @Test("fails when QEMU answers nothing on a present socket")
    func failsWhenQEMUAnswersNothing() async {
        let client = QEMUQMPClient(
            fileExists: { _ in true },
            processRunner: { _, _ in QEMUProcessOutcome(terminationStatus: 1, standardOutput: "") }
        )

        await #expect(throws: QEMUQMPClientError.transportUnavailable("/tmp/veil.qmp.sock")) {
            _ = try await client.execute([.stop], socketPath: "/tmp/veil.qmp.sock")
        }
    }

    @Test("reports a missing reply against the command that went unanswered")
    func reportsMissingReplyForUnansweredCommand() async {
        let client = QEMUQMPClient(
            fileExists: { _ in true },
            processRunner: { _, _ in
                QEMUProcessOutcome(
                    terminationStatus: 0,
                    standardOutput: #"{"return": {}, "id": "veil-qmp-capabilities"}"#
                )
            }
        )

        await #expect(throws: QEMUQMPClientError.noReply(command: QEMUQMPCommand.stop.label)) {
            _ = try await client.execute([.stop], socketPath: "/tmp/veil.qmp.sock")
        }
    }

    @Test("surfaces a rejected command instead of returning it as success")
    func surfacesRejectedCommand() async {
        let client = QEMUQMPClient(
            fileExists: { _ in true },
            processRunner: { _, _ in
                QEMUProcessOutcome(
                    terminationStatus: 0,
                    standardOutput: #"{"error": {"class": "GenericError", "desc": "not supported"}, "id": "veil-qmp-0"}"#
                )
            }
        )

        await #expect(throws: QEMUQMPClientError.commandFailed(command: QEMUQMPCommand.stop.label, message: "not supported")) {
            _ = try await client.run(.stop, socketPath: "/tmp/veil.qmp.sock")
        }
    }

    @Test("never waits forever on an idle QMP socket")
    func neverWaitsForeverOnIdleSocket() {
        // `nc -w 0` means "no timeout" on macOS, which would hang the caller.
        #expect(QEMUQMPClient.transportScript(idleTimeoutSeconds: 0).contains("-w 1"))
        #expect(QEMUQMPClient.transportScript(idleTimeoutSeconds: 3).contains("-w 3"))
    }
}

@Suite("QEMU boot argument fingerprint")
struct QEMUBootArgumentsFingerprintTests {
    private static let baseArguments = [
        "-machine", "virt,highmem=on",
        "-accel", "hvf",
        "-cpu", "host",
        "-smp", "4",
        "-m", "8192M"
    ]

    @Test("ignores per-launch plumbing that legitimately changes on every start")
    func ignoresPerLaunchPlumbing() {
        let first = Self.baseArguments + [
            "-serial", "file:/tmp/a.serial.log",
            "-monitor", "unix:/tmp/vq-1111.sock,server,nowait",
            "-qmp", "unix:/tmp/vq-2222.qmp.sock,server,nowait",
            "-vnc", "127.0.0.1:1",
            "-display", "none"
        ]
        let second = Self.baseArguments + [
            "-serial", "file:/tmp/b.serial.log",
            "-monitor", "unix:/tmp/vq-3333.sock,server,nowait",
            "-qmp", "unix:/tmp/vq-4444.qmp.sock,server,nowait",
            "-vnc", "127.0.0.1:7",
            "-display", "none",
            "-incoming", "exec:cat '/tmp/state.vmsave'"
        ]

        #expect(
            QEMUBootArgumentsFingerprint.value(for: first)
                == QEMUBootArgumentsFingerprint.value(for: second)
        )
    }

    @Test("changes when the guest-visible machine changes")
    func changesWhenMachineChanges() {
        var changed = Self.baseArguments
        changed[9] = "4096M"

        #expect(
            QEMUBootArgumentsFingerprint.value(for: Self.baseArguments)
                != QEMUBootArgumentsFingerprint.value(for: changed)
        )
    }

    @Test("cannot collide by concatenating adjacent arguments")
    func cannotCollideByConcatenation() {
        #expect(
            QEMUBootArgumentsFingerprint.value(for: ["-m", "8192M"])
                != QEMUBootArgumentsFingerprint.value(for: ["-m8192M"])
        )
    }

    @Test("tolerates a trailing per-launch flag with no value")
    func toleratesTrailingFlagWithoutValue() {
        #expect(QEMUBootArgumentsFingerprint.machineShapingArguments(["-cpu", "host", "-qmp"]) == ["-cpu", "host"])
    }

    @Test("produces a recognizable, fixed-width fingerprint")
    func producesRecognizableFingerprint() {
        let value = QEMUBootArgumentsFingerprint.value(for: Self.baseArguments)

        #expect(value.hasPrefix(QEMUBootArgumentsFingerprint.schemeIdentifier + ":"))
        #expect(value.count == QEMUBootArgumentsFingerprint.schemeIdentifier.count + 1 + 16)
    }

    @Test("ignores host port forwarding so toggling the shared folder keeps a suspended session")
    func ignoresHostPortForwarding() {
        let withoutShare = Self.baseArguments + [
            "-netdev", "user,id=net0,hostfwd=tcp:127.0.0.1:18444-:18444",
            "-device", "usb-net,netdev=net0"
        ]
        let withShare = Self.baseArguments + [
            "-netdev", "user,id=net0,hostfwd=tcp:127.0.0.1:18444-:18444,hostfwd=tcp:127.0.0.1:18445-:445",
            "-device", "usb-net,netdev=net0"
        ]

        #expect(
            QEMUBootArgumentsFingerprint.value(for: withoutShare)
                == QEMUBootArgumentsFingerprint.value(for: withShare)
        )
    }

    @Test("ignores a changed host forward address on an otherwise identical machine")
    func ignoresChangedForwardAddress() {
        let allInterfaces = Self.baseArguments + ["-netdev", "user,id=net0,hostfwd=tcp::18444-:18444"]
        let loopbackOnly = Self.baseArguments + ["-netdev", "user,id=net0,hostfwd=tcp:127.0.0.1:18444-:18444"]

        #expect(
            QEMUBootArgumentsFingerprint.value(for: allInterfaces)
                == QEMUBootArgumentsFingerprint.value(for: loopbackOnly)
        )
    }

    @Test("still changes when the network device itself changes")
    func changesWhenNetworkDeviceChanges() {
        let usbNet = Self.baseArguments + [
            "-netdev", "user,id=net0,hostfwd=tcp:127.0.0.1:18444-:18444",
            "-device", "usb-net,netdev=net0"
        ]
        let virtioNet = Self.baseArguments + [
            "-netdev", "user,id=net0,hostfwd=tcp:127.0.0.1:18444-:18444",
            "-device", "virtio-net-pci,netdev=net0"
        ]

        #expect(
            QEMUBootArgumentsFingerprint.value(for: usbNet)
                != QEMUBootArgumentsFingerprint.value(for: virtioNet)
        )
    }

    @Test("still changes when a non-forwarding netdev component changes")
    func changesWhenNetdevIdentityChanges() {
        let first = Self.baseArguments + ["-netdev", "user,id=net0,hostfwd=tcp:127.0.0.1:18445-:445"]
        let second = Self.baseArguments + ["-netdev", "user,id=net1,hostfwd=tcp:127.0.0.1:18445-:445"]

        #expect(
            QEMUBootArgumentsFingerprint.value(for: first)
                != QEMUBootArgumentsFingerprint.value(for: second)
        )
    }

    @Test("keeps every non-forwarding netdev component in place")
    func keepsNonForwardingComponents() {
        #expect(
            QEMUBootArgumentsFingerprint.withoutHostForwarding(
                "user,id=net0,hostfwd=tcp:127.0.0.1:18444-:18444,net=10.0.2.0/24,hostfwd=tcp:127.0.0.1:18445-:445"
            ) == "user,id=net0,net=10.0.2.0/24"
        )
    }

    @Test("recognizes fingerprints written before forwarding was excluded")
    func recognizesSupersededScheme() {
        #expect(QEMUBootArgumentsFingerprint.isFromSupersededScheme("fnv1a64:0123456789abcdef"))
        #expect(
            !QEMUBootArgumentsFingerprint.isFromSupersededScheme(
                QEMUBootArgumentsFingerprint.value(for: Self.baseArguments)
            )
        )
    }

    @Test("does not mistake an unrecognized fingerprint for the superseded scheme")
    func doesNotMistakeUnknownScheme() {
        #expect(!QEMUBootArgumentsFingerprint.isFromSupersededScheme("sha256:deadbeef"))
    }
}

@Suite("QEMU VM suspension")
struct QEMUVMSuspensionControllerTests {
    private static func launchRecord(qmpSocketPath: String? = "/tmp/veil.qmp.sock") -> QEMULaunchRecord {
        QEMULaunchRecord(
            pid: 4242,
            executablePath: "/opt/homebrew/bin/qemu-system-aarch64",
            arguments: ["-m", "8192M"],
            displayMode: .vncLoopback,
            processLogPath: "/tmp/qemu.log",
            monitorSocketPath: "/tmp/veil.sock",
            qmpSocketPath: qmpSocketPath,
            startedAt: Date(timeIntervalSince1970: 1_770_000_000)
        )
    }

    @Test("pauses the guest, streams memory state, then quits QEMU")
    func pausesStreamsThenQuits() async throws {
        let qmp = FakeQMPControl(migrationStatuses: ["setup", "active", "completed"])
        let controller = QEMUVMSuspensionController(
            qmp: qmp,
            fileByteCount: { _ in 4_831_838_208 },
            now: { Date(timeIntervalSince1970: 1_770_000_100) },
            sleeper: { _ in }
        )

        let record = try await controller.suspend(
            launchRecord: Self.launchRecord(),
            planArguments: ["-m", "8192M"],
            virtualDiskPath: "/Users/test/Virtual Machines/Veil/Windows 11 Arm.img",
            stateFilePath: "/Users/test/Virtual Machines/Veil/Windows 11 Arm.vmsave",
            pollAttempts: 5,
            pollIntervalNanoseconds: 1
        )

        #expect(record.migrationStatus == "completed")
        #expect(record.stateFileByteCount == 4_831_838_208)
        #expect(record.stateFilePath == "/Users/test/Virtual Machines/Veil/Windows 11 Arm.vmsave")
        #expect(record.machineFingerprint == QEMUBootArgumentsFingerprint.value(for: ["-m", "8192M"]))
        #expect(record.displayMode == .vncLoopback)

        let executed = await qmp.executeNames
        // Pausing before the stream is what makes the save converge instead of chasing dirty pages.
        #expect(executed.first == "stop")
        #expect(executed.contains("migrate"))
        #expect(executed.last == "quit")
    }

    @Test("keeps the guest paused and reports the terminal state when the save fails")
    func reportsFailedMemoryStateSave() async {
        let controller = QEMUVMSuspensionController(
            qmp: FakeQMPControl(migrationStatuses: ["active", "failed"]),
            sleeper: { _ in }
        )

        await #expect(throws: VMSuspensionError.memoryStateSaveFailed(status: "failed")) {
            _ = try await controller.suspend(
                launchRecord: Self.launchRecord(),
                planArguments: ["-m", "8192M"],
                virtualDiskPath: "/tmp/disk.img",
                stateFilePath: "/tmp/disk.vmsave",
                pollAttempts: 5,
                pollIntervalNanoseconds: 1
            )
        }
    }

    @Test("times out with the last observed migration state rather than hanging")
    func timesOutWithLastObservedState() async {
        let controller = QEMUVMSuspensionController(
            qmp: FakeQMPControl(migrationStatuses: ["active", "active", "active"]),
            sleeper: { _ in }
        )

        await #expect(throws: VMSuspensionError.memoryStateSaveTimedOut(seconds: 0, latestStatus: "active")) {
            _ = try await controller.suspend(
                launchRecord: Self.launchRecord(),
                planArguments: [],
                virtualDiskPath: "/tmp/disk.img",
                stateFilePath: "/tmp/disk.vmsave",
                pollAttempts: 3,
                pollIntervalNanoseconds: 1
            )
        }
    }

    @Test("refuses to suspend a machine with no QMP control socket")
    func refusesSuspendWithoutQMPSocket() async {
        let controller = QEMUVMSuspensionController(qmp: FakeQMPControl(), sleeper: { _ in })

        await #expect(throws: VMSuspensionError.qmpUnavailable) {
            _ = try await controller.suspend(
                launchRecord: Self.launchRecord(qmpSocketPath: "   "),
                planArguments: [],
                virtualDiskPath: "/tmp/disk.img",
                stateFilePath: "/tmp/disk.vmsave"
            )
        }
    }

    @Test("keeps guest memory out of the diagnostics tree")
    func keepsGuestMemoryOutOfDiagnostics() {
        let path = QEMUVMSuspensionController.defaultStateFilePath(
            virtualDiskPath: "/Users/test/Virtual Machines/Veil/Windows 11 Arm.img"
        )

        #expect(path == "/Users/test/Virtual Machines/Veil/Windows 11 Arm.vmsave")
        #expect(!path.contains("/Diagnostics/"))
    }

    @Test("unpauses the guest once the incoming stream is loaded")
    func unpausesGuestAfterIncomingLoad() async throws {
        let qmp = FakeQMPControl()
        let controller = QEMUVMSuspensionController(qmp: qmp, sleeper: { _ in })

        try await controller.resumeLoadedMachine(qmpSocketPath: "/tmp/veil.qmp.sock")

        let executed = await qmp.executeNames
        #expect(executed == ["cont"])
    }

    @Test("retries the resume handshake while the QMP socket is still appearing")
    func retriesResumeHandshakeWhileSocketAppears() async throws {
        let qmp = FakeQMPControl(failuresBeforeSuccess: 3)
        let controller = QEMUVMSuspensionController(qmp: qmp, sleeper: { _ in })

        try await controller.resumeLoadedMachine(
            qmpSocketPath: "/tmp/veil.qmp.sock",
            socketWaitAttempts: 5,
            socketWaitIntervalNanoseconds: 1
        )

        let executed = await qmp.executeNames
        #expect(executed.count == 4)
    }
}

@Suite("QEMU incoming memory state arguments")
struct QEMUIncomingMemoryStateArgumentTests {
    private static let plan = QEMUWindowsBootPlan(
        executablePath: "/opt/homebrew/bin/qemu-system-aarch64",
        isExecutableAvailable: true,
        summary: "test plan",
        arguments: ["-machine", "virt,highmem=on", "-display", "default"],
        warnings: []
    )

    @Test("attaches the suspended stream only when resuming")
    func attachesSuspendedStreamOnlyWhenResuming() throws {
        let planner = QEMUWindowsBootLaunchPlanner()
        let coldBoot = planner.makeArguments(
            from: Self.plan,
            serialLogPath: "/tmp/a.serial.log",
            monitorSocketPath: "/tmp/a.sock",
            qmpSocketPath: "/tmp/a.qmp.sock"
        )
        let resumed = planner.makeArguments(
            from: Self.plan,
            serialLogPath: "/tmp/a.serial.log",
            monitorSocketPath: "/tmp/a.sock",
            qmpSocketPath: "/tmp/a.qmp.sock",
            incomingMemoryStatePath: "/Users/test/Virtual Machines/Veil/Windows 11 Arm.vmsave"
        )

        #expect(!coldBoot.contains("-incoming"))
        let incomingIndex = try #require(resumed.firstIndex(of: "-incoming"))
        #expect(
            resumed[resumed.index(after: incomingIndex)]
                == "exec:cat '/Users/test/Virtual Machines/Veil/Windows 11 Arm.vmsave'"
        )
    }
}

@Suite("VM session action reports")
struct VMSessionActionReportTests {
    @Test("a suspended session offers resume and records durable evidence")
    func suspendedSessionOffersResume() {
        let report = VMSessionActionReportFactory.make(
            action: .suspend,
            snapshot: .suspendedQEMU,
            generatedAt: Date(timeIntervalSince1970: 1_770_000_200)
        )

        #expect(report.kind == "vmSessionAction")
        #expect(report.status == .suspended)
        #expect(report.canResume)
        #expect(!report.canSuspend)
        #expect(report.persistence.isSupported)
        #expect(report.persistence.mode == VMSessionPersistenceSummary.memoryStateFileMode)
        #expect(report.persistence.machineFingerprint == "fnv1a64:0a1b2c3d4e5f6071")
        #expect(report.nextActions.contains { $0.contains("vm-resume") })
    }

    @Test("a running session offers suspend and clears consumed session evidence")
    func runningSessionOffersSuspend() {
        let report = VMSessionActionReportFactory.make(
            action: .resume,
            snapshot: .runningQEMU,
            generatedAt: Date(timeIntervalSince1970: 1_770_000_300)
        )

        #expect(report.status == .resumed)
        #expect(report.canSuspend)
        #expect(!report.canResume)
        #expect(report.persistence.suspendedAt == nil)
        #expect(report.nextActions.contains { $0.contains("vm-suspend") })
    }

    @Test("a stopped VM points at starting Windows before suspending it")
    func stoppedVMPointsAtStart() {
        let report = VMSessionActionReportFactory.make(
            action: .status,
            snapshot: .stoppedQEMU,
            generatedAt: Date(timeIntervalSince1970: 1_770_000_400)
        )

        #expect(report.status == .stopped)
        #expect(!report.canSuspend)
        #expect(!report.canResume)
        #expect(report.nextActions.contains { $0.contains("qemu-start") })
    }

    @Test("the Apple Virtualization fallback reports session persistence as unsupported")
    func appleVirtualizationReportsUnsupportedPersistence() {
        let report = VMSessionActionReportFactory.make(
            action: .status,
            snapshot: .runningAppleVirtualization,
            generatedAt: Date(timeIntervalSince1970: 1_770_000_500)
        )

        #expect(!report.persistence.isSupported)
        #expect(report.persistence.mode == VMSessionPersistenceSummary.unsupportedMode)
        #expect(report.persistence.stateFilePath == nil)
        #expect(!report.canSuspend)
    }

    @Test("a failed suspend never claims the session was persisted")
    func failedSuspendNeverClaimsPersistence() {
        let report = VMSessionActionReportFactory.make(
            action: .suspend,
            snapshot: .runningQEMU,
            generatedAt: Date(timeIntervalSince1970: 1_770_000_600),
            errorMessage: "QEMU rejected the Windows VM memory state save."
        )

        #expect(report.status == .failed)
        #expect(!report.canSuspend)
        #expect(!report.canResume)
        #expect(report.errorMessage != nil)
    }
}

@Suite("VM runtime model session controls")
struct VMRuntimeModelSessionTests {
    @Test("offers suspend only while Windows is running")
    @MainActor
    func offersSuspendOnlyWhileRunning() async {
        let model = VMRuntimeModel(service: SessionVMRuntimeService(snapshot: .runningQEMU))
        await model.load()

        #expect(model.canSuspend)
        #expect(!model.canResume)
    }

    @Test("offers resume only when a saved memory state file exists")
    @MainActor
    func offersResumeOnlyWithSavedState() async {
        let withState = VMRuntimeModel(service: SessionVMRuntimeService(snapshot: .suspendedQEMU))
        await withState.load()
        #expect(withState.canResume)

        var orphanedSnapshot = VMRuntimeSnapshot.suspendedQEMU
        orphanedSnapshot.suspendedSession = nil
        let withoutState = VMRuntimeModel(service: SessionVMRuntimeService(snapshot: orphanedSnapshot))
        await withoutState.load()
        #expect(!withoutState.canResume)
    }

    @Test("suspends into the suspended state")
    @MainActor
    func suspendsIntoSuspendedState() async {
        let service = SessionVMRuntimeService(snapshot: .runningQEMU, suspendedSnapshot: .suspendedQEMU)
        let model = VMRuntimeModel(service: service)
        await model.load()

        await model.suspend()

        #expect(model.snapshot?.state == .suspended)
        #expect(model.statusText == "VM suspended")
        #expect(model.errorMessage == nil)
        #expect(service.suspendCount == 1)
    }

    @Test("keeps the VM suspended when resume fails so the saved state can be retried")
    @MainActor
    func keepsVMSuspendedWhenResumeFails() async {
        let service = SessionVMRuntimeService(
            snapshot: .suspendedQEMU,
            resumeError: VMSuspensionError.machineConfigurationChanged(expected: "fnv1a64:a", actual: "fnv1a64:b")
        )
        let model = VMRuntimeModel(service: service)
        await model.load()

        await model.resume()

        #expect(model.snapshot?.state == .suspended)
        #expect(model.errorMessage?.contains("configuration changed") == true)
        #expect(model.canResume)
    }

    @Test("reports suspend as unsupported instead of silently stopping the VM")
    @MainActor
    func reportsSuspendUnsupportedInsteadOfStopping() async {
        let service = SessionVMRuntimeService(
            snapshot: .runningAppleVirtualization,
            suspendError: VMRuntimeError.suspendNotSupported
        )
        let model = VMRuntimeModel(service: service)
        await model.load()

        await model.suspend()

        #expect(model.snapshot?.state == .running)
        #expect(model.errorMessage?.contains("cannot suspend") == true)
    }
}

@Suite("QEMU VM snapshots")
struct QEMUVMSnapshotTests {
    @Test("parses the QEMU snapshot table from both running and offline listings")
    func parsesSnapshotTable() {
        let running = """
        List of snapshots present on all disks:
        ID        TAG                 VM SIZE                DATE     VM CLOCK     ICOUNT
        1         before-update      4.02 GiB 2026-07-29 10:19:58 00:14:07.221
        2         clean-install      3.10 GiB 2026-07-28 22:04:11 00:02:31.004 123456
        """
        let offline = """
        Snapshot list:
        ID        TAG                 VM SIZE                DATE     VM CLOCK
        1         before-update      4.02 GiB 2026-07-29 10:19:58 00:14:07.221
        """

        let runningSnapshots = QEMUSnapshotListParser.parse(running)
        #expect(runningSnapshots.count == 2)
        #expect(runningSnapshots[0].tag == "before-update")
        #expect(runningSnapshots[0].vmStateSize == "4.02 GiB")
        #expect(runningSnapshots[0].createdAt == "2026-07-29 10:19:58")
        #expect(runningSnapshots[0].vmClock == "00:14:07.221")
        #expect(runningSnapshots[1].id == "2")

        #expect(QEMUSnapshotListParser.parse(offline).count == 1)
    }

    @Test("reads an empty snapshot listing as no snapshots rather than a parse failure")
    func readsEmptyListingAsNoSnapshots() {
        #expect(QEMUSnapshotListParser.parse("There is no snapshot available.\n").isEmpty)
        #expect(QEMUSnapshotListParser.parse("").isEmpty)
    }

    @Test("refuses snapshot names that could extend the monitor command line")
    func refusesUnsafeSnapshotNames() throws {
        #expect(try QEMUSnapshotTagPolicy.validate("  before-update  ") == "before-update")
        #expect(try QEMUSnapshotTagPolicy.validate("clean_install.2") == "clean_install.2")

        for unsafeTag in [
            "",
            "   ",
            "before update",
            "before;delvm all",
            "before\nloadvm other",
            "before'update",
            "before\"update",
            String(repeating: "a", count: QEMUSnapshotTagPolicy.maximumLength + 1)
        ] {
            #expect(throws: VMSnapshotError.invalidTag(unsafeTag)) {
                _ = try QEMUSnapshotTagPolicy.validate(unsafeTag)
            }
        }
    }

    @Test("treats monitor text failures as failures instead of successful returns")
    func treatsMonitorTextFailuresAsFailures() {
        #expect(QEMUSnapshotController.monitorFailureMessage(in: "") == nil)
        #expect(QEMUSnapshotController.monitorFailureMessage(in: "List of snapshots present on all disks:") == nil)
        #expect(
            QEMUSnapshotController.monitorFailureMessage(
                in: "Error: Device 'system' is writable but does not support snapshots"
            ) != nil
        )
        #expect(QEMUSnapshotController.monitorFailureMessage(in: "Snapshot 'nope' not found") != nil)
    }

    @Test("reads the system disk format from both plan and lock-safe launch arguments")
    func readsSystemDiskFormatFromBothArgumentForms() {
        #expect(
            VMSnapshotCapabilityFactory.systemDiskFormat(in: [
                "-drive", "if=none,id=system,format=raw,file=/Users/test/Windows 11 Arm.img"
            ]) == "raw"
        )
        #expect(
            VMSnapshotCapabilityFactory.systemDiskFormat(in: [
                "-drive",
                "driver=raw,file.driver=file,file.locking=off,file.filename=/Users/test/Windows 11 Arm.img,if=none,id=system"
            ]) == "raw"
        )
        #expect(
            VMSnapshotCapabilityFactory.systemDiskFormat(in: [
                "-drive", "if=none,id=system,format=qcow2,file=/Users/test/Windows 11 Arm.qcow2"
            ]) == "qcow2"
        )
        #expect(VMSnapshotCapabilityFactory.systemDiskFormat(in: ["-machine", "virt"]) == nil)
    }

    @Test("reports the raw shipping disk as unsupported with a conversion path")
    func reportsRawDiskAsUnsupportedWithConversionPath() {
        let capability = VMSnapshotCapabilityFactory.make(
            snapshot: .runningQEMU,
            planArguments: ["-drive", "if=none,id=system,format=raw,file=/Users/test/Virtual Machines/Veil/Windows 11 Arm.img"]
        )

        #expect(capability.state == .unsupportedDiskFormat)
        #expect(!capability.isSupported)
        #expect(capability.systemDiskFormat == "raw")
        #expect(capability.convertedDiskPath?.hasSuffix(".qcow2") == true)
        #expect(capability.conversionCommand?.contains("qemu-img convert -p -O qcow2") == true)
        // Suspend still works on this disk, so the message must not imply the session is unsavable.
        #expect(capability.detail.contains("Suspend and resume still work"))
    }

    @Test("reports a qcow2 disk as snapshot capable without a conversion step")
    func reportsQCOW2DiskAsCapable() {
        var snapshot = VMRuntimeSnapshot.runningQEMU
        snapshot.virtualDiskPath = "/Users/test/Virtual Machines/Veil/Windows 11 Arm.qcow2"
        let capability = VMSnapshotCapabilityFactory.make(
            snapshot: snapshot,
            planArguments: ["-drive", "if=none,id=system,format=qcow2,file=/Users/test/Virtual Machines/Veil/Windows 11 Arm.qcow2"]
        )

        #expect(capability.state == .supported)
        #expect(capability.isSupported)
        #expect(capability.conversionCommand == nil)
    }

    @Test("reports the Apple Virtualization fallback as snapshot-incapable")
    func reportsAppleVirtualizationAsIncapable() {
        let capability = VMSnapshotCapabilityFactory.make(
            snapshot: .runningAppleVirtualization,
            planArguments: nil
        )

        #expect(capability.state == .unsupportedProvider)
        #expect(capability.conversionCommand == nil)
    }

    @Test("an unavailable snapshot action still names the suspend alternative")
    func unavailableSnapshotActionNamesSuspendAlternative() {
        let report = VMSnapshotActionReportFactory.make(
            action: .create,
            snapshot: .runningQEMU,
            capability: VMSnapshotCapabilityFactory.make(
                snapshot: .runningQEMU,
                planArguments: ["-drive", "if=none,id=system,format=raw,file=/Users/test/Windows 11 Arm.img"]
            ),
            generatedAt: Date(timeIntervalSince1970: 1_770_000_700),
            requestedTag: "before-update"
        )

        #expect(report.status == .unavailable)
        #expect(report.snapshots.isEmpty)
        #expect(report.nextActions.contains { $0.contains("qemu-img convert") })
        #expect(report.nextActions.contains { $0.contains("vm-suspend") })
    }

    @Test("a restored snapshot points at guest agent reconnection before launching apps")
    func restoredSnapshotPointsAtGuestAgentReconnection() {
        var snapshot = VMRuntimeSnapshot.runningQEMU
        snapshot.virtualDiskPath = "/Users/test/Virtual Machines/Veil/Windows 11 Arm.qcow2"
        let report = VMSnapshotActionReportFactory.make(
            action: .restore,
            snapshot: snapshot,
            capability: VMSnapshotCapabilityFactory.make(
                snapshot: snapshot,
                planArguments: ["-drive", "if=none,id=system,format=qcow2,file=/Users/test/Virtual Machines/Veil/Windows 11 Arm.qcow2"]
            ),
            generatedAt: Date(timeIntervalSince1970: 1_770_000_800),
            requestedTag: "before-update",
            snapshots: [
                VMSnapshotSummary(
                    id: "1",
                    tag: "before-update",
                    vmStateSize: "4.02 GiB",
                    createdAt: "2026-07-29 10:19:58",
                    vmClock: "00:14:07.221"
                )
            ]
        )

        #expect(report.status == .succeeded)
        #expect(report.nextActions.contains { $0.contains("guest-agent-wait") })
    }

    @Test("resolves qemu-img next to the discovered QEMU executable")
    func resolvesSnapshotToolNextToQEMU() {
        #expect(
            QEMUSnapshotController.snapshotToolPath(forQEMUExecutablePath: "/opt/homebrew/bin/qemu-system-aarch64")
                == "/opt/homebrew/bin/qemu-img"
        )
    }
}

// MARK: - Test doubles

private actor FakeQMPControl: QEMUQMPControlling {
    private var migrationStatuses: [String]
    private var monitorTexts: [String]
    private var failuresBeforeSuccess: Int
    private(set) var executeNames: [String] = []

    init(
        migrationStatuses: [String] = ["completed"],
        monitorTexts: [String] = [],
        failuresBeforeSuccess: Int = 0
    ) {
        self.migrationStatuses = migrationStatuses
        self.monitorTexts = monitorTexts
        self.failuresBeforeSuccess = failuresBeforeSuccess
    }

    func execute(
        _ commands: [QEMUQMPCommand],
        socketPath: String,
        idleTimeoutSeconds: Int
    ) async throws -> [QEMUQMPReply] {
        var replies: [QEMUQMPReply] = []
        for command in commands {
            executeNames.append(command.executeName)

            if failuresBeforeSuccess > 0 {
                failuresBeforeSuccess -= 1
                throw QEMUQMPClientError.socketUnavailable(socketPath)
            }

            switch command {
            case .queryMigrate:
                let status = migrationStatuses.isEmpty ? "active" : migrationStatuses.removeFirst()
                replies.append(QEMUQMPReply(id: nil, isSuccess: true, statusReturn: status))
            case .queryStatus:
                replies.append(QEMUQMPReply(id: nil, isSuccess: true, statusReturn: "paused", isRunning: false))
            case .humanMonitor:
                let text = monitorTexts.isEmpty ? "" : monitorTexts.removeFirst()
                replies.append(QEMUQMPReply(id: nil, isSuccess: true, textReturn: text))
            default:
                replies.append(QEMUQMPReply(id: nil, isSuccess: true))
            }
        }

        return replies
    }
}

@MainActor
private final class SessionVMRuntimeService: VMRuntimeService {
    private var currentSnapshot: VMRuntimeSnapshot
    private let suspendedSnapshot: VMRuntimeSnapshot?
    private let resumedSnapshot: VMRuntimeSnapshot?
    private let suspendError: (any Error)?
    private let resumeError: (any Error)?
    private(set) var suspendCount = 0
    private(set) var resumeCount = 0

    init(
        snapshot: VMRuntimeSnapshot,
        suspendedSnapshot: VMRuntimeSnapshot? = nil,
        resumedSnapshot: VMRuntimeSnapshot? = nil,
        suspendError: (any Error)? = nil,
        resumeError: (any Error)? = nil
    ) {
        self.currentSnapshot = snapshot
        self.suspendedSnapshot = suspendedSnapshot
        self.resumedSnapshot = resumedSnapshot
        self.suspendError = suspendError
        self.resumeError = resumeError
    }

    func loadSnapshot() async throws -> VMRuntimeSnapshot {
        currentSnapshot
    }

    func prepareDefaultVM() async throws -> VMRuntimeSnapshot {
        currentSnapshot
    }

    func createDefaultProfile() async throws -> VMRuntimeSnapshot {
        currentSnapshot
    }

    func createDefaultVirtualDisk() async throws -> VMRuntimeSnapshot {
        currentSnapshot
    }

    func updateProfilePaths(
        installerMediaPath: String?,
        driverMediaPath: String?,
        virtualDiskPath: String?
    ) async throws -> VMRuntimeSnapshot {
        currentSnapshot
    }

    func markWindowsInstalled() async throws -> VMRuntimeSnapshot {
        currentSnapshot
    }

    func markGuestAgentConnected(agentVersion: String) async throws -> VMRuntimeSnapshot {
        currentSnapshot
    }

    func start() async throws -> VMRuntimeSnapshot {
        currentSnapshot
    }

    func stop() async throws -> VMRuntimeSnapshot {
        currentSnapshot
    }

    func suspend() async throws -> VMRuntimeSnapshot {
        suspendCount += 1
        if let suspendError {
            throw suspendError
        }

        currentSnapshot = suspendedSnapshot ?? currentSnapshot
        return currentSnapshot
    }

    func resume() async throws -> VMRuntimeSnapshot {
        resumeCount += 1
        if let resumeError {
            throw resumeError
        }

        currentSnapshot = resumedSnapshot ?? currentSnapshot
        return currentSnapshot
    }

    func suspendedSession() async -> VMSuspensionRecord? {
        currentSnapshot.suspendedSession
    }

    func sendConsolePointerTap(normalizedX: Double, normalizedY: Double) async throws -> QEMUPointerTapRecord {
        throw VMRuntimeError.bootNotImplemented
    }

    func sendConsoleKey(_ key: String) async throws -> QEMUKeySendRecord {
        throw VMRuntimeError.bootNotImplemented
    }

    func exportDiagnostics(to directory: URL) async throws -> URL {
        throw VMRuntimeError.bootNotImplemented
    }
}

private extension VMRuntimeProviderSummary {
    static var qemu: VMRuntimeProviderSummary {
        VMRuntimeProviderSummary(
            kind: .qemuHypervisor,
            displayName: "QEMU/HVF",
            mode: "local",
            acceleration: "hvf",
            isServerBacked: false,
            status: .active,
            detail: "Local QEMU/HVF provider."
        )
    }

    static var appleVirtualization: VMRuntimeProviderSummary {
        VMRuntimeProviderSummary(
            kind: .appleVirtualization,
            displayName: "Apple Virtualization",
            mode: "local",
            acceleration: "hypervisor",
            isServerBacked: false,
            status: .planned,
            detail: "Apple Virtualization fallback."
        )
    }
}

private extension VMRuntimeSnapshot {
    static func qemuSnapshot(
        state: VMRuntimeState,
        suspendedSession: VMSuspensionRecord? = nil,
        provider: VMRuntimeProviderSummary = .qemu
    ) -> VMRuntimeSnapshot {
        VMRuntimeSnapshot(
            state: state,
            virtualizationAvailable: true,
            architecture: "arm64",
            minimumOSSupported: true,
            profileName: "Windows 11 Arm",
            cpuCount: 4,
            memoryMB: 8_192,
            diskGB: 128,
            virtualDiskPath: "/Users/test/Virtual Machines/Veil/Windows 11 Arm.img",
            suspendedSession: suspendedSession,
            runtimeProvider: provider,
            bootReady: true,
            windowsInstalled: true,
            detail: "test snapshot"
        )
    }

    static var runningQEMU: VMRuntimeSnapshot {
        qemuSnapshot(state: .running)
    }

    static var stoppedQEMU: VMRuntimeSnapshot {
        qemuSnapshot(state: .stopped)
    }

    static var suspendedQEMU: VMRuntimeSnapshot {
        qemuSnapshot(
            state: .suspended,
            suspendedSession: VMSuspensionRecord(
                stateFilePath: "/Users/test/Virtual Machines/Veil/Windows 11 Arm.vmsave",
                stateFileByteCount: 4_831_838_208,
                virtualDiskPath: "/Users/test/Virtual Machines/Veil/Windows 11 Arm.img",
                executablePath: "/opt/homebrew/bin/qemu-system-aarch64",
                machineFingerprint: "fnv1a64:0a1b2c3d4e5f6071",
                displayMode: .vncLoopback,
                migrationStatus: "completed",
                suspendedAt: Date(timeIntervalSince1970: 1_770_000_092)
            )
        )
    }

    static var runningAppleVirtualization: VMRuntimeSnapshot {
        qemuSnapshot(state: .running, provider: .appleVirtualization)
    }
}
