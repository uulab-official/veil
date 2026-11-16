import Foundation
import Darwin
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers
import Vision
import VeilHostCore

extension VeilVMControl {
    static func qemuSafePhaseName(_ phase: String) -> String {
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-_"))
        return phase.unicodeScalars.map { allowed.contains($0) ? Character(String($0)) : "-" }
            .reduce(into: "") { $0.append($1) }
    }

    static func powerDownQEMU(json: Bool, waitSeconds: Int) async throws {
        let launchRecord = try latestQEMULaunchRecord()
        let qmpSocketPath = launchRecord.qmpSocketPath?.trimmingCharacters(in: .whitespacesAndNewlines)
        let canUseQMP = qmpSocketPath.map { !$0.isEmpty && FileManager.default.fileExists(atPath: $0) } ?? false
        guard canUseQMP || FileManager.default.fileExists(atPath: launchRecord.monitorSocketPath) else {
            throw VMControlError.qemuMonitorUnavailable(launchRecord.monitorSocketPath)
        }

        let sender: QEMUKeySendResult
        if canUseQMP, let qmpSocketPath {
            let command = try QEMUQMPControlCommandBuilder.powerDownCommand()
            sender = sendQMPCommand(command, qmpSocketPath: qmpSocketPath, key: "system_powerdown")
        } else {
            sender = sendQEMUMonitorLine(
                "system_powerdown",
                monitorSocketPath: launchRecord.monitorSocketPath,
                key: "system_powerdown"
            )
        }
        let boundedWaitSeconds = min(max(waitSeconds, 0), 120)
        let didExit = await waitForProcessExit(pid: launchRecord.pid, timeoutSeconds: boundedWaitSeconds)
        let record = QEMUPowerDownRecord(
            pid: launchRecord.pid,
            monitorSocketPath: launchRecord.monitorSocketPath,
            qmpSocketPath: launchRecord.qmpSocketPath,
            transport: sender.transport,
            socketPath: sender.socketPath,
            command: sender.monitorCommand,
            didLaunchSender: sender.didLaunchSender,
            terminationStatus: sender.terminationStatus,
            waitedSeconds: boundedWaitSeconds,
            didExitWithinWait: didExit,
            requestedAt: Date()
        )

        if json {
            let data = try JSONEncoder.veilDiagnostics.encode(record)
            print(String(decoding: data, as: UTF8.self))
            return
        }

        print("QEMU powerdown requested")
        print("PID: \(record.pid.map(String.init) ?? "unknown")")
        print("Transport: \(record.transport)")
        print("Socket: \(record.socketPath)")
        print("Sender status: \(record.terminationStatus.map(String.init) ?? "not launched")")
        print("Exited within wait: \(record.didExitWithinWait ? "yes" : "no")")
    }

    static func forceStopQEMU(json: Bool, waitSeconds: Int, isAuthorized: Bool) async throws {
        guard isAuthorized else {
            throw VMControlError.missingForceStopAcknowledgement
        }

        let launchRecord = try latestQEMULaunchRecord()
        let boundedWaitSeconds = min(max(waitSeconds, 0), 120)
        let didSignal: Bool
        if let pid = launchRecord.pid, isProcessRunning(pid: pid) {
            didSignal = Darwin.kill(pid, SIGTERM) == 0
        } else {
            didSignal = false
        }

        let didExit = await waitForProcessExit(pid: launchRecord.pid, timeoutSeconds: boundedWaitSeconds)
        let record = QEMUForceStopRecord(
            pid: launchRecord.pid,
            signal: "SIGTERM",
            didSignalProcess: didSignal,
            waitedSeconds: boundedWaitSeconds,
            didExitWithinWait: didExit,
            requestedAt: Date()
        )

        if json {
            let data = try JSONEncoder.veilDiagnostics.encode(record)
            print(String(decoding: data, as: UTF8.self))
            return
        }

        print("QEMU force stop requested")
        print("PID: \(record.pid.map(String.init) ?? "unknown")")
        print("Signal: \(record.signal)")
        print("Signaled: \(record.didSignalProcess ? "yes" : "no")")
        print("Exited within wait: \(record.didExitWithinWait ? "yes" : "no")")
    }

    static func sendQEMUOOBEBypass(json: Bool) async throws {
        try await sendQEMUKeySteps(json: json, steps: QEMUOOBEBypassKeySequence.steps)
    }

