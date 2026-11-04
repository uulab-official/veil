import Foundation
import Darwin
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers
import Vision
import VeilHostCore

extension VeilVMControl {
    static func waitForGuestAgent(json: Bool, waitSeconds: Int) async throws {
        let report = await guestAgentWaitReport(waitSeconds: waitSeconds)

        if json {
            let data = try JSONEncoder.veilDiagnostics.encode(report)
            print(String(decoding: data, as: UTF8.self))
            return
        }

        print("Windows guest agent: \(report.status.rawValue)")
        print("Endpoint: \(report.endpoint)")
        print("Attempts: \(report.attempts)")
        print("Waited seconds: \(report.waitedSeconds)")
        if let health = report.diagnostic.health {
            print("Agent: \(health.agentVersion)")
            print("OS: \(health.os)")
            print("Capabilities: appLaunch=\(health.capabilities.appLaunch), windowCapture=\(health.capabilities.windowCapture), input=\(health.capabilities.input), clipboard=\(health.capabilities.clipboardText), packageIdentity=\(health.capabilities.packageIdentity)")
        }
        if let errorMessage = report.diagnostic.errorMessage {
            print("Error: \(errorMessage)")
        }
        print("Next actions:")
        for action in report.nextActions {
            print("  - \(action)")
        }
    }

    static func guestAgentWaitReport(waitSeconds: Int) async -> AgentConnectionWaitReport {
        let endpoint = ProcessInfo.processInfo.environment["VEIL_AGENT_URL"] ?? "ws://127.0.0.1:18444"
        let url = URL(string: endpoint) ?? URL(string: "ws://127.0.0.1:18444")!
        let client = VeilHostClient(
            transport: URLSessionWebSocketTransport(url: url, requestTimeout: 3)
        )
        return await client.waitForAgentConnection(
            endpoint: endpoint,
            timeoutSeconds: waitSeconds
        )
    }

    static func markInstalled(json: Bool) async throws {
        let service = LocalVMRuntimeService()
        let snapshot = try await service.markWindowsInstalled()
        let diagnosticsURL = try await service.exportDiagnostics(to: diagnosticsDirectory())

        if json {
            let data = try JSONEncoder.veilDiagnostics.encode(snapshot)
            print(String(decoding: data, as: UTF8.self))
            return
        }

        print("Windows installation marked complete")
        print("Profile: \(snapshot.profileName ?? "Not configured")")
        print("Windows installed: \(snapshot.windowsInstalled ? "yes" : "no")")
        print("Installer: \(snapshot.installerMediaPath == nil ? "Not required for normal boot" : snapshot.installerMediaPath ?? "Not selected")")
        print("Virtual disk: \(snapshot.virtualDiskPath ?? "Not selected")")
        print("Boot ready: \(snapshot.bootReady ? "yes" : "no")")
        print("Detail: \(snapshot.detail)")
        print("Diagnostics: \(diagnosticsURL.path)")
    }

    /// Local runtime service wired to the QEMU/HVF provider.
    ///
    /// Suspend reads the QMP socket from the on-disk launch record rather than from in-process state,
    /// so this works whether the VM was started by Veil.app or by `qemu-start`. Resume relaunches
    /// QEMU as a child of this CLI process, which is the same orphan-and-continue pattern
    /// `qemu-start` already relies on.
    static func makeSessionRuntimeService(
        displayMode: QEMUWindowsBootDisplayMode
    ) -> LocalVMRuntimeService {
        LocalVMRuntimeService(
            bootRunner: QEMUVMRuntimeBooter(
                diagnosticsDirectory: diagnosticsDirectory(),
                frontmostRunner: {},
                displayMode: displayMode
            )
        )
    }

