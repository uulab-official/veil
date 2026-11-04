import Foundation
import Darwin
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers
import Vision
import VeilHostCore

enum VMControlError: Error, LocalizedError {
    case missingCommand
    case unsupportedCommand(String)
    case missingInstallerPath
    case installerNotFound(String)
    case driverMediaNotFound(String)
    case missingProfileForQEMUPlan
    case qemuNotReady([String])
    case missingQEMULaunchRecord
    case qemuMonitorUnavailable(String)
    case qemuScreenshotCaptureFailed(String)
    case missingQEMUDisplayEndpoint
    case qemuDisplayPortUnavailable
    case qemuDisplayBackendUnavailable(requested: String, executablePath: String, availableBackends: [String])
    case qemuLaunchExited(pid: Int32, terminationStatus: Int32, processLogPath: String)
    case missingQEMUKeySequence
    case missingQEMUText
    case missingQEMUPointerCoordinate
    case missingAppId
    case missingMultiAppProofAppIds
    case missingAppRuntimeAction
    case missingAppRuntimeReviewEvidenceDirectory
    case unsupportedAppRuntimeAction(String)
    case missingWindowId
    case missingAppRuntimeText
    case missingAppRuntimePointerCoordinate
    case missingPrinterBridgeEvidencePath
    case printerBridgeEvidenceNotFound(String)
    case qemuAlreadyRunning(pid: Int32, monitorSocketPath: String?)
    case missingForceStopAcknowledgement
    case mvpProofNotProved([String])
    case multiAppProofIncomplete([String])
    case notificationProofNotProved([String])
    case vmSessionSuspendFailed(String, [String])
    case vmSessionResumeFailed(String, [String])
    case missingSnapshotName
    case vmSnapshotActionFailed(String, [String])
    case invalidFramePipelineDuration(Int)
    case invalidHostBackingScale(String)
    case framePipelineChannelUnavailable(String)
    case framePipelineObservedNoFrames([String])
    case sharedFolderUnavailable(String, [String])
    case sharedFolderNotReady(String, [String])
    case devicePassthroughUnavailable([String])