    static func sendQEMUSparsePackagePreparation(json: Bool, waitSeconds: Int) async throws {
        let report = try await qemuSparsePackagePreparationAttemptReport(waitSeconds: waitSeconds)

        if json {
            let data = try JSONEncoder.veilDiagnostics.encode(report)
            print(String(decoding: data, as: UTF8.self))
            return
        }

        print("QEMU sparse package preparation attempt: \(report.status.rawValue)")
        print("Package identity: \(report.agentWait.diagnostic.health?.capabilities.packageIdentity == true ? "ready" : "needed")")
        print("Activation tap: \(report.activationTap == nil ? "fallback keyboard" : "sent")")
        print("Run confirmation tap: \(report.runConfirmationTap == nil ? "fallback keyboard" : "sent")")
        print("UAC approval tap: \(report.uacApprovalTap == nil ? "not sent" : "sent")")
        print("UAC approval keys: \(report.uacApprovalKeySend == nil ? "not sent" : "sent")")
        print("Keys sent: \(report.keySend.keys.count)")
        print("Desktop readiness: \(report.desktopReadiness.status.rawValue) (\(report.desktopReadiness.attempts) captures)")
        print("Run readiness: \(report.runReadiness.status.rawValue) (\(report.runReadiness.attempts) captures)")
        print("UAC readiness: \(report.uacReadiness.status.rawValue) (\(report.uacReadiness.attempts) captures)")
        print("Waited seconds: \(report.agentWait.waitedSeconds)")
        print("Attempts: \(report.agentWait.attempts)")
        print("Post-attempt console: \(report.postAttemptConsole.visualObservation?.screenshotPath ?? report.postAttemptConsole.capture?.consoleScreenshotPath ?? "not captured")")
        print("Next actions:")
        for action in report.nextActions {
            print("  - \(action)")
        }
    }

    static func sendQEMUGuestAgentInstall(json: Bool, waitSeconds: Int) async throws {
        let report = try await qemuGuestAgentInstallAttemptReport(waitSeconds: waitSeconds)

        if json {
            let data = try JSONEncoder.veilDiagnostics.encode(report)
            print(String(decoding: data, as: UTF8.self))
            return
        }

        print("QEMU guest agent install attempt: \(report.status.rawValue)")
        print("Activation tap: \(report.activationTap == nil ? "fallback keyboard" : "sent")")
        print("Run confirmation tap: \(report.runConfirmationTap == nil ? "fallback keyboard" : "sent")")
        print("UAC approval tap: \(report.uacApprovalTap == nil ? "not sent" : "sent")")
        print("UAC approval keys: \(report.uacApprovalKeySend == nil ? "not sent" : "sent")")
        print("Keys sent: \(report.keySend.keys.count)")
        print("Desktop readiness: \(report.desktopReadiness.status.rawValue) (\(report.desktopReadiness.attempts) captures)")
        print("Run readiness: \(report.runReadiness.status.rawValue) (\(report.runReadiness.attempts) captures)")
        print("UAC readiness: \(report.uacReadiness.status.rawValue) (\(report.uacReadiness.attempts) captures)")
        print("Waited seconds: \(report.agentWait.waitedSeconds)")
        print("Attempts: \(report.agentWait.attempts)")
        print("Post-attempt console: \(report.postAttemptConsole.visualObservation?.screenshotPath ?? report.postAttemptConsole.capture?.consoleScreenshotPath ?? "not captured")")
        print("Next actions:")
        for action in report.nextActions {
            print("  - \(action)")
        }
    }

    static func qemuSparsePackagePreparationAttemptReport(waitSeconds: Int) async throws -> QEMUGuestAgentInstallAttemptReport {
        var report = try await qemuGuestCommandAttemptReport(
            commandText: QEMUSparsePackagePreparationKeySequence.commandText,
            openRunSteps: QEMUSparsePackagePreparationKeySequence.openRunSteps,
            commandTextSteps: QEMUSparsePackagePreparationKeySequence.commandTextSteps,
            waitSeconds: waitSeconds,
            isAlreadySatisfied: { report in
                report.diagnostic.health?.capabilities.packageIdentity == true
            },
            nextActions: { agentWait, waitSeconds, consoleEvidence in
                sparsePackagePreparationNextActions(
                    agentWait: agentWait,
                    waitSeconds: waitSeconds,
                    consoleEvidence: consoleEvidence
                )
            }
        )
        report.kind = "qemuSparsePackagePreparationAttempt"
        return report
    }

    /// Installs the tools Veil ships into a running Windows from the tools update disc, the same way
    /// the app's Update Tools button does.
    static func sendQEMUGuestToolsUpdate(json: Bool, waitSeconds: Int) async throws {
        let bundledVersion = GuestToolsBundle.bundledVersion
        let mediaStatus = try await LocalVMRuntimeService().insertGuestToolsUpdateMedia()
        var report = try await qemuGuestCommandAttemptReport(
            commandText: QEMUGuestToolsUpdateKeySequence.commandText,
            openRunSteps: QEMUGuestToolsUpdateKeySequence.openRunSteps,
            commandTextSteps: QEMUGuestToolsUpdateKeySequence.commandTextSteps,
            waitSeconds: waitSeconds,
            isAlreadySatisfied: { $0.diagnostic.health?.agentVersion == bundledVersion },
            nextActions: { agentWait, waitSeconds, consoleEvidence in
                guestAgentInstallNextActions(
                    agentWait: agentWait,
                    waitSeconds: waitSeconds,
                    consoleEvidence: consoleEvidence
                )
            }
        )
        report.kind = "qemuGuestToolsUpdateAttempt"

        if json {
            let data = try JSONEncoder.veilDiagnostics.encode(report)
            print(String(decoding: data, as: UTF8.self))
            return
        }

        print("Tools update disc: \(mediaStatus.insertedPath ?? "inserted")")
        print("Bundled tools: \(bundledVersion ?? "unstamped")")
        print("QEMU guest tools update attempt: \(report.status.rawValue)")
        print("UAC readiness: \(report.uacReadiness.status.rawValue) (\(report.uacReadiness.attempts) captures)")
        print("UAC approval keys: \(report.uacApprovalKeySend == nil ? "not sent" : "sent")")
        print("Agent version: \(report.agentWait.diagnostic.health?.agentVersion ?? "not connected")")
    }