    static func suspendVMSession(json: Bool) async throws {
        let service = makeSessionRuntimeService(displayMode: .vncLoopback)
        let generatedAt = Date()

        do {
            let snapshot = try await service.suspend()
            let report = VMSessionActionReportFactory.make(
                action: .suspend,
                snapshot: snapshot,
                generatedAt: generatedAt
            )
            try printVMSessionActionReport(report, json: json)
        } catch {
            let snapshot = try await service.loadSnapshot()
            let report = VMSessionActionReportFactory.make(
                action: .suspend,
                snapshot: snapshot,
                generatedAt: generatedAt,
                errorMessage: vmSessionErrorMessage(for: error)
            )
            // The report is printed before throwing so automation still gets structured evidence for
            // the failure, then a non-zero exit code.
            try printVMSessionActionReport(report, json: json)
            throw VMControlError.vmSessionSuspendFailed(
                report.errorMessage ?? "unknown error",
                report.nextActions
            )
        }
    }

    static func resumeVMSession(json: Bool) async throws {
        let suspensionStore = JSONVMSuspensionRecordStore(
            directory: diagnosticsDirectory().appendingPathComponent("QEMU Suspend", isDirectory: true)
        )
        // A missing record and an unreadable one collapse to the same safe default here: resume will
        // fail with a clear `noSuspendedState`/`suspendedStateFileMissing` error a moment later.
        let suspendedRecord = try? await suspensionStore.loadLatest()
        // Resume reuses the display mode the session was suspended with so the embedded display
        // surface keeps working instead of silently switching to the native QEMU window.
        let service = makeSessionRuntimeService(displayMode: suspendedRecord?.displayMode ?? .vncLoopback)
        let generatedAt = Date()

        do {
            let snapshot = try await service.resume()
            let report = VMSessionActionReportFactory.make(
                action: .resume,
                snapshot: snapshot,
                generatedAt: generatedAt
            )
            try printVMSessionActionReport(report, json: json)
        } catch {
            let snapshot = try await service.loadSnapshot()
            let report = VMSessionActionReportFactory.make(
                action: .resume,
                snapshot: snapshot,
                generatedAt: generatedAt,
                errorMessage: vmSessionErrorMessage(for: error)
            )
            try printVMSessionActionReport(report, json: json)
            throw VMControlError.vmSessionResumeFailed(
                report.errorMessage ?? "unknown error",
                report.nextActions
            )
        }
    }

    static func printVMSessionStatus(json: Bool) async throws {
        let snapshot = try await makeSessionRuntimeService(displayMode: .vncLoopback).loadSnapshot()
        let report = VMSessionActionReportFactory.make(
            action: .status,
            snapshot: snapshot,
            generatedAt: Date()
        )
        try printVMSessionActionReport(report, json: json)
    }

    private static func printVMSessionActionReport(_ report: VMSessionActionReport, json: Bool) throws {
        if json {
            let data = try JSONEncoder.veilDiagnostics.encode(report)
            print(String(decoding: data, as: UTF8.self))
            return
        }

        print("Windows session \(report.action.rawValue): \(report.status.rawValue)")
        print("VM state: \(report.state.rawValue)")
        print("Provider: \(report.provider)")
        print("Session persistence: \(report.persistence.mode)")
        print("Can suspend: \(report.canSuspend ? "yes" : "no")")
        print("Can resume: \(report.canResume ? "yes" : "no")")
        if let stateFilePath = report.persistence.stateFilePath {
            print("Memory state file: \(stateFilePath)")
        }
        if let byteCount = report.persistence.stateFileByteCount {
            print("Memory state size: \(byteCount) bytes")
        }
        if let suspendedAt = report.persistence.suspendedAt {
            print("Suspended at: \(ISO8601DateFormatter().string(from: suspendedAt))")
        }
        print("Detail: \(report.persistence.detail)")
        if let errorMessage = report.errorMessage {
            print("Error: \(errorMessage)")
        }
        print("Next actions:")
        for action in report.nextActions {
            print("  - \(action)")
        }
    }

    private static func vmSessionErrorMessage(for error: any Error) -> String {
        if let localized = error as? LocalizedError,
           let description = localized.errorDescription {
            return description
        }

        return String(describing: error)
    }