    var errorDescription: String? {
        switch self {
        case .missingCommand:
            Self.usage
        case .unsupportedCommand(let command):
            "Unsupported command '\(command)'. \(Self.usage)"
        case .missingInstallerPath:
            "Missing installer path. \(Self.usage)"
        case .installerNotFound(let path):
            "Installer file does not exist: \(path)"
        case .driverMediaNotFound(let path):
            "Driver media file does not exist: \(path)"
        case .missingProfileForQEMUPlan:
            "No prepared VM profile found. Run veil-vmctl prepare --installer /path/to/Windows.iso first."
        case .qemuNotReady(let nextActions):
            "QEMU/HVF is not ready. \(nextActions.joined(separator: " "))"
        case .missingQEMULaunchRecord:
            "No QEMU launch record found. Run veil-vmctl qemu-start first."
        case .qemuMonitorUnavailable(let path):
            "QEMU monitor socket is not available: \(path)"
        case .qemuScreenshotCaptureFailed(let path):
            "QEMU console screenshot could not be captured: \(path)"
        case .missingQEMUDisplayEndpoint:
            "No loopback VNC display endpoint found in the latest QEMU launch record. Start the VM from Veil.app or run veil-vmctl qemu-start first."
        case .qemuDisplayPortUnavailable:
            "No loopback VNC display port is available. Close stale QEMU/VNC listeners and try again."
        case .qemuDisplayBackendUnavailable(let requested, let executablePath, let availableBackends):
            "QEMU cannot provide the requested \(requested) display backend at \(executablePath) (\(availableBackends.isEmpty ? "no display backends were reported" : availableBackends.joined(separator: ", "))). Run qemu-start without --native-display to use Veil's embedded VNC console."
        case .qemuLaunchExited(let pid, let terminationStatus, let processLogPath):
            "QEMU exited during startup (PID \(pid), status \(terminationStatus)). Inspect \(processLogPath) and retry after correcting the reported startup error."
        case .missingQEMUKeySequence:
            "Missing QEMU key sequence. Pass keys such as shift-f10, esc, tab, ret, or spc."
        case .missingQEMUText:
            "Missing QEMU text. Pass qemu-type-text --text \"...\" with bounded ASCII input."
        case .missingQEMUPointerCoordinate:
            "Missing QEMU pointer coordinates. Pass --x and --y as absolute values from 0 to 32767."
        case .missingAppId:
            "Missing Windows app id. Pass --app-id winapp_notepad, winapp_calculator, or another id reported by app-runtime-status."
        case .missingMultiAppProofAppIds:
            "Missing Windows app ids. Pass --app-ids winapp_notepad,winapp_calculator,winapp_paint or omit it to use the default multi-app proof set."
        case .missingAppRuntimeAction:
            "Missing app runtime action. Pass --action launch, fulfill-pending, focus, close, close-all, restart-frame-stream, recover-window-capture, restore, bring-forward, prepare-sparse-package, request-notification-consent, quiet-when-idle, stop-runtime, suspend-runtime, clipboard, type-text, click, proof-recommended, proof-multi-app, or proof-notifications."
        case .missingAppRuntimeReviewEvidenceDirectory:
            "Missing review evidence directory. Pass --evidence-dir /path/to/review-folder created by app-runtime-review-init."
        case .unsupportedAppRuntimeAction(let action):
            "Unsupported app runtime action '\(action)'. Pass --action launch, fulfill-pending, focus, close, close-all, restart-frame-stream, recover-window-capture, reopen-window, maintain-frame-streams, restore, bring-forward, prepare-sparse-package, request-notification-consent, quiet-when-idle, stop-runtime, suspend-runtime, clipboard, type-text, click, proof-recommended, proof-multi-app, or proof-notifications."
        case .missingWindowId:
            "Missing Windows window id. Pass --window-id hwnd:XXXXXXXX from app-runtime-status or app-window-proof."
        case .missingAppRuntimeText:
            "Missing app runtime text. Pass --text \"...\" for clipboard or type-text actions."
        case .missingAppRuntimePointerCoordinate:
            "Missing app runtime pointer coordinates. Pass --x and --y as non-negative guest-window coordinates."
        case .missingPrinterBridgeEvidencePath:
            "Missing printer bridge evidence. Pass --evidence /path/to/windows-test-page-proof.png or .pdf."
        case .printerBridgeEvidenceNotFound(let path):
            "Printer bridge evidence file does not exist: \(path)"
        case .qemuAlreadyRunning(let pid, let monitorSocketPath):
            monitorSocketPath.map {
                "QEMU is already running as PID \(pid). Close the existing QEMU/Windows window, or use qemu-powerdown when the process was launched from the current Veil diagnostics path. Monitor socket: \($0)"
            } ?? "QEMU is already running as PID \(pid) with the configured Windows disk attached. Shut down that VM before starting another one."
        case .missingForceStopAcknowledgement:
            "Force stop can interrupt Windows disk writes. Re-run with \(QEMUForceStopAuthorization.acknowledgementFlag) only when the VM cannot shut down normally."
        case .mvpProofNotProved(let nextActions):
            "MVP proof did not reach proved status. \(nextActions.joined(separator: " "))"
        case .multiAppProofIncomplete(let nextActions):
            "Multi-app proof did not cover every target app. \(nextActions.joined(separator: " "))"
        case .notificationProofNotProved(let nextActions):
            "Windows notification proof did not receive a notification. \(nextActions.joined(separator: " "))"
        case .vmSessionSuspendFailed(let message, let nextActions):
            "Suspending the Windows session failed: \(message) \(nextActions.joined(separator: " "))"
        case .vmSessionResumeFailed(let message, let nextActions):
            "Resuming the suspended Windows session failed: \(message) \(nextActions.joined(separator: " "))"
        case .missingSnapshotName:
            "Missing snapshot name. Pass --name with letters, digits, dot, dash, or underscore and no spaces."
        case .vmSnapshotActionFailed(let message, let nextActions):
            "The Windows VM snapshot action did not complete: \(message) \(nextActions.joined(separator: " "))"
        case .invalidFramePipelineDuration(let seconds):
            "Frame pipeline measurement duration must be between 1 and 300 seconds, got \(seconds). A bounded window keeps this a diagnostic run rather than an open-ended profiler."
        case .invalidHostBackingScale(let value):
            "Display scale must be a number between 0.5 and 4, got \(value). This is a Mac backing scale factor such as 1 or 2, not a percentage. Omit the flag to report the scale as unknown rather than guessing."
        case .framePipelineChannelUnavailable(let detail):
            "The binary frame channel is not available for measurement: \(detail)"
        case .framePipelineObservedNoFrames(let nextActions):
            "Frame pipeline measurement observed no frames. \(nextActions.joined(separator: " "))"
        case .sharedFolderUnavailable(let detail, let nextActions):
            "A live shared folder is not available with the current configuration: \(detail) \(nextActions.joined(separator: " "))"
        case .sharedFolderNotReady(let readiness, let nextActions):
            "The live shared folder is not ready yet (\(readiness)). \(nextActions.joined(separator: " "))"
        case .devicePassthroughUnavailable(let nextActions):
            "Some device integrations are unavailable on this host. \(nextActions.joined(separator: " "))"
        }
    }