    static func qemuGuestAgentInstallAttemptReport(waitSeconds: Int) async throws -> QEMUGuestAgentInstallAttemptReport {
        try await qemuGuestCommandAttemptReport(
            commandText: QEMUGuestAgentInstallKeySequence.commandText,
            openRunSteps: QEMUGuestAgentInstallKeySequence.openRunSteps,
            commandTextSteps: QEMUGuestAgentInstallKeySequence.commandTextSteps,
            waitSeconds: waitSeconds,
            isAlreadySatisfied: { $0.status == .connected },
            nextActions: { agentWait, waitSeconds, consoleEvidence in
                guestAgentInstallNextActions(
                    agentWait: agentWait,
                    waitSeconds: waitSeconds,
                    consoleEvidence: consoleEvidence
                )
            }
        )
    }

    private static func qemuGuestCommandAttemptReport(
        commandText: String,
        openRunSteps: @autoclosure () throws -> [QEMUKeySequenceStep],
        commandTextSteps: @autoclosure () throws -> [QEMUKeySequenceStep],
        waitSeconds: Int,
        isAlreadySatisfied: (AgentConnectionWaitReport) -> Bool,
        nextActions: (AgentConnectionWaitReport, Int, QEMUGuestAgentInstallConsoleEvidence) -> [String]
    ) async throws -> QEMUGuestAgentInstallAttemptReport {
        let preflight = await guestAgentWaitReport(waitSeconds: min(max(waitSeconds, 1), 3))
        if isAlreadySatisfied(preflight) {
            let keySend = try await qemuKeySendRecord(steps: [])
            let skippedReadiness = qemuSkippedConsoleReadinessReport(phase: "already-satisfied")
            let postAttemptConsole = qemuSkippedGuestAgentInstallConsoleEvidence()
            return QEMUGuestAgentInstallAttemptReport(
                commandText: commandText,
                activationTap: nil,
                runConfirmationTap: nil,
                uacApprovalTap: nil,
                uacApprovalKeySend: nil,
                keySend: keySend,
                desktopReadiness: skippedReadiness,
                runReadiness: skippedReadiness,
                uacReadiness: skippedReadiness,
                agentWait: preflight,
                postAttemptConsole: postAttemptConsole,
                status: preflight.status,
                nextActions: nextActions(preflight, waitSeconds, postAttemptConsole)
            )
        }

        let desktopTimeout = min(max(waitSeconds / 3, 8), 30)
        let desktopResult = await waitForQEMUConsoleReadiness(
            phase: "desktop",
            timeoutSeconds: desktopTimeout,
            referenceFrame: nil,
            expectedStates: [.desktop, .runDialog, .commandShell],
            acceptMeaningfulChange: false,
            wakeWhenBlank: true,
            recognizeText: false
        )
        guard desktopResult.report.status == .ready,
              let desktopSnapshot = desktopResult.snapshot else {
            let keySend = try await qemuKeySendRecord(steps: [])
            let postAttemptConsole = qemuGuestAgentInstallConsoleEvidence()
            return QEMUGuestAgentInstallAttemptReport(
                commandText: commandText,
                activationTap: nil,
                runConfirmationTap: nil,
                uacApprovalTap: nil,
                uacApprovalKeySend: nil,
                keySend: keySend,
                desktopReadiness: desktopResult.report,
                runReadiness: qemuSkippedConsoleReadinessReport(phase: "run"),
                uacReadiness: qemuSkippedConsoleReadinessReport(phase: "uac"),
                agentWait: preflight,
                postAttemptConsole: postAttemptConsole,
                status: preflight.status,
                nextActions: nextActions(preflight, waitSeconds, postAttemptConsole)
            )
        }

        // Win+R is global and works independently of the taskbar layout. Do not click a hard-coded
        // Start/search coordinate first: Windows can move or center those controls as the guest
        // resolution changes, which previously left the command in the Run field without running it.
        let activationTap: QEMUPointerTapRecord? = nil
        var keySendRecords: [QEMUKeySendRecord] = []
        var runReadiness: QEMUConsoleReadinessReport
        var runSnapshot: QEMUConsoleVisualSnapshot?
        try? await Task.sleep(nanoseconds: 500_000_000)
        keySendRecords.append(try await qemuKeySendRecord(steps: try openRunSteps()))
        var runResult = await waitForQEMUConsoleReadiness(
            phase: "run",
            timeoutSeconds: 6,
            referenceFrame: desktopSnapshot.frame,
            expectedStates: [.runDialog],
            acceptMeaningfulChange: true,
            wakeWhenBlank: false
        )
        if runResult.report.status != .ready {
            keySendRecords.append(try await qemuKeySendRecord(steps: [
                QEMUKeySequenceStep(key: "esc", delayAfterSend: 0.3)
            ] + (try openRunSteps())))
            let retryResult = await waitForQEMUConsoleReadiness(
                phase: "run-retry",
                timeoutSeconds: 6,
                referenceFrame: desktopSnapshot.frame,
                expectedStates: [.runDialog],
                acceptMeaningfulChange: true,
                wakeWhenBlank: false
            )
            runResult = mergeQEMUConsoleReadinessReports(runResult, retryResult)
        }
        runReadiness = runResult.report
        runSnapshot = runResult.snapshot
        if runReadiness.status == .ready {
            // Enter is mandatory even when the pointer-based Run confirmation is unavailable. A
            // visual change alone is not proof that the Run dialog received the command.
            keySendRecords.append(try await qemuKeySendRecord(steps: try commandTextSteps()))
            keySendRecords.append(try await qemuKeySendRecord(steps: [
                QEMUKeySequenceStep(key: "ret", delayAfterSend: 1.0)
            ]))
        }

        var uacReadiness = qemuSkippedConsoleReadinessReport(phase: "uac")
        var uacApprovalKeySend: QEMUKeySendRecord?
        if runReadiness.status == .ready {
            let typedSnapshot = try? qemuConsoleVisualSnapshot(
                phase: "run-command",
                attempt: 1,
                referenceFrame: runSnapshot?.frame,
                recognizeText: false
            )

            let uacTimeout = min(max(waitSeconds / 2, 12), 30)
            let uacResult = await waitForQEMUConsoleReadiness(
                phase: "uac",
                timeoutSeconds: uacTimeout,
                referenceFrame: typedSnapshot?.frame ?? runSnapshot?.frame,
                expectedStates: [.uacPrompt, .modalPrompt],
                acceptMeaningfulChange: false,
                wakeWhenBlank: false
            )
            uacReadiness = uacResult.report
            if uacReadiness.status == .ready {
                uacApprovalKeySend = try? await qemuKeySendRecord(
                    steps: QEMUGuestAgentInstallKeySequence.uacApproveKeySteps
                )
                if let uacApprovalKeySend {
                    keySendRecords.append(uacApprovalKeySend)
                }
            }
        }

        let keySend = try await mergedQEMUKeySendRecord(keySendRecords)
        try? await Task.sleep(nanoseconds: 1_000_000_000)
        let agentWait = await guestAgentWaitReport(waitSeconds: waitSeconds)
        let postAttemptConsole = qemuGuestAgentInstallConsoleEvidence()
        let nextActions = nextActions(agentWait, waitSeconds, postAttemptConsole)
        return QEMUGuestAgentInstallAttemptReport(
            commandText: commandText,
            activationTap: activationTap,
            runConfirmationTap: nil,
            uacApprovalTap: nil,
            uacApprovalKeySend: uacApprovalKeySend,
            keySend: keySend,
            desktopReadiness: desktopResult.report,
            runReadiness: runReadiness,
            uacReadiness: uacReadiness,
            agentWait: agentWait,
            postAttemptConsole: postAttemptConsole,
            status: agentWait.status,
            nextActions: nextActions
        )
    }