    /// Measures what the frame pipeline actually delivers over a bounded window.
    ///
    /// Three slices of frame-pipeline work -- idle heartbeats, the binary channel, and dirty-rect tiles --
    /// landed on reasoning with no numbers behind them. This produces the numbers: achieved frame rate,
    /// wire bytes, how much of a surface a typical change touches, and what compositing costs.
    ///
    /// Latency is deliberately not measured here; `coherence-proof` already covers first-frame and
    /// post-input latency against a budget. The gap was throughput and efficiency.
    @MainActor
    static func measureFramePipeline(json: Bool, seconds: Int, outputPath: String?) async throws {
        let endpoint = HostDashboardModel.defaultAgentEndpoint
        guard let url = URLSessionFrameChannel.frameChannelURL(agentEndpoint: endpoint) else {
            throw VMControlError.framePipelineChannelUnavailable(
                "'\(endpoint)' is not a WebSocket endpoint, so the /frames path cannot be derived."
            )
        }

        let metrics = FramePipelineMetrics()
        let compositor = WindowFrameCompositor()
        let channel = URLSessionFrameChannel(url: url)
        let startedAt = Date()
        metrics.start(at: startedAt)

        // Composites into a throwaway surface rather than reusing the app's, so a measurement run never
        // disturbs what a running Veil.app is displaying.
        let collector = Task { @MainActor in
            do {
                for try await message in channel.frames() {
                    let compositeStartedAt = ContinuousClock.now
                    let outcome = compositor.apply(message.tile)
                    let compositeDuration = ContinuousClock.now - compositeStartedAt

                    switch outcome {
                    case .composited:
                        metrics.recordApplied(
                            tile: message.tile,
                            wireByteCount: message.wireByteCount,
                            compositeDuration: TimeInterval(compositeDuration.components.seconds)
                                + TimeInterval(compositeDuration.components.attoseconds) / 1e18
                        )
                    case .needsKeyFrame(let reason):
                        metrics.recordDropped(windowId: message.tile.windowId, reason: reason)
                    }
                }
            } catch {
                // A dropped channel mid-run still leaves a usable partial measurement, so this is reported
                // through the report rather than failing the command.
                VeilLog.agent.notice(
                    "Frame pipeline measurement channel ended early: \(String(describing: error))"
                )
            }
        }

        try? await Task.sleep(for: .seconds(seconds))
        collector.cancel()
        compositor.forgetAll()

        let report = metrics.report(generatedAt: Date())
        if let outputPath {
            let data = try JSONEncoder.veilDiagnostics.encode(report)
            try data.write(to: URL(fileURLWithPath: outputPath), options: .atomic)
        }

        try printFramePipelineReport(report, json: json)

        guard report.didObserveFrames else {
            throw VMControlError.framePipelineObservedNoFrames(report.nextActions)
        }
    }

    private static func printFramePipelineReport(_ report: FramePipelineReport, json: Bool) throws {
        if json {
            let data = try JSONEncoder.veilDiagnostics.encode(report)
            print(String(decoding: data, as: UTF8.self))
            return
        }

        print("Frame pipeline over \(String(format: "%.1f", report.observedSeconds))s via \(report.transport)")
        print("Frames observed: \(report.didObserveFrames ? "yes" : "no")")
        print("Total wire bytes: \(report.totalWireBytes)")
        print("Total frames/sec: \(String(format: "%.2f", report.totalFramesPerSecond))")
        print("Total wire bytes/sec: \(String(format: "%.0f", report.totalWireBytesPerSecond))")

        for window in report.windows {
            print("")
            print("Window \(window.windowId) (\(window.surfaceWidth)x\(window.surfaceHeight))")
            print("  Key frames: \(window.keyFrameCount), tiles: \(window.tileCount), heartbeats: \(window.unchangedHeartbeatCount)")
            print("  Dropped tiles: \(window.droppedTiles.total)")
            print("  Frames/sec: \(String(format: "%.2f", window.framesPerSecond))")
            print("  Wire bytes: \(window.wireBytes) (key frames \(window.keyFrameWireBytes), tiles \(window.tileWireBytes))")
            print("  Frame interval ms: p50 \(String(format: "%.1f", window.frameIntervalMilliseconds.p50)), p95 \(String(format: "%.1f", window.frameIntervalMilliseconds.p95)), max \(String(format: "%.1f", window.frameIntervalMilliseconds.maximum))")
            print("  Tile coverage %: p50 \(String(format: "%.1f", window.tileCoveragePercent.p50)), p95 \(String(format: "%.1f", window.tileCoveragePercent.p95))")
            print("  Composite ms: p50 \(String(format: "%.2f", window.compositeMilliseconds.p50)), p95 \(String(format: "%.2f", window.compositeMilliseconds.p95))")
            if let estimate = window.estimatedFullFrameWireBytes,
               let saved = window.estimatedWireBytesSavedPercent {
                print("  Estimated full-frame bytes: \(estimate) (saved \(String(format: "%.1f", saved))%)")
            } else {
                print("  Estimated full-frame bytes: not available without an observed key frame")
            }
        }

        print("")
        print("Estimation basis: \(report.estimationBasis)")
        print("Next actions:")
        for action in report.nextActions {
            print("  - \(action)")
        }
    }