    private static let usage = "Usage: veil-vmctl prepare --installer /path/to/Windows.iso [--drivers /path/to/virtio-win.iso] | veil-vmctl app-runtime-status [--json] [--demo] [--host-backing-scale 2] | veil-vmctl app-runtime-review [--json] [--demo] [--evidence-dir /path/to/screenshots] | veil-vmctl app-runtime-review-init [--json] [--demo] [--evidence-dir /path/to/screenshots] | veil-vmctl app-runtime-review-verify [--json] [--demo] --evidence-dir /path/to/screenshots | veil-vmctl app-runtime-action --action launch|fulfill-pending|focus|close|close-all|restart-frame-stream|recover-window-capture|reopen-window|maintain-frame-streams|restore|reconnect-restore|bring-forward|recover-display|wait-agent|repair-agent|prepare-sparse-package|request-notification-consent|quiet-when-idle|stop-runtime|suspend-runtime|clipboard|type-text|click|proof-recommended|proof-multi-app|proof-notifications [--json] [--demo] [--wait-seconds 5] [--app-id winapp_notepad] [--window-id hwnd:XXXXXXXX] [--text \"...\"] [--x 240 --y 130] | veil-vmctl app-window-proof [--json] [--app-id winapp_notepad] [--wait-seconds 10] [--output /path/to/proof.json] | veil-vmctl coherence-proof [--json] [--app-id winapp_notepad] [--wait-seconds 10] [--output /path/to/proof.json] | veil-vmctl mvp-proof [--json] [--app-id winapp_notepad] [--wait-seconds 30] [--output /path/to/proof.json] [--require-proved] | veil-vmctl multi-app-proof [--json] [--app-ids winapp_notepad,winapp_calculator,winapp_paint] [--wait-seconds 10] [--output-dir /path/to/Diagnostics] [--require-complete] | veil-vmctl notification-proof [--json] [--wait-seconds 30] [--output /path/to/notification-proof.json] [--require-proved] | veil-vmctl printer-bridge-plan [--json] [--shared-printer name] [--windows-printer-name name] | veil-vmctl printer-bridge-proof [--json] --evidence /path/to/test-page-proof [--shared-printer name] [--windows-printer-name name] [--output /path/to/proof.json] | veil-vmctl guest-agent-wait [--json] [--wait-seconds 30] | veil-vmctl mark-installed [--json] | veil-vmctl providers [--json] | veil-vmctl export-diagnostics [--json] [--output /path/to/diagnostics.json] | veil-vmctl qemu-plan [--json] | veil-vmctl qemu-doctor [--json] | veil-vmctl qemu-install-status [--json] | veil-vmctl qemu-smoke [--json] [--seconds 45] | veil-vmctl qemu-start [--json] [--wait-seconds 15] [--native-display] | veil-vmctl qemu-display-smoke [--json] [--wait-seconds 5] | veil-vmctl qemu-capture [--json] [--output /path/to/console.png] | veil-vmctl qemu-powerdown [--json] [--wait-seconds 30] | veil-vmctl qemu-force-stop [--json] --i-understand-data-loss [--wait-seconds 10] | veil-vmctl qemu-sendkey [--json] key [key ...] | veil-vmctl qemu-type-text [--json] --text \"...\" | veil-vmctl qemu-click [--json] --x 0...32767 --y 0...32767 | veil-vmctl qemu-oobe-bypass [--json] | veil-vmctl qemu-install-agent [--json] [--wait-seconds 30] | veil-vmctl qemu-prepare-sparse-package [--json] [--wait-seconds 120] | veil-vmctl vm-suspend [--json] | veil-vmctl vm-resume [--json] | veil-vmctl vm-session-status [--json] | veil-vmctl vm-snapshot-list [--json] | veil-vmctl vm-snapshot-create [--json] --name before-update | veil-vmctl vm-snapshot-restore [--json] --name before-update | veil-vmctl vm-snapshot-delete [--json] --name before-update | veil-vmctl frame-pipeline-report [--json] [--seconds 10] [--output /path/to/frame-pipeline.json] | veil-vmctl shared-folder-status [--json] [--prepare] [--require-ready] | veil-vmctl device-passthrough-status [--json] [--require-available]"
}