    private static func qemuGuestAgentInstallConsoleEvidence() -> QEMUGuestAgentInstallConsoleEvidence {
        let expectedVisibleStates = [
            "Windows Run dialog with the V.cmd command",
            "Windows administrator approval prompt for Repair Veil Agent Connectivity, often with No focused by default",
            "PowerShell or Command Prompt running the Veil repair/install script",
            "Windows desktop with no visible installer window, which means the QMP command likely did not reach the shell"
        ]

        do {
            let snapshot = try qemuConsoleVisualSnapshot(
                phase: "post-attempt",
                attempt: 1,
                referenceFrame: nil
            )
            return QEMUGuestAgentInstallConsoleEvidence(
                capture: nil,
                visualObservation: snapshot.observation,
                reviewHint: "The VNC observation is the active Windows display; inspect its state, OCR text, metrics, and latest screenshot together.",
                expectedVisibleStates: expectedVisibleStates
            )
        } catch {
            // Keep the HMP capture only as a compatibility fallback for launch records without VNC.
        }

        do {
            let capture = try captureLatestQEMUConsole()
            return QEMUGuestAgentInstallConsoleEvidence(
                capture: capture,
                visualObservation: nil,
                reviewHint: "Inspect the screenshot to confirm whether the post-attempt Windows screen shows Run, UAC, PowerShell, or only the desktop.",
                expectedVisibleStates: expectedVisibleStates
            )
        } catch {
            return QEMUGuestAgentInstallConsoleEvidence(
                capture: nil,
                visualObservation: nil,
                reviewHint: "Console screenshot could not be captured after the install attempt: \(error.localizedDescription)",
                expectedVisibleStates: expectedVisibleStates
            )
        }
    }

    private static func qemuSkippedGuestAgentInstallConsoleEvidence() -> QEMUGuestAgentInstallConsoleEvidence {
        QEMUGuestAgentInstallConsoleEvidence(
            capture: nil,
            visualObservation: nil,
            reviewHint: "Guest-agent health was already satisfied, so Veil skipped recovery input and post-attempt screen capture.",
            expectedVisibleStates: []
        )
    }