    static func runVMSnapshotAction(
        _ action: VMSnapshotActionKind,
        json: Bool,
        name: String?
    ) async throws {
        let generatedAt = Date()
        let service = makeSessionRuntimeService(displayMode: .vncLoopback)
        let snapshot = try await service.loadSnapshot()
        let profile = try await JSONVMProfileStore().load()
        let plan = profile.flatMap { try? makeQEMUPlan(for: $0) }
        let capability = VMSnapshotCapabilityFactory.make(
            snapshot: snapshot,
            planArguments: plan?.arguments
        )

        guard capability.isSupported else {
            // Reported as `unavailable` with a conversion path rather than attempted and failed: on a
            // raw disk `savevm` cannot work, and pretending otherwise would produce a confusing QEMU
            // error instead of the real prerequisite.
            let report = VMSnapshotActionReportFactory.make(
                action: action,
                snapshot: snapshot,
                capability: capability,
                generatedAt: generatedAt,
                requestedTag: name
            )
            try printVMSnapshotActionReport(report, json: json)
            throw VMControlError.vmSnapshotActionFailed(capability.detail, report.nextActions)
        }

        let controller = QEMUSnapshotController()
        let launchRecord = try? await JSONQEMULaunchRecordStore(
            directory: diagnosticsDirectory().appendingPathComponent("QEMU Launch", isDirectory: true)
        ).loadLatest()
        let qmpSocketPath = snapshot.state == .running
            ? launchRecord?.qmpSocketPath?.trimmingCharacters(in: .whitespacesAndNewlines)
            : nil

        do {
            var snapshots: [VMSnapshotSummary] = []
            switch action {
            case .list:
                if let qmpSocketPath, !qmpSocketPath.isEmpty {
                    snapshots = try await controller.list(qmpSocketPath: qmpSocketPath)
                } else if let systemDiskPath = capability.systemDiskPath, let plan {
                    // Listing is the one action that is safe and useful while Windows is off, so it
                    // falls back to qemu-img instead of demanding a boot.
                    snapshots = try controller.listOffline(
                        systemDiskPath: systemDiskPath,
                        qemuExecutablePath: plan.executablePath
                    )
                } else {
                    throw VMSnapshotError.notConfigured
                }
            case .create, .restore, .delete:
                guard let qmpSocketPath, !qmpSocketPath.isEmpty else {
                    if snapshot.state == .running {
                        throw VMSnapshotError.qmpUnavailable
                    }
                    throw VMSnapshotError.vmNotRunning(action)
                }

                let tag = name ?? ""
                switch action {
                case .create:
                    _ = try await controller.create(tag: tag, qmpSocketPath: qmpSocketPath)
                case .restore:
                    _ = try await controller.restore(tag: tag, qmpSocketPath: qmpSocketPath)
                case .delete:
                    _ = try await controller.delete(tag: tag, qmpSocketPath: qmpSocketPath)
                case .list:
                    break
                }
                snapshots = (try? await controller.list(qmpSocketPath: qmpSocketPath)) ?? []
            }

            // Re-read the runtime snapshot: `loadvm` changes the run state, so the report must not
            // echo the pre-action state.
            let updatedSnapshot = try await service.loadSnapshot()
            let report = VMSnapshotActionReportFactory.make(
                action: action,
                snapshot: updatedSnapshot,
                capability: capability,
                generatedAt: generatedAt,
                requestedTag: name,
                snapshots: snapshots
            )
            try printVMSnapshotActionReport(report, json: json)
        } catch {
            let report = VMSnapshotActionReportFactory.make(
                action: action,
                snapshot: snapshot,
                capability: capability,
                generatedAt: generatedAt,
                requestedTag: name,
                errorMessage: vmSessionErrorMessage(for: error)
            )
            try printVMSnapshotActionReport(report, json: json)
            throw VMControlError.vmSnapshotActionFailed(
                report.errorMessage ?? "unknown error",
                report.nextActions
            )
        }
    }