struct VMControlArguments {
    enum AppRuntimeAction: String, Equatable, Codable {
        case launch
        case fulfillPending = "fulfill-pending"
        case focus
        case close
        case closeAll = "close-all"
        case restartFrameStream = "restart-frame-stream"
        case recoverWindowCapture = "recover-window-capture"
        case reopenWindow = "reopen-window"
        case maintainFrameStreams = "maintain-frame-streams"
        case restore
        case reconnectRestore = "reconnect-restore"
        case bringForward = "bring-forward"
        case recoverDisplay = "recover-display"
        case waitAgent = "wait-agent"
        case repairAgent = "repair-agent"
        case prepareSparsePackage = "prepare-sparse-package"
        case requestNotificationConsent = "request-notification-consent"
        case quietWhenIdle = "quiet-when-idle"
        case stopRuntime = "stop-runtime"
        case suspendRuntime = "suspend-runtime"
        case clipboard
        case typeText = "type-text"
        case click
        case proofRecommended = "proof-recommended"
        case proofMultiApp = "proof-multi-app"
        case proofNotifications = "proof-notifications"
    }

    enum QEMUStartDisplayMode: Equatable {
        case nativeCocoa
        case embedded
    }

    enum Command: Equatable {
        case prepare(installerPath: String, driverMediaPath: String?)
        case appRuntimeStatus(json: Bool, demo: Bool, hostBackingScale: Double?)
        case appRuntimeReview(json: Bool, demo: Bool, evidenceDirectoryPath: String?)
        case appRuntimeReviewInit(json: Bool, demo: Bool, evidenceDirectoryPath: String?)
        case appRuntimeReviewVerify(json: Bool, demo: Bool, evidenceDirectoryPath: String)
        case appRuntimeAction(json: Bool, demo: Bool, action: AppRuntimeAction, appId: String?, windowId: String?, text: String?, x: Int?, y: Int?, waitSeconds: Int)
        case appWindowProof(json: Bool, appId: String, waitSeconds: Int, outputPath: String?)
        case coherenceProof(json: Bool, appId: String, waitSeconds: Int, outputPath: String?)
        case mvpProof(json: Bool, appId: String, waitSeconds: Int, outputPath: String?, requireProved: Bool)
        case multiAppProof(json: Bool, appIds: [String], waitSeconds: Int, outputDirectoryPath: String?, requireComplete: Bool)
        case notificationProof(json: Bool, waitSeconds: Int, outputPath: String?, requireProved: Bool)
        case printerBridgePlan(json: Bool, sharedPrinterName: String?, windowsPrinterName: String?)
        case printerBridgeProof(json: Bool, evidencePath: String, sharedPrinterName: String?, windowsPrinterName: String?, outputPath: String?)
        case guestAgentWait(json: Bool, waitSeconds: Int)
        case markInstalled(json: Bool)
        case providers(json: Bool)
        case qemuPlan(json: Bool)
        case qemuDoctor(json: Bool)
        case qemuInstallStatus(json: Bool)
        case qemuSmoke(json: Bool, seconds: Int)
        case qemuStart(json: Bool, waitSeconds: Int, displayMode: QEMUStartDisplayMode)
        case qemuDisplaySmoke(json: Bool, waitSeconds: Int)
        case qemuCapture(json: Bool, outputPath: String?)
        case qemuPowerDown(json: Bool, waitSeconds: Int)
        case qemuForceStop(json: Bool, waitSeconds: Int, isAuthorized: Bool)
        case qemuSendKey(json: Bool, keys: [String])
        case qemuTypeText(json: Bool, text: String)
        case qemuClick(json: Bool, x: Int, y: Int)
        case qemuOOBEBypass(json: Bool)
        case qemuInstallAgent(json: Bool, waitSeconds: Int)
        case qemuPrepareSparsePackage(json: Bool, waitSeconds: Int)
        case vmSuspend(json: Bool)
        case vmResume(json: Bool)
        case vmSessionStatus(json: Bool)
        case vmSnapshotList(json: Bool)
        case vmSnapshotCreate(json: Bool, name: String)
        case vmSnapshotRestore(json: Bool, name: String)
        case vmSnapshotDelete(json: Bool, name: String)
        case framePipelineReport(json: Bool, seconds: Int, outputPath: String?)
        case sharedFolderStatus(json: Bool, prepare: Bool, requireReady: Bool)
        case devicePassthroughStatus(json: Bool, requireAvailable: Bool)
        case exportDiagnostics(json: Bool, outputPath: String?)
    }