    private static func qemuGuestAgentInstallActivationTapRecord() async throws -> QEMUPointerTapRecord {
        let launchRecordStore = JSONQEMULaunchRecordStore(
            directory: diagnosticsDirectory()
                .appendingPathComponent("QEMU Launch", isDirectory: true)
        )
        let sender = QEMUPointerEventSender(launchRecordStore: launchRecordStore)
        return try await sender.sendTap(
            normalizedX: QEMUGuestAgentInstallKeySequence.startButtonTapNormalizedX,
            normalizedY: QEMUGuestAgentInstallKeySequence.startButtonTapNormalizedY
        )
    }

    private static func qemuGuestAgentInstallUACApprovalTapRecord() async throws -> QEMUPointerTapRecord {
        let launchRecordStore = JSONQEMULaunchRecordStore(
            directory: diagnosticsDirectory()
                .appendingPathComponent("QEMU Launch", isDirectory: true)
        )
        let sender = QEMUPointerEventSender(launchRecordStore: launchRecordStore)
        return try await sender.sendTap(
            normalizedX: QEMUGuestAgentInstallKeySequence.uacApproveTapNormalizedX,
            normalizedY: QEMUGuestAgentInstallKeySequence.uacApproveTapNormalizedY
        )
    }

    private static func qemuGuestCommandRunConfirmationTapRecord() async throws -> QEMUPointerTapRecord {
        let launchRecordStore = JSONQEMULaunchRecordStore(
            directory: diagnosticsDirectory()
                .appendingPathComponent("QEMU Launch", isDirectory: true)
        )
        let sender = QEMUPointerEventSender(launchRecordStore: launchRecordStore)
        return try await sender.sendTap(
            normalizedX: QEMUGuestAgentInstallKeySequence.runConfirmTapNormalizedX,
            normalizedY: QEMUGuestAgentInstallKeySequence.runConfirmTapNormalizedY
        )
    }

    private static func guestAgentInstallNextActions(
        agentWait: AgentConnectionWaitReport,
        waitSeconds: Int,
        consoleEvidence: QEMUGuestAgentInstallConsoleEvidence
    ) -> [String] {
        if agentWait.status == .connected {
            return [
                "Run `veil-vmctl app-runtime-status --json` to inspect app launch readiness.",
                "Run `veil-vmctl app-window-proof --json --app-id winapp_notepad` to prove the first mirrored Windows app window."
            ]
        }

        var actions = agentWait.nextActions
        if let visualObservation = consoleEvidence.visualObservation,
           let screenshotPath = visualObservation.screenshotPath {
            actions.append("Inspect postAttemptConsole.visualObservation at \(screenshotPath); Veil classified the active VNC display as \(visualObservation.state.rawValue).")
            actions.append("If the active display still shows an administrator prompt, retry `qemu-install-agent`; approval is sent only after UAC or centered-modal readiness is observed.")
        } else if let capture = consoleEvidence.capture {
            actions.append("Inspect postAttemptConsole.capture.consoleScreenshotPath at \(capture.consoleScreenshotPath) for Run, UAC, PowerShell, or desktop-only evidence.")
            actions.append("If the fallback screenshot still shows the Windows administrator approval prompt, retry `qemu-install-agent` after confirming the embedded display is available.")
        } else {
            actions.append("Run `veil-vmctl qemu-capture --json` and confirm whether the Windows desktop showed Run, UAC, or PowerShell during the install attempt.")
        }
        actions.append("Retry with a longer gate using `veil-vmctl qemu-install-agent --json --wait-seconds \(max(waitSeconds, 60))` after clicking inside the live Windows console.")
        return actions
    }

    private static func sparsePackagePreparationNextActions(
        agentWait: AgentConnectionWaitReport,
        waitSeconds: Int,
        consoleEvidence: QEMUGuestAgentInstallConsoleEvidence
    ) -> [String] {
        if agentWait.diagnostic.health?.capabilities.packageIdentity == true {
            return [
                "Run `veil-vmctl app-runtime-status --json` to verify Daily Use package identity readiness.",
                "Run `veil-vmctl app-runtime-action --json --action proof-recommended` to continue the strongest available Windows app check."
            ]
        }

        var actions = agentWait.nextActions
        if let packageIdentityStatus = agentWait.diagnostic.health?.packageIdentityStatus {
            actions.append("Inspect dailyUseReadiness.packageIdentityStage=\(packageIdentityStatus.stage) and packageIdentityEvidencePath=\(packageIdentityStatus.statusPath) before retrying.")
            if let message = packageIdentityStatus.message, !message.isEmpty {
                actions.append("Inspect dailyUseReadiness.packageIdentityMessage=\(message)")
            }
        }
        if let visualObservation = consoleEvidence.visualObservation,
           let screenshotPath = visualObservation.screenshotPath {
            actions.append("Inspect postAttemptConsole.visualObservation at \(screenshotPath); Veil classified the active VNC display as \(visualObservation.state.rawValue).")
        } else if let capture = consoleEvidence.capture {
            actions.append("Inspect postAttemptConsole.capture.consoleScreenshotPath at \(capture.consoleScreenshotPath) for the sparse package build or package identity failure.")
        } else {
            actions.append("Run `veil-vmctl qemu-capture --json` and confirm whether the Windows desktop showed the sparse package command output.")
        }
        actions.append("Retry with a longer gate using `veil-vmctl qemu-prepare-sparse-package --json --wait-seconds \(max(waitSeconds, 120))` after confirming the Windows SDK is installed in the guest.")
        return actions
    }