    /// Reports whether the live shared folder is actually usable, end to end.
    ///
    /// Three separate things have to agree and any one of them can be the problem, so all three are
    /// reported rather than collapsed into one boolean: the boot plan has to carry the port forward, the
    /// guest has to be publishing the share, and macOS has to have it mounted.
    static func printSharedFolderStatus(
        json: Bool,
        prepare: Bool,
        requireReady: Bool
    ) async throws {
        let generatedAt = Date()
        let service = makeSessionRuntimeService(displayMode: .vncLoopback)
        let snapshot = try await service.loadSnapshot()
        let profile = try await JSONVMProfileStore().load()

        // Resolved from the same environment override the boot plan reads, so this cannot report a
        // transport the plan never wired.
        let transport = QEMUWindowsSharedFolderTransport.selected(
            from: ProcessInfo.processInfo.environment[QEMUWindowsSharedFolderTransport.environmentVariableName]
        ).transport

        // The running VM's own arguments are the truth about what is wired. A freshly built plan would
        // describe the *next* boot, which is a different question, and it would also see its own running
        // VM holding the forward port and wrongly call it a conflict.
        let launchRecord = try? await JSONQEMULaunchRecordStore(
            directory: diagnosticsDirectory().appendingPathComponent("QEMU Launch", isDirectory: true)
        ).loadLatest()
        let planArguments = snapshot.state == .running
            ? launchRecord?.arguments
            : profile.flatMap { try? makeQEMUPlan(for: $0) }?.arguments

        // Left unprobed while the VM runs: the running VM holds the forward port itself, so a probe
        // would report a conflict against Veil's own listener and blame the wrong thing.
        var isHostPortAvailable: Bool?
        if snapshot.state != .running {
            isHostPortAvailable = LocalQEMUWindowsBootPlanFactory.isLoopbackPortFree(
                QEMUWindowsSharedFolderTransport.guestSMBHostPort
            )
        }

        let capability = VMSharedFolderCapabilityFactory.make(
            transport: transport,
            planArguments: planArguments,
            isHostPortAvailable: isHostPortAvailable
        )

        var guest: WindowsSharedFolderStatus?
        var guestError: String?
        if capability.isSupported, snapshot.state == .running {
            let endpoint = HostDashboardModel.defaultAgentEndpoint
            let url = URL(string: endpoint) ?? URL(string: "ws://127.0.0.1:18444")!
            let client = VeilHostClient(transport: URLSessionWebSocketTransport(url: url))
            do {
                if prepare {
                    guest = try await client.prepareSharedFolder(
                        shareName: capability.shareName ?? QEMUWindowsSharedFolderTransport.shareName,
                        guestDirectoryPath: capability.expectedGuestDirectoryPath
                            ?? QEMUWindowsSharedFolderTransport.guestDirectoryPath
                    ).sharedFolder
                } else {
                    // Health is read-only, which is what a status command should be.
                    guest = try await client.loadHealth().sharedFolder
                }
            } catch {
                guestError = vmSessionErrorMessage(for: error)
            }
        }

        let report = VMSharedFolderReportFactory.make(
            generatedAt: generatedAt,
            vmState: snapshot.state,
            capability: capability,
            guest: guest,
            hostMount: VMSharedFolderHostMountProbe.read(transport: transport),
            hostStagingFolderPath: profile?.sharedFolderPath
        )

        try printSharedFolderReport(report, guestError: guestError, json: json)

        guard capability.isSupported else {
            throw VMControlError.sharedFolderUnavailable(capability.detail, report.nextActions)
        }

        // Only a hard gate on request. A folder that is merely not set up yet is a normal state for a
        // status command to report, not a command failure.
        if requireReady, report.readiness != .ready {
            throw VMControlError.sharedFolderNotReady(report.readiness.rawValue, report.nextActions)
        }
    }