    var command: Command

    static func parse(_ arguments: [String]) throws -> VMControlArguments {
        guard let command = arguments.first else {
            throw VMControlError.missingCommand
        }

        if command == "providers" {
            return VMControlArguments(command: .providers(json: arguments.contains("--json")))
        }

        if command == "export-diagnostics" {
            return VMControlArguments(
                command: .exportDiagnostics(
                    json: arguments.contains("--json"),
                    outputPath: stringArgument(named: "--output", from: arguments)
                )
            )
        }

        if command == "vm-suspend" {
            return VMControlArguments(command: .vmSuspend(json: arguments.contains("--json")))
        }

        if command == "vm-resume" {
            return VMControlArguments(command: .vmResume(json: arguments.contains("--json")))
        }

        if command == "vm-session-status" {
            return VMControlArguments(command: .vmSessionStatus(json: arguments.contains("--json")))
        }

        if command == "frame-pipeline-report" {
            let seconds = intArgument(named: "--seconds", from: arguments) ?? 10
            guard seconds > 0, seconds <= 300 else {
                throw VMControlError.invalidFramePipelineDuration(seconds)
            }

            return VMControlArguments(
                command: .framePipelineReport(
                    json: arguments.contains("--json"),
                    seconds: seconds,
                    outputPath: stringArgument(named: "--output", from: arguments)
                )
            )
        }

        if command == "shared-folder-status" {
            return VMControlArguments(
                command: .sharedFolderStatus(
                    json: arguments.contains("--json"),
                    // Reading is the default. Preparing creates a folder in the guest and, when the
                    // agent is elevated, publishes an SMB share, so it stays opt-in.
                    prepare: arguments.contains("--prepare"),
                    requireReady: arguments.contains("--require-ready")
                )
            )
        }

        if command == "device-passthrough-status" {
            return VMControlArguments(
                command: .devicePassthroughStatus(
                    json: arguments.contains("--json"),
                    requireAvailable: arguments.contains("--require-available")
                )
            )
        }

        if command == "vm-snapshot-list" {
            return VMControlArguments(command: .vmSnapshotList(json: arguments.contains("--json")))
        }

        if command == "vm-snapshot-create" || command == "vm-snapshot-restore" || command == "vm-snapshot-delete" {
            guard let name = stringArgument(named: "--name", from: arguments),
                  !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                throw VMControlError.missingSnapshotName
            }

            let json = arguments.contains("--json")
            switch command {
            case "vm-snapshot-create":
                return VMControlArguments(command: .vmSnapshotCreate(json: json, name: name))
            case "vm-snapshot-restore":
                return VMControlArguments(command: .vmSnapshotRestore(json: json, name: name))
            default:
                return VMControlArguments(command: .vmSnapshotDelete(json: json, name: name))
            }
        }