    static func sendQEMUKeys(
        json: Bool,
        keys: [String],
        delayAfterFirstKey: TimeInterval = 0.08
    ) async throws {
        let steps = keys.enumerated().map { index, key in
            QEMUKeySequenceStep(
                key: key,
                delayAfterSend: index == 0 ? delayAfterFirstKey : 0.08
            )
        }
        try await sendQEMUKeySteps(json: json, steps: steps)
    }

    private static func sendQEMUKeySteps(
        json: Bool,
        steps: [QEMUKeySequenceStep]
    ) async throws {
        let record = try await qemuKeySendRecord(steps: steps)

        if json {
            let data = try JSONEncoder.veilDiagnostics.encode(record)
            print(String(decoding: data, as: UTF8.self))
            return
        }

        print("QEMU key sequence sent")
        print("Monitor socket: \(record.monitorSocketPath)")
        print("Keys: \(record.keys.joined(separator: ", "))")
    }

    static func qemuKeySendRecord(
        steps: [QEMUKeySequenceStep]
    ) async throws -> QEMUKeySendRecord {
        let launchRecord = try latestQEMULaunchRecord()
        let qmpSocketPath = launchRecord.qmpSocketPath?.trimmingCharacters(in: .whitespacesAndNewlines)
        let canUseQMP = qmpSocketPath.map { !$0.isEmpty && FileManager.default.fileExists(atPath: $0) } ?? false
        guard canUseQMP || FileManager.default.fileExists(atPath: launchRecord.monitorSocketPath) else {
            throw VMControlError.qemuMonitorUnavailable(launchRecord.monitorSocketPath)
        }

        var results: [QEMUKeySendResult] = []
        for step in steps {
            let key = step.key
            if canUseQMP, let qmpSocketPath {
                let command = try QEMUQMPKeyboardCommandBuilder.inputEventCommand(for: key)
                results.append(sendQMPCommand(command, qmpSocketPath: qmpSocketPath, key: key))
            } else {
                let command = "sendkey \(key)"
                results.append(sendQEMUMonitorLine(command, monitorSocketPath: launchRecord.monitorSocketPath, key: key))
            }
            try? await Task.sleep(nanoseconds: UInt64(step.delayAfterSend * 1_000_000_000))
        }

        return QEMUKeySendRecord(
            monitorSocketPath: launchRecord.monitorSocketPath,
            keys: steps.map(\.key),
            results: results,
            sentAt: Date()
        )
    }

    static func typeQEMUText(json: Bool, text: String) async throws {
        let steps = try QEMUQMPKeyboardCommandBuilder
            .keySequence(forText: text)
            .map { QEMUKeySequenceStep(key: $0, delayAfterSend: 0.035) }
        try await sendQEMUKeySteps(json: json, steps: steps)
    }

    static func clickQEMU(json: Bool, x: Int, y: Int) async throws {
        let launchRecord = try latestQEMULaunchRecord()
        let qmpSocketPath = launchRecord.qmpSocketPath?.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let qmpSocketPath,
              !qmpSocketPath.isEmpty,
              FileManager.default.fileExists(atPath: qmpSocketPath) else {
            throw VMControlError.qemuMonitorUnavailable(launchRecord.qmpSocketPath ?? launchRecord.monitorSocketPath)
        }

        let moveCommand = try QEMUQMPPointerCommandBuilder.absoluteMoveCommand(x: x, y: y)
        let downCommand = try QEMUQMPPointerCommandBuilder.leftButtonCommand(isDown: true)
        let upCommand = try QEMUQMPPointerCommandBuilder.leftButtonCommand(isDown: false)
        let results = [
            sendQMPCommand(moveCommand, qmpSocketPath: qmpSocketPath, key: "mouse-move"),
            sendQMPCommand(downCommand, qmpSocketPath: qmpSocketPath, key: "mouse-left-down"),
            sendQMPCommand(upCommand, qmpSocketPath: qmpSocketPath, key: "mouse-left-up")
        ]
        let record = QEMUPointerClickRecord(
            monitorSocketPath: launchRecord.monitorSocketPath,
            qmpSocketPath: qmpSocketPath,
            x: x,
            y: y,
            results: results,
            sentAt: Date()
        )

        if json {
            let data = try JSONEncoder.veilDiagnostics.encode(record)
            print(String(decoding: data, as: UTF8.self))
            return
        }

        print("QEMU pointer click sent")
        print("Monitor socket: \(record.monitorSocketPath)")
        print("QMP socket: \(record.qmpSocketPath)")
        print("Absolute coordinate: \(record.x), \(record.y)")
    }