    /// Reports which device-level integrations work on this host, and for the ones that do not, why.
    ///
    /// Exists because "does Veil do USB passthrough" deserves a precise answer. Both USB passthrough and
    /// the bridged network modes need root on macOS, and Veil runs QEMU as the logged-in user, so the
    /// blocker is a product decision rather than missing code. Saying that plainly is more useful than
    /// silence, and it stops the next person rediscovering it.
    static func printDevicePassthroughStatus(json: Bool, requireAvailable: Bool) async throws {
        let generatedAt = Date()
        let profile = try await JSONVMProfileStore().load()
        let plan = profile.flatMap { try? makeQEMUPlan(for: $0) }
        // Asks the local QEMU what it actually has rather than assuming. A build without libusb has no
        // usb-host device at all, which is a different answer from a build that has it and cannot get
        // access. This shells out, which is why it lives here and not in polled status.
        let deviceNames = QEMUDeviceModelProbe.deviceNames(
            qemuExecutablePath: plan?.isExecutableAvailable == true ? plan?.executablePath : nil
        )

        let report = VMDevicePassthroughReportFactory.make(
            generatedAt: generatedAt,
            qemuExecutablePath: plan?.executablePath,
            qemuDeviceNames: deviceNames
        )

        if json {
            let data = try JSONEncoder.veilDiagnostics.encode(report)
            print(String(decoding: data, as: UTF8.self))
        } else {
            print("Device integrations via \(report.provider)")
            print("QEMU: \(report.qemuExecutablePath ?? "not resolved")")
            print("Probed QEMU devices: \(report.didProbeQEMU ? "yes" : "no")")
            print("")
            for capability in report.capabilities {
                print("\(capability.title): \(capability.state.rawValue)")
                if capability.requiresPrivilegedHelper {
                    print("  Needs a root-privileged helper Veil does not ship.")
                }
                if let prerequisite = capability.prerequisite {
                    print("  Prerequisite: \(prerequisite)")
                }
                if let alternative = capability.alternative {
                    print("  Instead: \(alternative)")
                }
                print("  Detail: \(capability.detail)")
                if let reference = capability.reference {
                    print("  Reference: \(reference)")
                }
                print("")
            }
            print("Open decision: \(report.privilegedHelperDecision)")
            print("Next actions:")
            for action in report.nextActions {
                print("  - \(action)")
            }
        }

        // Only a hard gate on request. An honest "unavailable" is the normal, expected output of this
        // command, so it must not fail by default.
        if requireAvailable, report.capabilities.contains(where: { !$0.isAvailable }) {
            throw VMControlError.devicePassthroughUnavailable(report.nextActions)
        }
    }