        if command == "app-runtime-status" {
            return VMControlArguments(
                command: .appRuntimeStatus(
                    json: arguments.contains("--json"),
                    demo: arguments.contains("--demo"),
                    hostBackingScale: try hostBackingScaleArgument(from: arguments)
                )
            )
        }

        if command == "app-runtime-review" {
            return VMControlArguments(
                command: .appRuntimeReview(
                    json: arguments.contains("--json"),
                    demo: arguments.contains("--demo"),
                    evidenceDirectoryPath: stringArgument(named: "--evidence-dir", from: arguments)
                )
            )
        }

        if command == "app-runtime-review-init" {
            return VMControlArguments(
                command: .appRuntimeReviewInit(
                    json: arguments.contains("--json"),
                    demo: arguments.contains("--demo"),
                    evidenceDirectoryPath: stringArgument(named: "--evidence-dir", from: arguments)
                )
            )
        }

        if command == "app-runtime-review-verify" {
            guard let evidenceDirectoryPath = stringArgument(named: "--evidence-dir", from: arguments),
                  !evidenceDirectoryPath.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                throw VMControlError.missingAppRuntimeReviewEvidenceDirectory
            }
            return VMControlArguments(
                command: .appRuntimeReviewVerify(
                    json: arguments.contains("--json"),
                    demo: arguments.contains("--demo"),
                    evidenceDirectoryPath: evidenceDirectoryPath
                )
            )
        }

        if command == "app-runtime-action" {
            guard let actionValue = stringArgument(named: "--action", from: arguments) else {
                throw VMControlError.missingAppRuntimeAction
            }
            guard let action = AppRuntimeAction(rawValue: actionValue) else {
                throw VMControlError.unsupportedAppRuntimeAction(actionValue)
            }

            return VMControlArguments(
                command: .appRuntimeAction(
                    json: arguments.contains("--json"),
                    demo: arguments.contains("--demo"),
                    action: action,
                    appId: stringArgument(named: "--app-id", from: arguments),
                    windowId: stringArgument(named: "--window-id", from: arguments),
                    text: stringArgument(named: "--text", from: arguments),
                    x: intArgument(named: "--x", from: arguments),
                    y: intArgument(named: "--y", from: arguments),
                    waitSeconds: waitSecondsArgument(from: arguments) ?? (action == .proofNotifications ? 30 : (action == .proofMultiApp ? 10 : 5))
                )
            )
        }

        if command == "app-window-proof" {
            let appId = stringArgument(named: "--app-id", from: arguments) ?? "winapp_notepad"
            guard !appId.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                throw VMControlError.missingAppId
            }
            let waitSeconds = waitSecondsArgument(from: arguments) ?? 10
            return VMControlArguments(
                command: .appWindowProof(
                    json: arguments.contains("--json"),
                    appId: appId,
                    waitSeconds: waitSeconds,
                    outputPath: stringArgument(named: "--output", from: arguments)
                )
            )
        }

        if command == "coherence-proof" {
            let appId = stringArgument(named: "--app-id", from: arguments) ?? "winapp_notepad"
            guard !appId.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                throw VMControlError.missingAppId
            }
            let waitSeconds = waitSecondsArgument(from: arguments) ?? 10
            return VMControlArguments(
                command: .coherenceProof(
                    json: arguments.contains("--json"),
                    appId: appId,
                    waitSeconds: waitSeconds,
                    outputPath: stringArgument(named: "--output", from: arguments)
                )
            )
        }

        if command == "mvp-proof" {
            let appId = stringArgument(named: "--app-id", from: arguments) ?? "winapp_notepad"
            guard !appId.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                throw VMControlError.missingAppId
            }
            let waitSeconds = waitSecondsArgument(from: arguments) ?? 30
            return VMControlArguments(
                command: .mvpProof(
                    json: arguments.contains("--json"),
                    appId: appId,
                    waitSeconds: waitSeconds,
                    outputPath: stringArgument(named: "--output", from: arguments),
                    requireProved: arguments.contains("--require-proved")
                )
            )
        }

        if command == "multi-app-proof" {
            let appIds = appIdsArgument(from: arguments) ?? WindowsAppRuntimeProofCoverageDefaults.targetAppIds
            guard !appIds.isEmpty else {
                throw VMControlError.missingMultiAppProofAppIds
            }
            return VMControlArguments(
                command: .multiAppProof(
                    json: arguments.contains("--json"),
                    appIds: appIds,
                    waitSeconds: waitSecondsArgument(from: arguments) ?? 10,
                    outputDirectoryPath: stringArgument(named: "--output-dir", from: arguments),
                    requireComplete: arguments.contains("--require-complete")
                )
            )
        }

        if command == "notification-proof" {
            return VMControlArguments(
                command: .notificationProof(
                    json: arguments.contains("--json"),
                    waitSeconds: waitSecondsArgument(from: arguments) ?? 30,
                    outputPath: stringArgument(named: "--output", from: arguments),
                    requireProved: arguments.contains("--require-proved")
                )
            )
        }

        if command == "printer-bridge-plan" {
            return VMControlArguments(
                command: .printerBridgePlan(
                    json: arguments.contains("--json"),
                    sharedPrinterName: stringArgument(named: "--shared-printer", from: arguments),
                    windowsPrinterName: stringArgument(named: "--windows-printer-name", from: arguments)
                )
            )
        }

        if command == "printer-bridge-proof" {
            guard let evidencePath = stringArgument(named: "--evidence", from: arguments),
                  !evidencePath.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                throw VMControlError.missingPrinterBridgeEvidencePath
            }
            return VMControlArguments(
                command: .printerBridgeProof(
                    json: arguments.contains("--json"),
                    evidencePath: evidencePath,
                    sharedPrinterName: stringArgument(named: "--shared-printer", from: arguments),
                    windowsPrinterName: stringArgument(named: "--windows-printer-name", from: arguments),
                    outputPath: stringArgument(named: "--output", from: arguments)
                )
            )
        }

        if command == "guest-agent-wait" {
            let waitSeconds = waitSecondsArgument(from: arguments) ?? 30
            return VMControlArguments(command: .guestAgentWait(json: arguments.contains("--json"), waitSeconds: waitSeconds))
        }

        if command == "mark-installed" {
            return VMControlArguments(command: .markInstalled(json: arguments.contains("--json")))
        }

        if command == "qemu-plan" {
            return VMControlArguments(command: .qemuPlan(json: arguments.contains("--json")))
        }

        if command == "qemu-doctor" {
            return VMControlArguments(command: .qemuDoctor(json: arguments.contains("--json")))
        }

        if command == "qemu-install-status" {
            return VMControlArguments(command: .qemuInstallStatus(json: arguments.contains("--json")))
        }

        if command == "qemu-smoke" {
            let seconds = secondsArgument(from: arguments) ?? 45
            return VMControlArguments(command: .qemuSmoke(json: arguments.contains("--json"), seconds: seconds))
        }

        if command == "qemu-start" {
            let waitSeconds = waitSecondsArgument(from: arguments) ?? 15
            let displayMode: QEMUStartDisplayMode = arguments.contains("--native-display")
                ? .nativeCocoa
                : .embedded
            return VMControlArguments(
                command: .qemuStart(
                    json: arguments.contains("--json"),
                    waitSeconds: waitSeconds,
                    displayMode: displayMode
                )
            )
        }

        if command == "qemu-display-smoke" {
            let waitSeconds = waitSecondsArgument(from: arguments) ?? 5
            return VMControlArguments(command: .qemuDisplaySmoke(json: arguments.contains("--json"), waitSeconds: waitSeconds))
        }

        if command == "qemu-capture" {
            return VMControlArguments(
                command: .qemuCapture(
                    json: arguments.contains("--json"),
                    outputPath: stringArgument(named: "--output", from: arguments)
                )
            )
        }

        if command == "qemu-powerdown" {
            let waitSeconds = waitSecondsArgument(from: arguments) ?? 30
            return VMControlArguments(command: .qemuPowerDown(json: arguments.contains("--json"), waitSeconds: waitSeconds))
        }

        if command == "qemu-force-stop" {
            let waitSeconds = waitSecondsArgument(from: arguments) ?? 10
            return VMControlArguments(
                command: .qemuForceStop(
                    json: arguments.contains("--json"),
                    waitSeconds: waitSeconds,
                    isAuthorized: QEMUForceStopAuthorization.isAuthorized(arguments: arguments)
                )
            )
        }

        if command == "qemu-sendkey" {
            let keys = arguments
                .dropFirst()
                .filter { !$0.hasPrefix("--") }
            guard !keys.isEmpty else {
                throw VMControlError.missingQEMUKeySequence
            }
            return VMControlArguments(command: .qemuSendKey(json: arguments.contains("--json"), keys: Array(keys)))
        }

        if command == "qemu-type-text" {
            guard let text = stringArgument(named: "--text", from: arguments),
                  !text.isEmpty else {
                throw VMControlError.missingQEMUText
            }
            return VMControlArguments(command: .qemuTypeText(json: arguments.contains("--json"), text: text))
        }

        if command == "qemu-click" {
            guard let x = intArgument(named: "--x", from: arguments),
                  let y = intArgument(named: "--y", from: arguments) else {
                throw VMControlError.missingQEMUPointerCoordinate
            }
            return VMControlArguments(command: .qemuClick(json: arguments.contains("--json"), x: x, y: y))
        }

        if command == "qemu-oobe-bypass" {
            return VMControlArguments(command: .qemuOOBEBypass(json: arguments.contains("--json")))
        }

        if command == "qemu-install-agent" {
            return VMControlArguments(
                command: .qemuInstallAgent(
                    json: arguments.contains("--json"),
                    waitSeconds: waitSecondsArgument(from: arguments) ?? 30
                )
            )
        }

        if command == "qemu-prepare-sparse-package" {
            return VMControlArguments(
                command: .qemuPrepareSparsePackage(
                    json: arguments.contains("--json"),
                    waitSeconds: waitSecondsArgument(from: arguments) ?? 120
                )
            )
        }

        guard command == "prepare" else {
            throw VMControlError.unsupportedCommand(command)
        }

        guard let installerFlagIndex = arguments.firstIndex(of: "--installer"),
              arguments.indices.contains(installerFlagIndex + 1) else {
            throw VMControlError.missingInstallerPath
        }

        return VMControlArguments(
            command: .prepare(
                installerPath: arguments[installerFlagIndex + 1],
                driverMediaPath: stringArgument(named: "--drivers", from: arguments)
            )
        )
    }

    /// This process has no window server connection to read a backing scale factor from, so the scale is
    /// supplied explicitly or not at all. Absent reports the display scaling state as unknown, which beats
    /// guessing 1 and telling every Retina user to change a setting that was already correct.
    private static func hostBackingScaleArgument(from arguments: [String]) throws -> Double? {
        guard let requested = stringArgument(named: "--host-backing-scale", from: arguments) else {
            return nil
        }

        // A typo fails loudly. Silently ignoring it would report the scale as unknown while the user
        // believes they supplied it.
        guard let parsed = Double(requested), parsed >= 0.5, parsed <= 4 else {
            throw VMControlError.invalidHostBackingScale(requested)
        }

        return parsed
    }

    private static func secondsArgument(from arguments: [String]) -> Int? {
        guard let secondsFlagIndex = arguments.firstIndex(of: "--seconds"),
              arguments.indices.contains(secondsFlagIndex + 1) else {
            return nil
        }

        return Int(arguments[secondsFlagIndex + 1])
    }

    private static func waitSecondsArgument(from arguments: [String]) -> Int? {
        guard let secondsFlagIndex = arguments.firstIndex(of: "--wait-seconds"),
              arguments.indices.contains(secondsFlagIndex + 1) else {
            return nil
        }

        return Int(arguments[secondsFlagIndex + 1])
    }

    private static func appIdsArgument(from arguments: [String]) -> [String]? {
        guard let appIdsValue = stringArgument(named: "--app-ids", from: arguments) else {
            return nil
        }

        return appIdsValue
            .split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }

    private static func stringArgument(named name: String, from arguments: [String]) -> String? {
        guard let flagIndex = arguments.firstIndex(of: name),
              arguments.indices.contains(flagIndex + 1) else {
            return nil
        }

        return arguments[flagIndex + 1]
    }

    private static func intArgument(named name: String, from arguments: [String]) -> Int? {
        stringArgument(named: name, from: arguments).flatMap(Int.init)
    }
}