    static func latestQEMULaunchRecord() throws -> QEMULaunchRecord {
        let latestURL = diagnosticsDirectory()
            .appendingPathComponent("QEMU Launch", isDirectory: true)
            .appendingPathComponent("qemu-launch-latest.json")
        guard FileManager.default.fileExists(atPath: latestURL.path) else {
            throw VMControlError.missingQEMULaunchRecord
        }

        let data = try Data(contentsOf: latestURL)
        return try JSONDecoder.veilDiagnostics.decode(QEMULaunchRecord.self, from: data)
    }

    static func rejectDuplicateQEMULaunchIfNeeded(for profile: VMProfile) throws {
        guard let launchRecord = try? latestQEMULaunchRecord(),
              let pid = launchRecord.pid,
              isProcessRunning(pid: pid) else {
            if let runningProcess = QEMUVMRuntimeBooter.runningProcess(
                attachedToVirtualDiskPath: profile.virtualDiskPath
            ) {
                throw VMControlError.qemuAlreadyRunning(
                    pid: runningProcess.pid,
                    monitorSocketPath: runningProcess.monitorSocketPath
                )
            }
            return
        }

        throw VMControlError.qemuAlreadyRunning(
            pid: pid,
            monitorSocketPath: launchRecord.monitorSocketPath
        )
    }

    static func isProcessRunning(pid: Int32) -> Bool {
        Darwin.kill(pid, 0) == 0 || errno == EPERM
    }

    private static func waitForProcessExit(pid: Int32?, timeoutSeconds: Int) async -> Bool {
        guard let pid else {
            return false
        }

        if !isProcessRunning(pid: pid) {
            return true
        }

        guard timeoutSeconds > 0 else {
            return false
        }

        for _ in 0..<timeoutSeconds {
            try? await Task.sleep(nanoseconds: 1_000_000_000)
            if !isProcessRunning(pid: pid) {
                return true
            }
        }
        return false
    }

    private static func sendQEMUMonitorLine(
        _ line: String,
        monitorSocketPath: String,
        key: String
    ) -> QEMUKeySendResult {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/sh")
        process.arguments = [
            "-c",
            "printf '%s\\n' \"$1\" | /usr/bin/nc -w 1 -U \"$0\"",
            monitorSocketPath,
            line
        ]
        process.standardOutput = nil
        process.standardError = nil

        do {
            try process.run()
            process.waitUntilExit()
            return QEMUKeySendResult(
                key: key,
                transport: "hmp",
                socketPath: monitorSocketPath,
                monitorCommand: line,
                terminationStatus: process.terminationStatus,
                didLaunchSender: true
            )
        } catch {
            return QEMUKeySendResult(
                key: key,
                transport: "hmp",
                socketPath: monitorSocketPath,
                monitorCommand: line,
                terminationStatus: nil,
                didLaunchSender: false
            )
        }
    }

    private static func sendQMPCommand(
        _ command: String,
        qmpSocketPath: String,
        key: String
    ) -> QEMUKeySendResult {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/sh")
        process.arguments = [
            "-c",
            "printf '%s\\n%s\\n' \"$1\" \"$2\" | /usr/bin/nc -w 1 -U \"$0\"",
            qmpSocketPath,
            QEMUQMPKeyboardCommandBuilder.capabilitiesCommand(),
            command
        ]
        process.standardOutput = nil
        process.standardError = nil

        do {
            try process.run()
            process.waitUntilExit()
            return QEMUKeySendResult(
                key: key,
                transport: "qmp",
                socketPath: qmpSocketPath,
                monitorCommand: command,
                terminationStatus: process.terminationStatus,
                didLaunchSender: true
            )
        } catch {
            return QEMUKeySendResult(
                key: key,
                transport: "qmp",
                socketPath: qmpSocketPath,
                monitorCommand: command,
                terminationStatus: nil,
                didLaunchSender: false
            )
        }
    }

    static func driveInitialQEMULaunch(
        process: Process,
        waitSeconds: Int,
        shouldSendInstallerBootKey: Bool,
        monitorSocketURL: URL
    ) {
        let boundedSeconds = min(max(waitSeconds, 0), 120)
        let startDate = Date()
        let deadline = startDate.addingTimeInterval(TimeInterval(boundedSeconds))
        // VNC-backed QEMU takes longer to initialize its firmware display than the headless smoke
        // path. Starting at second two still covers the Windows CD prompt while avoiding a key event
        // being consumed by the EDK II startup handoff itself.
        var bootPromptAutomation = QEMUWindowsBootPromptAutomation(firstSendSecond: 2)

        while isProcessRunning(pid: process.processIdentifier), Date() < deadline {
            Thread.sleep(forTimeInterval: 0.25)
            if shouldSendInstallerBootKey {
                _ = bootPromptAutomation.tick(
                    elapsedSeconds: Int(Date().timeIntervalSince(startDate)),
                    monitorSocketURL: monitorSocketURL,
                    sendBootKey: QEMUVMRuntimeBooter.sendWindowsInstallerBootKey
                )
            }
        }

        // Keep the launch path focused on handing the live VM to the display bridge. A monitor
        // `screendump` during early UEFI startup is not a safe readiness probe: on some QEMU builds
        // it races firmware initialization and can terminate the launcher even though the VM was
        // otherwise healthy. The VNC display smoke and explicit qemu-capture command provide the
        // screenshot after the console is live.
    }