    private static func printSharedFolderReport(
        _ report: VMSharedFolderReport,
        guestError: String?,
        json: Bool
    ) throws {
        if json {
            let data = try JSONEncoder.veilDiagnostics.encode(report)
            print(String(decoding: data, as: UTF8.self))
            return
        }

        print("Live shared folder: \(report.readiness.rawValue)")
        print("VM state: \(report.vmState.rawValue)")
        print("Provider: \(report.provider)")
        print("Transport: \(report.capability.transport.rawValue) (\(report.capability.state.rawValue))")
        print("Wired into boot plan: \(report.capability.isWiredIntoBootPlan ? "yes" : "no")")
        if let clause = report.capability.hostForwardClause {
            print("Port forward: \(clause)")
        }
        if let shareName = report.capability.shareName {
            print("Share name: \(shareName)")
        }
        if let guestDirectoryPath = report.capability.expectedGuestDirectoryPath {
            print("Guest folder: \(guestDirectoryPath)")
        }
        if let hostMountURL = report.capability.hostMountURL {
            print("Mount from Mac: \(hostMountURL)")
        }

        if let guest = report.guest {
            print("Guest report:")
            print("  Folder exists: \(guest.directoryExists ? "yes" : "no")")
            print("  Shared: \(guest.isShared ? "yes" : "no")")
            print("  Writable: \(guest.isWritable ? "yes" : "no")")
            print("  SMB server reachable: \(guest.serverListening ? "yes" : "no")")
            print("  Needs administrator: \(guest.requiresElevation ? "yes" : "no")")
            print("  Recommended action: \(guest.recommendedAction)")
            if let shareCommand = guest.shareCommand {
                print("  Elevated command: \(shareCommand)")
            }
            if let message = guest.message {
                print("  Detail: \(message)")
            }
        } else {
            print("Guest report: unavailable")
        }

        print("Mounted on this Mac: \(report.hostMount.isMounted ? "yes" : "no")")
        if let mountPath = report.hostMount.mountPath {
            print("Mount path: \(mountPath)")
        }
        // Named separately because the field is called sharedFolderPath but is not shared with Windows.
        if let hostStagingFolderPath = report.hostStagingFolderPath {
            print("Host install-media staging folder (not shared): \(hostStagingFolderPath)")
        }
        print("Detail: \(report.capability.detail)")
        if let guestError {
            print("Guest agent error: \(guestError)")
        }
        print("Next actions:")
        for action in report.nextActions {
            print("  - \(action)")
        }
    }

    private static func printVMSnapshotActionReport(_ report: VMSnapshotActionReport, json: Bool) throws {
        if json {
            let data = try JSONEncoder.veilDiagnostics.encode(report)
            print(String(decoding: data, as: UTF8.self))
            return
        }

        print("Windows snapshot \(report.action.rawValue): \(report.status.rawValue)")
        print("VM state: \(report.vmState.rawValue)")
        print("Provider: \(report.provider)")
        print("Snapshot support: \(report.capability.state.rawValue)")
        print("System disk format: \(report.capability.systemDiskFormat ?? "unknown")")
        if let requestedTag = report.requestedTag {
            print("Requested snapshot: \(requestedTag)")
        }
        if report.snapshots.isEmpty {
            print("Snapshots: none")
        } else {
            print("Snapshots:")
            for snapshot in report.snapshots {
                print("  \(snapshot.tag) (id \(snapshot.id), \(snapshot.vmStateSize), \(snapshot.createdAt), clock \(snapshot.vmClock))")
            }
        }
        print("Detail: \(report.capability.detail)")
        if let errorMessage = report.errorMessage {
            print("Error: \(errorMessage)")
        }
        print("Next actions:")
        for action in report.nextActions {
            print("  - \(action)")
        }
    }

    static func printProviders(json: Bool) throws {
        let architecture = hostArchitecture()
        let minimumOSSupported = ProcessInfo.processInfo.isOperatingSystemAtLeast(
            OperatingSystemVersion(majorVersion: 15, minorVersion: 0, patchVersion: 0)
        )
        let providers = VMRuntimeProviderProbe().localProviders(
            architecture: architecture,
            minimumOSSupported: minimumOSSupported
        )

        if json {
            let data = try JSONEncoder.veilDiagnostics.encode(providers)
            print(String(decoding: data, as: UTF8.self))
            return
        }

        for provider in providers {
            let pathSuffix = provider.executablePath.map { " at \($0)" } ?? ""
            print("\(provider.displayName): \(provider.status.rawValue), \(provider.mode), \(provider.acceleration)\(pathSuffix)")
            print("  \(provider.detail)")
        }
    }

    static func printQEMUPlan(json: Bool) async throws {
        guard let profile = try await JSONVMProfileStore().load() else {
            throw VMControlError.missingProfileForQEMUPlan
        }

        let plan = try makeQEMUPlan(for: profile)

        if json {
            let data = try JSONEncoder.veilDiagnostics.encode(plan)
            print(String(decoding: data, as: UTF8.self))
            return
        }

        print(plan.summary)
        print("\(plan.executablePath) \(plan.arguments.map(shellQuoted).joined(separator: " "))")
        if !plan.warnings.isEmpty {
            print("Warnings:")
            for warning in plan.warnings {
                print("  - \(warning)")
            }
        }
    }
}