    static func bringQEMUToFrontIfAllowed() {
        guard ProcessInfo.processInfo.environment["VEIL_ALLOW_SYSTEM_EVENTS_FRONTMOST"] == "1" else {
            return
        }

        Thread.sleep(forTimeInterval: 0.5)

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
        process.arguments = [
            "-e",
            "tell application \"System Events\" to set frontmost of process \"qemu-system-aarch64\" to true"
        ]
        process.standardOutput = nil
        process.standardError = nil
        try? process.run()
    }

    static func runBoundedQEMU(
        executablePath: String,
        arguments: [String],
        seconds: Int,
        processLogURL: URL,
        monitorSocketURL: URL,
        consoleScreenshotURL: URL
    ) throws -> (output: String, didRemainRunningUntilTimeout: Bool, bootPromptKeySendCount: Int) {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executablePath)
        process.arguments = arguments

        let outputPipe = Pipe()
        process.standardOutput = outputPipe
        process.standardError = outputPipe

        try process.run()

        // Drain QEMU output while it runs. A full 16 KB pipe buffer would otherwise
        // block QEMU mid-boot and truncate the captured log to whatever fit.
        let outputDrainQueue = DispatchQueue(label: "veil.qemu-boot-log-drain")
        var drainedOutput = Data()
        let drainFinished = DispatchGroup()
        drainFinished.enter()
        outputDrainQueue.async {
            drainedOutput = outputPipe.fileHandleForReading.readDataToEndOfFile()
            drainFinished.leave()
        }

        let deadline = Date().addingTimeInterval(TimeInterval(seconds))
        let startDate = Date()
        var bootPromptAutomation = QEMUWindowsBootPromptAutomation()
        var bootPromptKeySendCount = 0
        while process.isRunning, Date() < deadline {
            Thread.sleep(forTimeInterval: 0.25)
            let didSendBootKey = bootPromptAutomation.tick(
                elapsedSeconds: Int(Date().timeIntervalSince(startDate)),
                monitorSocketURL: monitorSocketURL,
                sendBootKey: QEMUVMRuntimeBooter.sendWindowsInstallerBootKey
            )
            if didSendBootKey {
                bootPromptKeySendCount += 1
            }
        }

        let didRemainRunningUntilTimeout = process.isRunning
        if process.isRunning {
            QEMUVMRuntimeBooter.captureConsoleScreenshot(
                monitorSocketURL: monitorSocketURL,
                imageURL: consoleScreenshotURL
            )
            Thread.sleep(forTimeInterval: 0.5)
        }

        if process.isRunning {
            process.terminate()
        }
        process.waitUntilExit()
        drainFinished.wait()

        try drainedOutput.write(to: processLogURL, options: [.atomic])
        return (
            String(data: drainedOutput, encoding: .utf8) ?? "",
            didRemainRunningUntilTimeout,
            bootPromptKeySendCount
        )
    }

    static func makeQEMUPlan(for profile: VMProfile) throws -> QEMUWindowsBootPlan {
        try LocalQEMUWindowsBootPlanFactory.makePlan(
            for: profile,
            architecture: hostArchitecture(),
            minimumOSSupported: ProcessInfo.processInfo.isOperatingSystemAtLeast(
                OperatingSystemVersion(majorVersion: 15, minorVersion: 0, patchVersion: 0)
            )
        )
    }

    static func shellQuoted(_ value: String) -> String {
        guard value.rangeOfCharacter(from: .whitespacesAndNewlines) != nil else {
            return value
        }

        return "'\(value.replacingOccurrences(of: "'", with: "'\\''"))'"
    }

    static func qemuLaunchSupervisorCommand(
        executablePath: String,
        arguments: [String],
        qemuPIDPath: String
    ) -> String {
        let launchCommand = ([executablePath] + arguments)
            .map(shellQuoted)
            .joined(separator: " ")
        let pidPath = shellQuoted(qemuPIDPath)
        return "\(launchCommand) & qemu_child_pid=$!; /usr/bin/printf '%s\\n' \"$qemu_child_pid\" > \(pidPath); wait \"$qemu_child_pid\""
    }

    static func waitForQEMUPID(
        at pidURL: URL,
        timeoutSeconds: TimeInterval
    ) async -> Int32? {
        let deadline = Date().addingTimeInterval(max(timeoutSeconds, 0))
        repeat {
            if let data = try? Data(contentsOf: pidURL),
               let pid = Int32(
                   String(decoding: data, as: UTF8.self)
                       .trimmingCharacters(in: .whitespacesAndNewlines)
               ),
               pid > 0 {
                return pid
            }

            guard Date() < deadline else {
                return nil
            }
            try? await Task.sleep(nanoseconds: 50_000_000)
        } while true
    }

    static func hostArchitecture() -> String {
        #if arch(arm64)
        return "arm64"
        #elseif arch(x86_64)
        return "x86_64"
        #else
        return "unknown"
        #endif
    }

    static func diagnosticsDirectory() -> URL {
        QEMUVMRuntimeBooter.defaultDiagnosticsDirectory()
    }
}
