import Foundation
import Darwin
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
    case missingQEMUKeySequence
    case missingQEMUText
    case missingQEMUPointerCoordinate
    case missingAppId
    case missingAppRuntimeAction
    case unsupportedAppRuntimeAction(String)
    case missingWindowId
    case missingAppRuntimeText
    case missingAppRuntimePointerCoordinate
    case qemuAlreadyRunning(pid: Int32, monitorSocketPath: String?)
    case missingForceStopAcknowledgement
    case mvpProofNotProved([String])

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
        case .missingQEMUKeySequence:
            "Missing QEMU key sequence. Pass keys such as shift-f10, esc, tab, ret, or spc."
        case .missingQEMUText:
            "Missing QEMU text. Pass qemu-type-text --text \"...\" with bounded ASCII input."
        case .missingQEMUPointerCoordinate:
            "Missing QEMU pointer coordinates. Pass --x and --y as absolute values from 0 to 32767."
        case .missingAppId:
            "Missing Windows app id. Pass --app-id winapp_notepad, winapp_calculator, or another id reported by app-runtime-status."
        case .missingAppRuntimeAction:
            "Missing app runtime action. Pass --action launch, fulfill-pending, focus, close, close-all, restore, bring-forward, quiet-when-idle, stop-runtime, clipboard, type-text, click, or proof-recommended."
        case .unsupportedAppRuntimeAction(let action):
            "Unsupported app runtime action '\(action)'. Pass --action launch, fulfill-pending, focus, close, close-all, restore, bring-forward, quiet-when-idle, stop-runtime, clipboard, type-text, click, or proof-recommended."
        case .missingWindowId:
            "Missing Windows window id. Pass --window-id hwnd:XXXXXXXX from app-runtime-status or app-window-proof."
        case .missingAppRuntimeText:
            "Missing app runtime text. Pass --text \"...\" for clipboard or type-text actions."
        case .missingAppRuntimePointerCoordinate:
            "Missing app runtime pointer coordinates. Pass --x and --y as non-negative guest-window coordinates."
        case .qemuAlreadyRunning(let pid, let monitorSocketPath):
            monitorSocketPath.map {
                "QEMU is already running as PID \(pid). Close the existing QEMU/Windows window, or use qemu-powerdown when the process was launched from the current Veil diagnostics path. Monitor socket: \($0)"
            } ?? "QEMU is already running as PID \(pid) with the configured Windows disk attached. Shut down that VM before starting another one."
        case .missingForceStopAcknowledgement:
            "Force stop can interrupt Windows disk writes. Re-run with \(QEMUForceStopAuthorization.acknowledgementFlag) only when the VM cannot shut down normally."
        case .mvpProofNotProved(let nextActions):
            "MVP proof did not reach proved status. \(nextActions.joined(separator: " "))"
        }
    }

    private static let usage = "Usage: veil-vmctl prepare --installer /path/to/Windows.iso [--drivers /path/to/virtio-win.iso] | veil-vmctl app-runtime-status [--json] [--demo] | veil-vmctl app-runtime-action --action launch|fulfill-pending|focus|close|close-all|restore|bring-forward|quiet-when-idle|stop-runtime|clipboard|type-text|click|proof-recommended [--json] [--demo] [--app-id winapp_notepad] [--window-id hwnd:XXXXXXXX] [--text \"...\"] [--x 240 --y 130] | veil-vmctl app-window-proof [--json] [--app-id winapp_notepad] [--wait-seconds 10] [--output /path/to/proof.json] | veil-vmctl coherence-proof [--json] [--app-id winapp_notepad] [--wait-seconds 10] [--output /path/to/proof.json] | veil-vmctl mvp-proof [--json] [--app-id winapp_notepad] [--wait-seconds 30] [--output /path/to/proof.json] [--require-proved] | veil-vmctl guest-agent-wait [--json] [--wait-seconds 30] | veil-vmctl mark-installed [--json] | veil-vmctl providers [--json] | veil-vmctl qemu-plan [--json] | veil-vmctl qemu-doctor [--json] | veil-vmctl qemu-install-status [--json] | veil-vmctl qemu-smoke [--json] [--seconds 45] | veil-vmctl qemu-start [--json] [--wait-seconds 15] [--native-display] | veil-vmctl qemu-display-smoke [--json] [--wait-seconds 5] | veil-vmctl qemu-capture [--json] [--output /path/to/console.png] | veil-vmctl qemu-powerdown [--json] [--wait-seconds 30] | veil-vmctl qemu-force-stop [--json] --i-understand-data-loss [--wait-seconds 10] | veil-vmctl qemu-sendkey [--json] key [key ...] | veil-vmctl qemu-type-text [--json] --text \"...\" | veil-vmctl qemu-click [--json] --x 0...32767 --y 0...32767 | veil-vmctl qemu-oobe-bypass [--json] | veil-vmctl qemu-install-agent [--json]"
}

struct VMControlArguments {
    enum AppRuntimeAction: String, Equatable, Codable {
        case launch
        case fulfillPending = "fulfill-pending"
        case focus
        case close
        case closeAll = "close-all"
        case restore
        case bringForward = "bring-forward"
        case quietWhenIdle = "quiet-when-idle"
        case stopRuntime = "stop-runtime"
        case clipboard
        case typeText = "type-text"
        case click
        case proofRecommended = "proof-recommended"
    }

    enum QEMUStartDisplayMode: Equatable {
        case nativeCocoa
        case embedded
    }

    enum Command: Equatable {
        case prepare(installerPath: String, driverMediaPath: String?)
        case appRuntimeStatus(json: Bool, demo: Bool)
        case appRuntimeAction(json: Bool, demo: Bool, action: AppRuntimeAction, appId: String?, windowId: String?, text: String?, x: Int?, y: Int?)
        case appWindowProof(json: Bool, appId: String, waitSeconds: Int, outputPath: String?)
        case coherenceProof(json: Bool, appId: String, waitSeconds: Int, outputPath: String?)
        case mvpProof(json: Bool, appId: String, waitSeconds: Int, outputPath: String?, requireProved: Bool)
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
        case qemuInstallAgent(json: Bool)
    }

    var command: Command

    static func parse(_ arguments: [String]) throws -> VMControlArguments {
        guard let command = arguments.first else {
            throw VMControlError.missingCommand
        }

        if command == "providers" {
            return VMControlArguments(command: .providers(json: arguments.contains("--json")))
        }

        if command == "app-runtime-status" {
            return VMControlArguments(
                command: .appRuntimeStatus(
                    json: arguments.contains("--json"),
                    demo: arguments.contains("--demo")
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
                    y: intArgument(named: "--y", from: arguments)
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
            return VMControlArguments(command: .qemuInstallAgent(json: arguments.contains("--json")))
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

struct QEMUConsoleCaptureRecord: Codable, Equatable {
    var kind: String = "qemuConsoleCapture"
    var monitorSocketPath: String
    var consoleScreenshotPath: String
    var capturedAt: Date
}

struct QEMUKeySendResult: Codable, Equatable {
    var key: String
    var transport: String
    var socketPath: String
    var monitorCommand: String
    var terminationStatus: Int32?
    var didLaunchSender: Bool
}

struct QEMUKeySendRecord: Codable, Equatable {
    var kind: String = "qemuKeySend"
    var monitorSocketPath: String
    var keys: [String]
    var results: [QEMUKeySendResult]
    var sentAt: Date
}

struct QEMUPointerClickRecord: Codable, Equatable {
    var kind: String = "qemuPointerClick"
    var monitorSocketPath: String
    var qmpSocketPath: String
    var x: Int
    var y: Int
    var results: [QEMUKeySendResult]
    var sentAt: Date
}

struct QEMUPowerDownRecord: Codable, Equatable {
    var kind: String = "qemuPowerDown"
    var pid: Int32?
    var monitorSocketPath: String
    var qmpSocketPath: String?
    var transport: String
    var socketPath: String
    var command: String
    var didLaunchSender: Bool
    var terminationStatus: Int32?
    var waitedSeconds: Int
    var didExitWithinWait: Bool
    var requestedAt: Date
}

struct QEMUForceStopRecord: Codable, Equatable {
    var kind: String = "qemuForceStop"
    var pid: Int32?
    var signal: String
    var didSignalProcess: Bool
    var waitedSeconds: Int
    var didExitWithinWait: Bool
    var requestedAt: Date
}

struct QEMUDisplaySmokeRecord: Codable, Equatable {
    var kind: String = "qemuDisplaySmoke"
    var pid: Int32?
    var endpoint: String
    var width: Int
    var height: Int
    var frameSequence: Int
    var pixelByteCount: Int
    var waitedSeconds: Int
    var capturedAt: Date
}

enum AppRuntimeRecommendedProofRunStatus: String, Codable, Equatable {
    case proved
    case unavailable
}

struct AppRuntimeRecommendedProofRun: Codable, Equatable {
    var kind: String = "windowsAppRuntimeRecommendedProofRun"
    var proofKind: String
    var command: String
    var appId: String
    var status: AppRuntimeRecommendedProofRunStatus
    var savedProofPath: String?
    var windowId: String?
    var windowTitle: String?
    var frameSequence: Int?
    var inputEventCount: Int?
    var clipboardTextByteCount: Int?
    var nextActions: [String]
}

struct AppRuntimeActionReport: Codable, Equatable {
    var kind: String = "windowsAppRuntimeAction"
    var action: VMControlArguments.AppRuntimeAction
    var requestedAt: Date
    var endpoint: String
    var connectionMode: HostConnectionMode
    var accepted: Bool
    var appId: String?
    var windowId: String?
    var foregroundWindowId: String?
    var foregroundWindowTitle: String?
    var pendingLaunchAppId: String?
    var launchPlan: WindowsAppRuntimeLaunchPlanStatus?
    var proofPlan: WindowsAppRuntimeProofPlanStatus
    var launch: AppLaunchResponse?
    var window: WindowCreatedEvent?
    var focus: WindowFocusResponse?
    var close: WindowCloseResponse?
    var closedWindows: [WindowCloseResponse]
    var clipboard: ClipboardTextSet?
    var mouseInputs: [InputMouseEvent]
    var keyInputs: [InputKeyEvent]
    var typedTextCharacterCount: Int?
    var restoredWindows: [WindowCreatedEvent]
    var restoreRequestedAppIds: [String]
    var broughtForwardWindowIds: [String]
    var proof: AppRuntimeRecommendedProofRun?
    var quietRuntime: WindowsAppRuntimeQuietPolicyStatus?
    var runtimeStop: VMRuntimeSnapshot?
    var status: WindowsAppRuntimeStatusReport
    var nextActions: [String]
}

@main
struct VeilVMControl {
    static func main() async {
        do {
            let arguments = try VMControlArguments.parse(Array(CommandLine.arguments.dropFirst()))
            try await run(arguments)
        } catch {
            let message: String
            if let localized = error as? LocalizedError,
               let description = localized.errorDescription {
                message = description
            } else {
                message = String(describing: error)
            }

            FileHandle.standardError.write(Data("Error: \(message)\n".utf8))
            Foundation.exit(1)
        }
    }

    private static func run(_ arguments: VMControlArguments) async throws {
        switch arguments.command {
        case .prepare(let installerPath, let driverMediaPath):
            try await prepare(installerPath: installerPath, driverMediaPath: driverMediaPath)
        case .appRuntimeStatus(let json, let demo):
            try await printAppRuntimeStatus(json: json, demo: demo)
        case .appRuntimeAction(let json, let demo, let action, let appId, let windowId, let text, let x, let y):
            try await runAppRuntimeAction(json: json, demo: demo, action: action, appId: appId, windowId: windowId, text: text, x: x, y: y)
        case .appWindowProof(let json, let appId, let waitSeconds, let outputPath):
            try await proveAppWindow(json: json, appId: appId, waitSeconds: waitSeconds, outputPath: outputPath)
        case .coherenceProof(let json, let appId, let waitSeconds, let outputPath):
            try await proveCoherence(json: json, appId: appId, waitSeconds: waitSeconds, outputPath: outputPath)
        case .mvpProof(let json, let appId, let waitSeconds, let outputPath, let requireProved):
            try await proveMVP(json: json, appId: appId, waitSeconds: waitSeconds, outputPath: outputPath, requireProved: requireProved)
        case .guestAgentWait(let json, let waitSeconds):
            try await waitForGuestAgent(json: json, waitSeconds: waitSeconds)
        case .markInstalled(let json):
            try await markInstalled(json: json)
        case .providers(let json):
            try printProviders(json: json)
        case .qemuPlan(let json):
            try await printQEMUPlan(json: json)
        case .qemuDoctor(let json):
            try await printQEMUDoctor(json: json)
        case .qemuInstallStatus(let json):
            try await printQEMUInstallStatus(json: json)
        case .qemuSmoke(let json, let seconds):
            try await printQEMUSmoke(json: json, seconds: seconds)
        case .qemuStart(let json, let waitSeconds, let displayMode):
            try await startQEMU(json: json, waitSeconds: waitSeconds, displayMode: displayMode)
        case .qemuDisplaySmoke(let json, let waitSeconds):
            try smokeQEMUDisplay(json: json, waitSeconds: waitSeconds)
        case .qemuCapture(let json, let outputPath):
            try await captureQEMUConsole(json: json, outputPath: outputPath)
        case .qemuPowerDown(let json, let waitSeconds):
            try await powerDownQEMU(json: json, waitSeconds: waitSeconds)
        case .qemuForceStop(let json, let waitSeconds, let isAuthorized):
            try await forceStopQEMU(json: json, waitSeconds: waitSeconds, isAuthorized: isAuthorized)
        case .qemuSendKey(let json, let keys):
            try await sendQEMUKeys(json: json, keys: keys)
        case .qemuTypeText(let json, let text):
            try await typeQEMUText(json: json, text: text)
        case .qemuClick(let json, let x, let y):
            try await clickQEMU(json: json, x: x, y: y)
        case .qemuOOBEBypass(let json):
            try await sendQEMUOOBEBypass(json: json)
        case .qemuInstallAgent(let json):
            try await sendQEMUGuestAgentInstall(json: json)
        }
    }

    private static func prepare(installerPath: String, driverMediaPath: String?) async throws {
        let installerURL = URL(fileURLWithPath: installerPath)
        guard FileManager.default.fileExists(atPath: installerURL.path) else {
            throw VMControlError.installerNotFound(installerURL.path)
        }

        let driverMediaURL = driverMediaPath.map(URL.init(fileURLWithPath:))
        if let driverMediaURL,
           !FileManager.default.fileExists(atPath: driverMediaURL.path) {
            throw VMControlError.driverMediaNotFound(driverMediaURL.path)
        }

        let service = LocalVMRuntimeService()
        let preparedSnapshot = try await service.prepareDefaultVM()
        let configuredSnapshot = try await service.updateProfilePaths(
            installerMediaPath: installerURL.path,
            driverMediaPath: driverMediaURL?.path ?? preparedSnapshot.driverMediaPath,
            virtualDiskPath: preparedSnapshot.virtualDiskPath
        )
        let diagnosticsURL = try await service.exportDiagnostics(to: diagnosticsDirectory())
        let profile = try await JSONVMProfileStore().load()

        print("Veil VM prepared")
        print("Profile: \(configuredSnapshot.profileName ?? "Not configured")")
        print("Installer: \(configuredSnapshot.installerMediaPath ?? "Not selected")")
        print("Drivers: \(configuredSnapshot.driverMediaPath ?? "Not selected")")
        print("Virtual disk: \(configuredSnapshot.virtualDiskPath ?? "Not selected")")
        print("Shared folder: \(profile?.sharedFolderPath ?? "Not configured")")
        print("Boot ready: \(configuredSnapshot.bootReady ? "yes" : "no")")
        print("Detail: \(configuredSnapshot.detail)")
        print("Diagnostics: \(diagnosticsURL.path)")
    }

    @MainActor
    private static func printAppRuntimeStatus(json: Bool, demo: Bool) async throws {
        let model = HostDashboardModel(service: appRuntimeStatusService(demo: demo))

        await model.loadRestoreIntent()
        await model.load()

        let report = model.runtimeStatusReport()
        if json {
            let data = try JSONEncoder.veilDiagnostics.encode(report)
            print(String(decoding: data, as: UTF8.self))
            return
        }

        print("Windows app runtime: \(report.connection.mode.rawValue)")
        print("Live agent: \(report.connection.hasLiveAgentConnection ? "yes" : "no")")
        if let agentVersion = report.connection.agentVersion {
            print("Agent: \(agentVersion)")
        }
        if let detail = report.connection.connectionDetail {
            print("Detail: \(detail)")
        }
        print("Pending launch queued: \(report.pendingLaunch.isQueued ? "yes" : "no")")
        if let pendingLaunchAppId = report.pendingLaunch.appId {
            print("Pending launch app: \(pendingLaunchAppId)")
        }
        print("Pending launch auto-reconnect: \(report.pendingLaunch.willLaunchOnAgentReconnect ? "yes" : "no")")
        print("Pending launch action: \(report.pendingLaunch.recommendedAction)")
        print("Apps: \(report.apps.count)")
        print("Open Windows app windows: \(report.mirrorSessions.count)")
        print("Dock integration: \(report.dockIntegration.isEnabled ? "enabled" : "disabled")")
        print("Dock pending launches: \(report.dockIntegration.pendingLaunchCount)")
        print("Dock runtime badge: \(report.dockIntegration.badgeLabel ?? "none")")
        print("Dock can bring apps forward: \(report.dockIntegration.canBringWindowsAppsForward ? "yes" : "no")")
        print("Launcher action: \(report.launcherVisibility.recommendedAction)")
        print("Launcher hidden for apps: \(report.launcherVisibility.shouldHideMainWindow ? "yes" : "no")")
        print("Visible surface: \(report.visibleSurfacePolicy.primarySurface)")
        print("Expected visible surfaces: \(report.visibleSurfacePolicy.expectedVisibleSurfaceCount)")
        print("Recovery display: \(report.visibleSurfacePolicy.keepsRecoveryDisplayManual ? "manual" : "automatic")")
        print("Mac window integration: \(report.macWindowIntegration.isEnabled ? "enabled" : "disabled")")
        print("Mac windows auto-open: \(report.macWindowIntegration.acceptsGuestWindowEvents ? "ready" : "waiting")")
        print("Mac mirrored windows: \(report.macWindowIntegration.mirroredWindowCount)")
        print("Mac foregroundable windows: \(report.macWindowIntegration.foregroundableWindowCount)")
        if let foregroundWindowId = report.macWindowIntegration.foregroundWindowId {
            print("Mac foreground window: \(foregroundWindowId)")
        }
        if let foregroundWindowTitle = report.macWindowIntegration.foregroundWindowTitle {
            print("Mac foreground title: \(foregroundWindowTitle)")
        }
        print("Launch plan: \(report.launchPlan.recommendedAction)")
        print("Launch plan reason: \(report.launchPlan.reason)")
        if let startCommand = report.launchPlan.recommendedStartCommand {
            print("Launch start command: \(startCommand)")
        }
        if let waitCommand = report.launchPlan.recommendedWaitCommand {
            print("Launch wait command: \(waitCommand)")
        }
        if let launchCommand = report.launchPlan.recommendedLaunchCommand {
            print("Launch app command: \(launchCommand)")
        }
        print("Proof plan reason: \(report.proofPlan.reason)")
        print("Proof app-window ready: \(report.proofPlan.canRunAppWindowProof ? "yes" : "no")")
        print("Proof coherence ready: \(report.proofPlan.canRunCoherenceProof ? "yes" : "no")")
        print("Proof MVP ready: \(report.proofPlan.canRunMVPProof ? "yes" : "no")")
        if let proofCommand = report.proofPlan.recommendedAppWindowProofCommand {
            print("Proof app-window command: \(proofCommand)")
        }
        if let proofCommand = report.proofPlan.recommendedCoherenceProofCommand {
            print("Proof coherence command: \(proofCommand)")
        }
        if let proofCommand = report.proofPlan.recommendedMVPProofCommand {
            print("Proof MVP command: \(proofCommand)")
        }
        print("Proof artifacts: \(report.proofArtifacts.reason)")
        if let latestProofKind = report.proofArtifacts.latestProofKind {
            print("Latest proof kind: \(latestProofKind)")
        }
        if let latestProofPath = report.proofArtifacts.latestProofPath {
            print("Latest proof artifact: \(latestProofPath)")
        }
        print("Quiet runtime ready: \(report.quietRuntime.canQuietRuntime ? "yes" : "no")")
        print("Quiet runtime auto: \(report.quietRuntime.willQuietAutomatically ? "yes" : "no")")
        print("Quiet runtime delay: \(report.quietRuntime.automaticQuietDelaySeconds)s")
        print("Quiet runtime recommendation: \(report.quietRuntime.recommendedAction)")
        if let stopCommand = report.quietRuntime.recommendedStopCommand {
            print("Quiet runtime stop command: \(stopCommand)")
        }
        print("Quiet runtime reason: \(report.quietRuntime.reason)")
        print("Restorable apps: \(report.restorableAppIds.joined(separator: ", "))")
        print("Actions:")
        for action in report.actions {
            print("  - \(action.id): \(action.isAvailable ? "available" : "unavailable")")
        }
    }

    private static func appRuntimeStatusService(demo: Bool) -> any HostDashboardService {
        if demo {
            return DemoHostDashboardService()
        }

        let endpoint = ProcessInfo.processInfo.environment["VEIL_AGENT_URL"] ?? "ws://127.0.0.1:18444"
        let url = URL(string: endpoint) ?? URL(string: "ws://127.0.0.1:18444")!
        return FallbackHostDashboardService(
            primary: VeilHostClient(
                transport: URLSessionWebSocketTransport(url: url)
            ),
            fallback: DemoHostDashboardService(),
            primaryEndpointDescription: endpoint
        )
    }

    @MainActor
    private static func runAppRuntimeAction(
        json: Bool,
        demo: Bool,
        action: VMControlArguments.AppRuntimeAction,
        appId: String?,
        windowId: String?,
        text: String?,
        x: Int?,
        y: Int?
    ) async throws {
        let endpoint = demo
            ? "demo"
            : ProcessInfo.processInfo.environment["VEIL_AGENT_URL"] ?? "ws://127.0.0.1:18444"
        let service = appRuntimeStatusService(demo: demo)
        let model = HostDashboardModel(service: service)
        await model.loadRestoreIntent()
        await model.load()

        var launch: AppLaunchResponse?
        var window: WindowCreatedEvent?
        var focus: WindowFocusResponse?
        var close: WindowCloseResponse?
        var closedWindows: [WindowCloseResponse] = []
        var clipboard: ClipboardTextSet?
        var mouseInputs: [InputMouseEvent] = []
        var keyInputs: [InputKeyEvent] = []
        var typedTextCharacterCount: Int?
        var restoredWindows: [WindowCreatedEvent] = []
        var restoreRequestedAppIds: [String] = []
        var broughtForwardWindowIds: [String] = []
        var proof: AppRuntimeRecommendedProofRun?
        var foregroundWindowId: String?
        var foregroundWindowTitle: String?
        var quietRuntime: WindowsAppRuntimeQuietPolicyStatus?
        var runtimeStop: VMRuntimeSnapshot?
        var accepted = false
        var resolvedAppId = appId
        var resolvedWindowId = windowId

        switch action {
        case .launch:
            let launchAppId = appId ?? "winapp_notepad"
            guard !launchAppId.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                throw VMControlError.missingAppId
            }

            let result: WindowsAppLaunchResult?
            if demo {
                result = await model.launchApp(appId: launchAppId)
            } else {
                model.selectedAppId = launchAppId
                await model.launchSelectedApp()
                result = model.lastLaunch?.window.appId == launchAppId ? model.lastLaunch : nil
            }

            launch = result?.launch
            window = result?.window
            resolvedAppId = launchAppId
            resolvedWindowId = result?.window.windowId
            foregroundWindowId = result?.window.windowId
            foregroundWindowTitle = result?.window.title
            accepted = result?.launch.accepted == true
        case .fulfillPending:
            let result = await model.refreshLiveAgentIfNeeded()
            launch = result?.launch
            window = result?.window
            resolvedAppId = result?.window.appId ?? model.pendingLaunchAppId
            resolvedWindowId = result?.window.windowId
            foregroundWindowId = result?.window.windowId
            foregroundWindowTitle = result?.window.title
            accepted = result?.launch.accepted == true
        case .focus:
            guard let focusWindowId = windowId,
                  !focusWindowId.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                throw VMControlError.missingWindowId
            }
            focus = await model.focusMirrorSession(windowId: focusWindowId)
            if focus == nil {
                focus = try await service.focusWindow(windowId: focusWindowId)
            }
            accepted = focus?.accepted == true
            resolvedWindowId = focusWindowId
            foregroundWindowId = accepted ? focusWindowId : nil
            foregroundWindowTitle = model.mirrorSessions.first { $0.id == focusWindowId }?.window.title
        case .close:
            guard let closeWindowId = windowId,
                  !closeWindowId.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                throw VMControlError.missingWindowId
            }
            close = await model.closeMirrorSession(windowId: closeWindowId)
            if close == nil {
                close = try await service.closeWindow(windowId: closeWindowId)
            }
            accepted = close?.accepted == true
            resolvedWindowId = closeWindowId
        case .closeAll:
            closedWindows = await model.closeAllMirrorSessions()
            accepted = !closedWindows.isEmpty && closedWindows.allSatisfy(\.accepted)
        case .restore:
            restoreRequestedAppIds = model.restorableAppIds
            let restored = await model.restoreMirroredWindowsAfterReconnect()
            restoredWindows = restored.map(\.window)
            if let foregroundWindow = restoredWindows.last {
                resolvedWindowId = foregroundWindow.windowId
                foregroundWindowId = foregroundWindow.windowId
                foregroundWindowTitle = foregroundWindow.title
            }
            accepted = !restored.isEmpty
        case .bringForward:
            broughtForwardWindowIds = model.mirrorSessions.map(\.id)
            if let foregroundSession = model.mirrorSessions.last {
                focus = await model.focusMirrorSession(windowId: foregroundSession.id)
                resolvedWindowId = foregroundSession.id
                foregroundWindowId = foregroundSession.id
                foregroundWindowTitle = foregroundSession.window.title
            }
            accepted = !broughtForwardWindowIds.isEmpty
        case .quietWhenIdle:
            quietRuntime = model.quietRuntimeStatus()
            accepted = quietRuntime?.canQuietRuntime == true
        case .stopRuntime:
            quietRuntime = model.quietRuntimeStatus()
            if quietRuntime?.canQuietRuntime == true {
                runtimeStop = try await LocalVMRuntimeService().stop()
                accepted = runtimeStop?.state == .stopped
            }
        case .clipboard:
            guard let text,
                  !text.isEmpty else {
                throw VMControlError.missingAppRuntimeText
            }
            clipboard = ClipboardTextSet(
                requestId: "req_app_runtime_clipboard",
                origin: "host",
                sequence: model.clipboardSequence + 1,
                text: text
            )
            if model.canSendHostClipboardText,
               let clipboard {
                try await service.sendClipboardText(clipboard)
                accepted = true
            }
        case .typeText:
            guard let inputWindowId = windowId,
                  !inputWindowId.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                throw VMControlError.missingWindowId
            }
            guard let text,
                  !text.isEmpty else {
                throw VMControlError.missingAppRuntimeText
            }
            keyInputs = try VeilHostClient.keyInputs(windowId: inputWindowId, text: text)
            typedTextCharacterCount = text.count
            resolvedWindowId = inputWindowId
            if model.hasLiveAgentConnection,
               model.health?.capabilities.input == true {
                for input in keyInputs {
                    try await service.sendKeyInput(input)
                }
                accepted = true
            }
        case .click:
            guard let inputWindowId = windowId,
                  !inputWindowId.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                throw VMControlError.missingWindowId
            }
            guard let x,
                  let y,
                  x >= 0,
                  y >= 0 else {
                throw VMControlError.missingAppRuntimePointerCoordinate
            }
            mouseInputs = [
                InputMouseEvent(windowId: inputWindowId, event: "leftDown", x: x, y: y),
                InputMouseEvent(windowId: inputWindowId, event: "leftUp", x: x, y: y)
            ]
            resolvedWindowId = inputWindowId
            if model.hasLiveAgentConnection,
               model.health?.capabilities.input == true {
                for input in mouseInputs {
                    try await service.sendMouseInput(input)
                }
                accepted = true
            }
        case .proofRecommended:
            let currentStatus = model.runtimeStatusReport()
            if let proofCommand = currentStatus.proofPlan.recommendedProofCommand,
               let proofKind = currentStatus.proofPlan.recommendedProofKind,
               let proofAppId = currentStatus.proofPlan.selectedAppId {
                proof = try await runRecommendedProof(
                    proofKind: proofKind,
                    command: proofCommand,
                    appId: proofAppId,
                    endpoint: endpoint
                )
                resolvedAppId = proofAppId
                resolvedWindowId = proof?.windowId
                foregroundWindowId = proof?.windowId
                foregroundWindowTitle = proof?.windowTitle
                accepted = proof?.status == .proved
            }
        }

        let status = model.runtimeStatusReport()
        let actionLaunchPlan = action == .launch || action == .fulfillPending ? status.launchPlan : nil
        let report = AppRuntimeActionReport(
            action: action,
            requestedAt: Date(),
            endpoint: endpoint,
            connectionMode: status.connection.mode,
            accepted: accepted,
            appId: resolvedAppId,
            windowId: resolvedWindowId,
            foregroundWindowId: foregroundWindowId,
            foregroundWindowTitle: foregroundWindowTitle,
            pendingLaunchAppId: status.pendingLaunchAppId,
            launchPlan: actionLaunchPlan,
            proofPlan: status.proofPlan,
            launch: launch,
            window: window,
            focus: focus,
            close: close,
            closedWindows: closedWindows,
            clipboard: clipboard,
            mouseInputs: mouseInputs,
            keyInputs: keyInputs,
            typedTextCharacterCount: typedTextCharacterCount,
            restoredWindows: restoredWindows,
            restoreRequestedAppIds: restoreRequestedAppIds,
            broughtForwardWindowIds: broughtForwardWindowIds,
            proof: proof,
            quietRuntime: quietRuntime,
            runtimeStop: runtimeStop,
            status: status,
            nextActions: nextActions(for: action, accepted: accepted, status: status)
        )

        if json {
            let data = try JSONEncoder.veilDiagnostics.encode(report)
            print(String(decoding: data, as: UTF8.self))
            return
        }

        print("Windows app runtime action: \(report.action.rawValue)")
        print("Accepted: \(report.accepted ? "yes" : "no")")
        print("Endpoint: \(report.endpoint)")
        if let appId = report.appId {
            print("App: \(appId)")
        }
        if let windowId = report.windowId {
            print("Window: \(windowId)")
        }
        if let foregroundWindowId = report.foregroundWindowId {
            print("Foreground window id: \(foregroundWindowId)")
        }
        if let foregroundWindowTitle = report.foregroundWindowTitle {
            print("Foreground window: \(foregroundWindowTitle)")
        }
        if let pendingLaunchAppId = report.pendingLaunchAppId {
            print("Pending launch app: \(pendingLaunchAppId)")
        }
        if let launchPlan = report.launchPlan {
            print("Launch plan: \(launchPlan.recommendedAction)")
            print("Launch plan reason: \(launchPlan.reason)")
            if let startCommand = launchPlan.recommendedStartCommand {
                print("Launch start command: \(startCommand)")
            }
            if let waitCommand = launchPlan.recommendedWaitCommand {
                print("Launch wait command: \(waitCommand)")
            }
            if let launchCommand = launchPlan.recommendedLaunchCommand {
                print("Launch app command: \(launchCommand)")
            }
        }
        print("Proof plan: \(report.proofPlan.reason)")
        if let proofKind = report.proofPlan.recommendedProofKind {
            print("Proof recommended kind: \(proofKind)")
        }
        if let proofCommand = report.proofPlan.recommendedProofCommand {
            print("Proof recommended command: \(proofCommand)")
        }
        if let proofCommand = report.proofPlan.recommendedAppWindowProofCommand {
            print("Proof app-window command: \(proofCommand)")
        }
        if let proofCommand = report.proofPlan.recommendedCoherenceProofCommand {
            print("Proof coherence command: \(proofCommand)")
        }
        if let proofCommand = report.proofPlan.recommendedMVPProofCommand {
            print("Proof MVP command: \(proofCommand)")
        }
        if let window = report.window {
            print("Window title: \(window.title)")
        }
        if let clipboard = report.clipboard {
            print("Clipboard bytes: \(Data(clipboard.text.utf8).count)")
        }
        if !report.closedWindows.isEmpty {
            print("Closed Windows app windows: \(report.closedWindows.map(\.windowId).joined(separator: ", "))")
        }
        if !report.mouseInputs.isEmpty {
            print("Mouse events: \(report.mouseInputs.count)")
        }
        if !report.keyInputs.isEmpty {
            print("Key events: \(report.keyInputs.count)")
        }
        if !report.broughtForwardWindowIds.isEmpty {
            print("Brought forward windows: \(report.broughtForwardWindowIds.joined(separator: ", "))")
        }
        if !report.restoreRequestedAppIds.isEmpty {
            print("Restore requested apps: \(report.restoreRequestedAppIds.joined(separator: ", "))")
        }
        if let proof = report.proof {
            print("Recommended proof: \(proof.proofKind) \(proof.status.rawValue)")
            print("Proof command: \(proof.command)")
            if let windowId = proof.windowId {
                print("Proof window: \(windowId)")
            }
            if let savedProofPath = proof.savedProofPath {
                print("Proof artifact: \(savedProofPath)")
            }
        }
        if let runtimeStop = report.runtimeStop {
            print("Runtime stop state: \(runtimeStop.state.rawValue)")
            print("Runtime stop detail: \(runtimeStop.detail)")
        }
        print("Open Windows app windows: \(report.status.mirrorSessions.count)")
        print("Next actions:")
        for action in report.nextActions {
            print("  - \(action)")
        }
    }

    private static func runRecommendedProof(
        proofKind: String,
        command: String,
        appId: String,
        endpoint: String
    ) async throws -> AppRuntimeRecommendedProofRun {
        let url = URL(string: endpoint) ?? URL(string: "ws://127.0.0.1:18444")!
        let transport = URLSessionWebSocketTransport(url: url)
        let client = VeilHostClient(transport: transport)

        switch proofKind {
        case "app-window":
            let report = try await client.proveAppWindow(
                appId: appId,
                endpoint: endpoint,
                eventSource: transport
            )
            return AppRuntimeRecommendedProofRun(
                proofKind: proofKind,
                command: command,
                appId: appId,
                status: .proved,
                savedProofPath: report.savedProofPath,
                windowId: report.window.windowId,
                windowTitle: report.window.title,
                frameSequence: report.frame.sequence,
                inputEventCount: nil,
                clipboardTextByteCount: nil,
                nextActions: report.nextActions
            )
        case "coherence":
            let report = try await client.proveCoherenceAppWindow(
                appId: appId,
                endpoint: endpoint,
                eventSource: transport
            )
            return AppRuntimeRecommendedProofRun(
                proofKind: proofKind,
                command: command,
                appId: appId,
                status: .proved,
                savedProofPath: report.savedProofPath,
                windowId: report.window.windowId,
                windowTitle: report.window.title,
                frameSequence: report.postInputFrame.sequence,
                inputEventCount: report.input.mouseEventsPosted.count + report.input.keyEventsPosted.count,
                clipboardTextByteCount: report.input.clipboardTextByteCount,
                nextActions: report.nextActions
            )
        case "mvp":
            let report = try await client.proveMVPAppRuntime(
                appId: appId,
                endpoint: endpoint,
                eventSource: transport
            )
            return AppRuntimeRecommendedProofRun(
                proofKind: proofKind,
                command: command,
                appId: appId,
                status: report.status == .proved ? .proved : .unavailable,
                savedProofPath: report.savedProofPath,
                windowId: report.coherence?.window.windowId,
                windowTitle: report.coherence?.window.title,
                frameSequence: report.coherence?.postInputFrame.sequence,
                inputEventCount: report.coherence.map { $0.input.mouseEventsPosted.count + $0.input.keyEventsPosted.count },
                clipboardTextByteCount: report.coherence?.input.clipboardTextByteCount,
                nextActions: report.nextActions
            )
        default:
            return AppRuntimeRecommendedProofRun(
                proofKind: proofKind,
                command: command,
                appId: appId,
                status: .unavailable,
                savedProofPath: nil,
                windowId: nil,
                windowTitle: nil,
                frameSequence: nil,
                inputEventCount: nil,
                clipboardTextByteCount: nil,
                nextActions: [
                    "Run `veil-vmctl app-runtime-status --json` and check proofPlan.recommendedProofKind before retrying."
                ]
            )
        }
    }

    private static func nextActions(
        for action: VMControlArguments.AppRuntimeAction,
        accepted: Bool,
        status: WindowsAppRuntimeStatusReport
    ) -> [String] {
        if accepted {
            switch action {
            case .launch, .fulfillPending:
                return compactActions([
                    "Open or focus the mirrored macOS app window from the menu bar.",
                    proofNextAction(from: status.proofPlan),
                    "Run `veil-vmctl app-runtime-status --json` to inspect the tracked HWND and available actions."
                ])
            case .focus:
                return compactActions([
                    "Confirm the macOS mirror window is frontmost.",
                    proofNextAction(from: status.proofPlan)
                ])
            case .close:
                return [
                    "Run `veil-vmctl app-runtime-status --json` to confirm the HWND no longer appears.",
                    "If Windows keeps the app open, collect guest-agent diagnostics from the shared folder."
                ]
            case .closeAll:
                return [
                    "Run `veil-vmctl app-runtime-status --json` to confirm no mirrored Windows app windows remain.",
                    "Run `veil-vmctl app-runtime-action --json --action quiet-when-idle` if the runtime is ready to quiet."
                ]
            case .restore:
                return compactActions([
                    "Open or focus restored mirrored windows from the menu bar.",
                    proofNextAction(from: status.proofPlan),
                    "Run `veil-vmctl app-runtime-status --json` to inspect restored sessions."
                ])
            case .bringForward:
                return compactActions([
                    "Confirm the mirrored Windows app windows are frontmost on macOS.",
                    proofNextAction(from: status.proofPlan),
                    "Run `veil-vmctl app-runtime-action --json --action focus --window-id ...` if one app window needs explicit guest focus."
                ])
            case .quietWhenIdle:
                return [
                    "Run `\(status.quietRuntime.recommendedStopCommand ?? "veil-vmctl app-runtime-action --json --action stop-runtime")` to stop the idle local Windows runtime.",
                    "Use `veil-vmctl qemu-powerdown --json --wait-seconds 30` only as a lower-level recovery command.",
                    "Run `veil-vmctl app-runtime-status --json` before relaunching a Windows app."
                ]
            case .stopRuntime:
                return [
                    "Run `veil-vmctl app-runtime-status --json` before relaunching a Windows app.",
                    "If Windows did not stop cleanly, export diagnostics before using force stop."
                ]
            case .clipboard:
                return compactActions([
                    "Use Cmd+V inside the mirrored Windows app window to paste the synced text.",
                    proofNextAction(from: status.proofPlan)
                ])
            case .typeText:
                return [
                    "Confirm the text appears in the focused Windows app.",
                    "Run `veil-vmctl app-runtime-action --json --action clipboard --text \"...\"` to validate clipboard transfer as well."
                ]
            case .click:
                return [
                    "Confirm the clicked control or text area is focused inside the Windows app.",
                    "Run `veil-vmctl app-runtime-action --json --action type-text --window-id ... --text veil` to validate keyboard input after the click."
                ]
            case .proofRecommended:
                return [
                    "Attach the proof artifact or JSON report to the current runtime gate.",
                    "Run `veil-vmctl app-runtime-status --json` to inspect the next available Windows app runtime action."
                ]
            }
        }

        if action == .proofRecommended {
            return compactActions([
                proofNextAction(from: status.proofPlan),
                "Run `veil-vmctl guest-agent-wait --json` if no proof command is available yet."
            ])
        }

        if action == .stopRuntime {
            return [
                "Run `veil-vmctl app-runtime-action --json --action quiet-when-idle` to confirm every mirrored Windows app window is closed.",
                "Run `veil-vmctl app-runtime-status --json` and check quietRuntime.reason before retrying stop-runtime."
            ]
        }

        if action == .launch || action == .fulfillPending {
            return launchRecoveryActions(from: status.launchPlan)
        }

        return [
            "Run `veil-vmctl guest-agent-wait --json` to confirm the Windows guest agent is connected.",
            "Run `veil-vmctl app-runtime-status --json` and check the requested app or window id before retrying."
        ]
    }

    private static func proofNextAction(from proofPlan: WindowsAppRuntimeProofPlanStatus) -> String? {
        guard let command = proofPlan.recommendedProofCommand else {
            return nil
        }

        if proofPlan.recommendedProofKind == "mvp" {
            return "Run `\(command)` to verify the full Windows app runtime loop."
        }

        if proofPlan.recommendedProofKind == "coherence" {
            return "Run `\(command)` to verify input and clipboard before MVP release."
        }

        if proofPlan.recommendedProofKind == "app-window" {
            return "Run `\(command)` to verify launch, HWND tracking, and first frame capture."
        }

        return "Run `\(command)` to verify the Windows app runtime proof gate."
    }

    private static func compactActions(_ actions: [String?]) -> [String] {
        actions.compactMap { action in
            guard let action,
                  !action.isEmpty else {
                return nil
            }
            return action
        }
    }

    private static func launchRecoveryActions(from launchPlan: WindowsAppRuntimeLaunchPlanStatus) -> [String] {
        var actions: [String] = []

        if let startCommand = launchPlan.recommendedStartCommand {
            actions.append("Run `\(startCommand)` to start the local Windows runtime for the selected app.")
        }

        if let waitCommand = launchPlan.recommendedWaitCommand {
            actions.append("Run `\(waitCommand)` to wait for the Windows guest agent.")
        }

        if let launchCommand = launchPlan.recommendedLaunchCommand {
            actions.append("Run `\(launchCommand)` after the guest agent connects.")
        }

        if actions.isEmpty {
            actions.append("Run `veil-vmctl app-runtime-status --json` and check the selected app before retrying.")
        }

        return actions
    }

    private static func proveAppWindow(json: Bool, appId: String, waitSeconds: Int, outputPath: String?) async throws {
        let endpoint = ProcessInfo.processInfo.environment["VEIL_AGENT_URL"] ?? "ws://127.0.0.1:18444"
        let url = URL(string: endpoint) ?? URL(string: "ws://127.0.0.1:18444")!
        let boundedWaitSeconds = min(max(waitSeconds, 1), 60)
        let transport = URLSessionWebSocketTransport(url: url)
        let client = VeilHostClient(transport: transport)
        var report = try await client.proveAppWindow(
            appId: appId,
            endpoint: endpoint,
            eventSource: transport,
            timeoutNanoseconds: UInt64(boundedWaitSeconds) * 1_000_000_000
        )
        if let outputURL = proofOutputURL(from: outputPath) {
            report.savedProofPath = outputURL.path
            try writeProof(report, to: outputURL)
        }

        if json {
            let data = try JSONEncoder.veilDiagnostics.encode(report)
            print(String(decoding: data, as: UTF8.self))
            return
        }

        print("Windows app window proof: \(report.appId)")
        print("Endpoint: \(report.endpoint)")
        print("PID: \(report.launch.processId)")
        print("Window: \(report.window.windowId) \(report.window.title)")
        print("Frame: \(report.frame.width)x\(report.frame.height) \(report.frame.format) #\(report.frame.sequence)")
        print("Frame bytes: \(report.frame.encodedByteCount)")
        if let savedProofPath = report.savedProofPath {
            print("Saved proof: \(savedProofPath)")
        }
        print("Next actions:")
        for action in report.nextActions {
            print("  - \(action)")
        }
    }

    private static func proveCoherence(json: Bool, appId: String, waitSeconds: Int, outputPath: String?) async throws {
        let endpoint = ProcessInfo.processInfo.environment["VEIL_AGENT_URL"] ?? "ws://127.0.0.1:18444"
        let url = URL(string: endpoint) ?? URL(string: "ws://127.0.0.1:18444")!
        let boundedWaitSeconds = min(max(waitSeconds, 1), 60)
        let transport = URLSessionWebSocketTransport(url: url)
        let client = VeilHostClient(transport: transport)
        var report = try await client.proveCoherenceAppWindow(
            appId: appId,
            endpoint: endpoint,
            eventSource: transport,
            timeoutNanoseconds: UInt64(boundedWaitSeconds) * 1_000_000_000
        )
        if let outputURL = proofOutputURL(from: outputPath) {
            report.savedProofPath = outputURL.path
            try writeProof(report, to: outputURL)
        }

        if json {
            let data = try JSONEncoder.veilDiagnostics.encode(report)
            print(String(decoding: data, as: UTF8.self))
            return
        }

        print("Windows app coherence proof: \(report.appId)")
        print("Endpoint: \(report.endpoint)")
        print("PID: \(report.launch.processId)")
        print("Window: \(report.window.windowId) \(report.window.title)")
        print("Initial frame: \(report.initialFrame.width)x\(report.initialFrame.height) \(report.initialFrame.format) #\(report.initialFrame.sequence)")
        print("Post-input frame: \(report.postInputFrame.width)x\(report.postInputFrame.height) \(report.postInputFrame.format) #\(report.postInputFrame.sequence)")
        let mouseEvents = report.input.mouseEventsPosted.joined(separator: ", ")
        print("Mouse events: \(mouseEvents)")
        print("Key events: \(report.input.keyEventsPosted.count)")
        print("Clipboard bytes: \(report.input.clipboardTextByteCount)")
        if let savedProofPath = report.savedProofPath {
            print("Saved proof: \(savedProofPath)")
        }
        print("Next actions:")
        for action in report.nextActions {
            print("  - \(action)")
        }
    }

    private static func proveMVP(json: Bool, appId: String, waitSeconds: Int, outputPath: String?, requireProved: Bool) async throws {
        let endpoint = ProcessInfo.processInfo.environment["VEIL_AGENT_URL"] ?? "ws://127.0.0.1:18444"
        let url = URL(string: endpoint) ?? URL(string: "ws://127.0.0.1:18444")!
        let boundedWaitSeconds = min(max(waitSeconds, 0), 300)
        let transport = URLSessionWebSocketTransport(url: url)
        let client = VeilHostClient(transport: transport)
        var report = try await client.proveMVPAppRuntime(
            appId: appId,
            endpoint: endpoint,
            eventSource: transport,
            waitSeconds: boundedWaitSeconds,
            proofTimeoutNanoseconds: UInt64(max(boundedWaitSeconds, 1)) * 1_000_000_000
        )
        if let outputURL = proofOutputURL(from: outputPath) {
            report.savedProofPath = outputURL.path
            try writeProof(report, to: outputURL)
        }

        if json {
            let data = try JSONEncoder.veilDiagnostics.encode(report)
            print(String(decoding: data, as: UTF8.self))
            if requireProved, report.status != .proved {
                throw VMControlError.mvpProofNotProved(report.nextActions)
            }
            return
        }

        print("Windows MVP proof: \(report.status.rawValue)")
        print("Endpoint: \(report.endpoint)")
        print("App: \(report.appId)")
        print("Agent wait: \(report.wait.status.rawValue) after \(report.wait.attempts) attempt(s)")
        if let coherence = report.coherence {
            print("Window: \(coherence.window.windowId) \(coherence.window.title)")
            print("Frames: #\(coherence.initialFrame.sequence) -> #\(coherence.postInputFrame.sequence)")
            print("Key events: \(coherence.input.keyEventsPosted.count)")
            print("Clipboard bytes: \(coherence.input.clipboardTextByteCount)")
        }
        if let savedProofPath = report.savedProofPath {
            print("Saved proof: \(savedProofPath)")
        }
        print("Next actions:")
        for action in report.nextActions {
            print("  - \(action)")
        }
        if requireProved, report.status != .proved {
            throw VMControlError.mvpProofNotProved(report.nextActions)
        }
    }

    private static func proofOutputURL(from outputPath: String?) -> URL? {
        guard let outputPath,
              !outputPath.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return nil
        }

        return URL(fileURLWithPath: outputPath)
    }

    private static func writeProof<T: Encodable>(_ report: T, to outputURL: URL) throws {
        let directory = outputURL.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let data = try JSONEncoder.veilDiagnostics.encode(report)
        try data.write(to: outputURL, options: .atomic)
    }

    private static func waitForGuestAgent(json: Bool, waitSeconds: Int) async throws {
        let endpoint = ProcessInfo.processInfo.environment["VEIL_AGENT_URL"] ?? "ws://127.0.0.1:18444"
        let url = URL(string: endpoint) ?? URL(string: "ws://127.0.0.1:18444")!
        let client = VeilHostClient(
            transport: URLSessionWebSocketTransport(url: url, requestTimeout: 3)
        )
        let report = await client.waitForAgentConnection(
            endpoint: endpoint,
            timeoutSeconds: waitSeconds
        )

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
            print("Capabilities: appLaunch=\(health.capabilities.appLaunch), windowCapture=\(health.capabilities.windowCapture), input=\(health.capabilities.input), clipboard=\(health.capabilities.clipboardText)")
        }
        if let errorMessage = report.diagnostic.errorMessage {
            print("Error: \(errorMessage)")
        }
        print("Next actions:")
        for action in report.nextActions {
            print("  - \(action)")
        }
    }

    private static func markInstalled(json: Bool) async throws {
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

    private static func printProviders(json: Bool) throws {
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

    private static func printQEMUPlan(json: Bool) async throws {
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

    private static func printQEMUDoctor(json: Bool) async throws {
        let profile = try await JSONVMProfileStore().load()
        let plan = try? profile.map(makeQEMUPlan(for:))
        let report = QEMUWindowsReadinessDoctor().makeReport(
            profile: profile,
            plan: plan
        )

        if json {
            let data = try JSONEncoder.veilDiagnostics.encode(report)
            print(String(decoding: data, as: UTF8.self))
            return
        }

        print("QEMU/HVF readiness: \(report.overallState.rawValue)")
        for check in report.checks {
            print("\(check.title): \(check.state.rawValue)")
            print("  \(check.detail)")
        }
        print("Next actions:")
        for action in report.nextActions {
            print("  - \(action)")
        }
    }

    private static func printQEMUInstallStatus(json: Bool) async throws {
        let snapshot = try await LocalVMRuntimeService().loadSnapshot()
        let report = snapshot.windowsInstallStatusReport()

        if json {
            let data = try JSONEncoder.veilDiagnostics.encode(report)
            print(String(decoding: data, as: UTF8.self))
            return
        }

        print("Windows install status: \(report.installEvidence.title)")
        print("State: \(report.state.rawValue)")
        print("Profile: \(report.profileName ?? "Not configured")")
        print("Boot ready: \(report.bootReady ? "yes" : "no")")
        print("Windows installed: \(report.windowsInstalled ? "yes" : "no")")
        print("Installer: \(report.installerMediaPath ?? "Not selected")")
        print("Drivers: \(report.driverMediaPath ?? "Not selected")")
        print("Virtual disk: \(report.virtualDiskPath ?? "Not selected")")
        print("Console screenshot: \(report.latestConsoleScreenshotPath ?? "Not captured")")
        print("Display surface: \(report.displaySurface.kind.rawValue)")
        print("Display size: \(report.displaySurface.plannedWidthInPixels)x\(report.displaySurface.plannedHeightInPixels)")
        print("Display scaling: \(report.displaySurface.scalingMode)")
        print("Dynamic resolution: \(report.displaySurface.dynamicResolution)")
        print("Retina scaling: \(report.displaySurface.retinaScaling)")
        if let endpoint = report.displaySurface.endpoint {
            print("Display endpoint: \(endpoint)")
        }
        if let validationCommand = report.displaySurface.validationCommand {
            print("Display validation: \(validationCommand)")
        }
        if let launch = report.latestConsoleLaunch {
            print("Latest QEMU PID: \(launch.pid.map(String.init) ?? "unknown")")
        }
        print("Detail: \(report.installEvidence.detail)")
        print("Next actions:")
        for action in report.nextActions {
            print("  - \(action)")
        }
    }

    private static func printQEMUSmoke(json: Bool, seconds: Int) async throws {
        guard let profile = try await JSONVMProfileStore().load() else {
            throw VMControlError.missingProfileForQEMUPlan
        }

        let boundedSeconds = min(max(seconds, 5), 120)
        let plan = try makeQEMUPlan(for: profile)
        let logDirectory = diagnosticsDirectory()
            .appendingPathComponent("QEMU Smoke", isDirectory: true)
        try FileManager.default.createDirectory(
            at: logDirectory,
            withIntermediateDirectories: true
        )
        let stamp = ISO8601DateFormatter()
            .string(from: Date())
            .replacingOccurrences(of: ":", with: "-")
        let serialLogURL = logDirectory.appendingPathComponent("qemu-smoke-\(stamp).serial.log")
        let processLogURL = logDirectory.appendingPathComponent("qemu-smoke-\(stamp).process.log")
        let consoleScreenshotURL = logDirectory.appendingPathComponent("qemu-smoke-\(stamp).console.png")
        let monitorSocketURL = URL(fileURLWithPath: "/tmp")
            .appendingPathComponent("veil-qemu-smoke-\(UUID().uuidString.prefix(8)).sock")
        let qmpSocketURL = URL(fileURLWithPath: "/tmp")
            .appendingPathComponent("veil-qemu-smoke-\(UUID().uuidString.prefix(8)).qmp.sock")
        let arguments = QEMUWindowsBootSmokePlanner().makeArguments(
            from: plan,
            serialLogPath: serialLogURL.path,
            monitorSocketPath: monitorSocketURL.path,
            qmpSocketPath: qmpSocketURL.path
        )
        try QEMUVMRuntimeBooter.startTPMEmulatorIfNeeded(plan: plan)

        let processOutput = try runBoundedQEMU(
            executablePath: plan.executablePath,
            arguments: arguments,
            seconds: boundedSeconds,
            processLogURL: processLogURL,
            monitorSocketURL: monitorSocketURL,
            consoleScreenshotURL: consoleScreenshotURL
        )
        try? FileManager.default.removeItem(at: monitorSocketURL)
        try? FileManager.default.removeItem(at: qmpSocketURL)
        let serialOutput = (try? String(contentsOf: serialLogURL, encoding: .utf8)) ?? ""
        let report = QEMUWindowsBootSmokeAnalyzer.makeReport(
            durationSeconds: boundedSeconds,
            processOutput: processOutput.output,
            serialOutput: serialOutput,
            didRemainRunningUntilTimeout: processOutput.didRemainRunningUntilTimeout,
            serialLogPath: serialLogURL.path,
            processLogPath: processLogURL.path,
            consoleScreenshotPath: consoleScreenshotURL.path,
            runEvidence: processOutput.bootPromptKeySendCount > 0 ? ["boot-prompt-key-sent"] : []
        )

        if json {
            let data = try JSONEncoder.veilDiagnostics.encode(report)
            print(String(decoding: data, as: UTF8.self))
            return
        }

        print("QEMU/HVF smoke: \(report.outcome.rawValue)")
        print(report.detail)
        print("Evidence: \(report.evidence.joined(separator: ", "))")
        print("Serial log: \(report.serialLogPath)")
        print("Process log: \(report.processLogPath)")
        print("Console screenshot: \(report.consoleScreenshotPath)")
        print("Next actions:")
        for action in report.nextActions {
            print("  - \(action)")
        }
    }

    private static func startQEMU(
        json: Bool,
        waitSeconds: Int,
        displayMode: VMControlArguments.QEMUStartDisplayMode
    ) async throws {
        guard let profile = try await JSONVMProfileStore().load() else {
            throw VMControlError.missingProfileForQEMUPlan
        }
        try rejectDuplicateQEMULaunchIfNeeded(for: profile)

        let plan = try makeQEMUPlan(for: profile)
        let readiness = QEMUWindowsReadinessDoctor().makeReport(
            profile: profile,
            plan: plan
        )
        guard readiness.overallState == .ready else {
            throw VMControlError.qemuNotReady(readiness.nextActions)
        }
        let shouldSendInstallerBootKey = QEMUWindowsInstallerBootPolicy.shouldSendBootKey(
            profile: profile,
            virtualDiskAllocatedBytes: QEMUWindowsInstallerBootPolicy.allocatedFileSize(path: profile.virtualDiskPath)
        )

        let logDirectory = diagnosticsDirectory()
            .appendingPathComponent("QEMU Launch", isDirectory: true)
        try FileManager.default.createDirectory(
            at: logDirectory,
            withIntermediateDirectories: true
        )
        let stamp = ISO8601DateFormatter()
            .string(from: Date())
            .replacingOccurrences(of: ":", with: "-")
        let processLogURL = logDirectory.appendingPathComponent("qemu-launch-\(stamp).log")
        let serialLogURL = logDirectory.appendingPathComponent("qemu-launch-\(stamp).serial.log")
        let consoleScreenshotURL = logDirectory.appendingPathComponent("qemu-console-\(stamp).png")
        let monitorSocketURL = URL(fileURLWithPath: "/tmp")
            .appendingPathComponent("vq-\(UUID().uuidString.prefix(8)).sock")
        let qmpSocketURL = URL(fileURLWithPath: "/tmp")
            .appendingPathComponent("vq-\(UUID().uuidString.prefix(8)).qmp.sock")
        let bootDisplayMode: QEMUWindowsBootDisplayMode = displayMode == .embedded
            ? .vncLoopback
            : .nativeCocoa
        let vncPort = displayMode == .embedded ? QEMUVMRuntimeBooter.allocateLoopbackVNCPort() : nil
        if displayMode == .embedded, vncPort == nil {
            throw VMControlError.qemuDisplayPortUnavailable
        }
        let vncDisplay = vncPort.map { max($0 - 5_900, 0) }
        FileManager.default.createFile(atPath: processLogURL.path, contents: nil)
        let logHandle = try FileHandle(forWritingTo: processLogURL)
        let launchArguments = QEMUWindowsBootLaunchPlanner().makeArguments(
            from: plan,
            serialLogPath: serialLogURL.path,
            monitorSocketPath: monitorSocketURL.path,
            qmpSocketPath: qmpSocketURL.path,
            bootDiskFirst: !shouldSendInstallerBootKey,
            displayMode: bootDisplayMode,
            vncDisplay: vncDisplay
        )

        let process = Process()
        process.executableURL = URL(fileURLWithPath: plan.executablePath)
        process.arguments = launchArguments
        process.standardOutput = logHandle
        process.standardError = logHandle
        try QEMUVMRuntimeBooter.startTPMEmulatorIfNeeded(plan: plan)
        try process.run()
        if bootDisplayMode == .nativeCocoa {
            bringQEMUToFrontIfAllowed()
        }
        driveInitialQEMULaunch(
            process: process,
            waitSeconds: waitSeconds,
            shouldSendInstallerBootKey: shouldSendInstallerBootKey,
            monitorSocketURL: monitorSocketURL,
            consoleScreenshotURL: consoleScreenshotURL
        )

        let record = QEMULaunchRecord(
            provider: plan.provider,
            pid: process.processIdentifier,
            executablePath: plan.executablePath,
            arguments: launchArguments,
            displayMode: bootDisplayMode,
            processLogPath: processLogURL.path,
            monitorSocketPath: monitorSocketURL.path,
            qmpSocketPath: qmpSocketURL.path,
            vncHost: vncPort == nil ? nil : "127.0.0.1",
            vncPort: vncPort,
            consoleScreenshotPath: consoleScreenshotURL.path,
            startedAt: Date()
        )
        try writeQEMULaunchRecord(record, directory: logDirectory, stamp: stamp)

        if json {
            let data = try JSONEncoder.veilDiagnostics.encode(record)
            print(String(decoding: data, as: UTF8.self))
            return
        }

        print("QEMU/HVF Windows VM launched")
        print("PID: \(record.pid.map(String.init) ?? "unknown")")
        print("Executable: \(record.executablePath)")
        print("Process log: \(record.processLogPath)")
        print("Serial log: \(serialLogURL.path)")
        print("Monitor socket: \(record.monitorSocketPath)")
        print("QMP socket: \(record.qmpSocketPath ?? "not attached")")
        print("Display mode: \(record.displayMode?.rawValue ?? "unknown")")
        if let vncHost = record.vncHost, let vncPort = record.vncPort {
            print("VNC display: \(vncHost):\(vncPort)")
        }
        print("Console screenshot: \(record.consoleScreenshotPath ?? "pending")")
    }

    private static func writeQEMULaunchRecord(
        _ record: QEMULaunchRecord,
        directory: URL,
        stamp: String
    ) throws {
        let data = try JSONEncoder.veilDiagnostics.encode(record)
        try data.write(to: directory.appendingPathComponent("qemu-launch-\(stamp).json"), options: .atomic)
        try data.write(to: directory.appendingPathComponent("qemu-launch-latest.json"), options: .atomic)
    }

    private static func smokeQEMUDisplay(json: Bool, waitSeconds: Int) throws {
        let launchRecord = try latestQEMULaunchRecord()
        guard let host = launchRecord.vncHost?.trimmingCharacters(in: .whitespacesAndNewlines),
              !host.isEmpty,
              let port = launchRecord.vncPort else {
            throw VMControlError.missingQEMUDisplayEndpoint
        }

        let boundedWaitSeconds = min(max(waitSeconds, 1), 30)
        let socket = try RFBLoopbackSocket(host: host, port: port, timeoutSeconds: boundedWaitSeconds)
        let client = RFBFrameStreamClient(stream: socket)
        let serverInit = try client.startSharedSession()
        let renderer = try RFBFramebufferRenderer(serverInit: serverInit)
        try client.requestFramebufferUpdate(incremental: false)
        let update = try client.readFramebufferUpdate()
        let frame = try renderer.apply(update)
        socket.close()

        let record = QEMUDisplaySmokeRecord(
            pid: launchRecord.pid,
            endpoint: "\(host):\(port)",
            width: frame.width,
            height: frame.height,
            frameSequence: frame.sequence,
            pixelByteCount: frame.rgbaPixels.count,
            waitedSeconds: boundedWaitSeconds,
            capturedAt: Date()
        )

        if json {
            let data = try JSONEncoder.veilDiagnostics.encode(record)
            print(String(decoding: data, as: UTF8.self))
            return
        }

        print("QEMU embedded display smoke passed")
        print("PID: \(record.pid.map(String.init) ?? "unknown")")
        print("Endpoint: \(record.endpoint)")
        print("Frame: \(record.width)x\(record.height) #\(record.frameSequence)")
        print("RGBA bytes: \(record.pixelByteCount)")
    }

    private static func captureQEMUConsole(json: Bool, outputPath: String?) async throws {
        let directory = diagnosticsDirectory()
            .appendingPathComponent("QEMU Launch", isDirectory: true)
        let latestURL = directory.appendingPathComponent("qemu-launch-latest.json")
        guard FileManager.default.fileExists(atPath: latestURL.path) else {
            throw VMControlError.missingQEMULaunchRecord
        }

        let data = try Data(contentsOf: latestURL)
        var launchRecord = try JSONDecoder.veilDiagnostics.decode(QEMULaunchRecord.self, from: data)
        guard FileManager.default.fileExists(atPath: launchRecord.monitorSocketPath) else {
            throw VMControlError.qemuMonitorUnavailable(launchRecord.monitorSocketPath)
        }

        let screenshotURL: URL
        if let outputPath,
           !outputPath.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            screenshotURL = URL(fileURLWithPath: outputPath)
        } else if let path = launchRecord.consoleScreenshotPath,
                  !path.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            screenshotURL = URL(fileURLWithPath: path)
        } else {
            let stamp = ISO8601DateFormatter()
                .string(from: Date())
                .replacingOccurrences(of: ":", with: "-")
            screenshotURL = directory.appendingPathComponent("qemu-console-\(stamp).png")
        }

        try FileManager.default.createDirectory(
            at: screenshotURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        QEMUVMRuntimeBooter.captureConsoleScreenshot(
            monitorSocketURL: URL(fileURLWithPath: launchRecord.monitorSocketPath),
            imageURL: screenshotURL
        )
        guard FileManager.default.fileExists(atPath: screenshotURL.path) else {
            throw VMControlError.qemuScreenshotCaptureFailed(screenshotURL.path)
        }

        launchRecord.consoleScreenshotPath = screenshotURL.path
        let launchData = try JSONEncoder.veilDiagnostics.encode(launchRecord)
        try launchData.write(to: latestURL, options: .atomic)

        let captureRecord = QEMUConsoleCaptureRecord(
            monitorSocketPath: launchRecord.monitorSocketPath,
            consoleScreenshotPath: screenshotURL.path,
            capturedAt: Date()
        )
        if json {
            let captureData = try JSONEncoder.veilDiagnostics.encode(captureRecord)
            print(String(decoding: captureData, as: UTF8.self))
            return
        }

        print("QEMU console screenshot captured")
        print("Monitor socket: \(captureRecord.monitorSocketPath)")
        print("Console screenshot: \(captureRecord.consoleScreenshotPath)")
    }

    private static func powerDownQEMU(json: Bool, waitSeconds: Int) async throws {
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

    private static func forceStopQEMU(json: Bool, waitSeconds: Int, isAuthorized: Bool) async throws {
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

    private static func sendQEMUOOBEBypass(json: Bool) async throws {
        try await sendQEMUKeySteps(json: json, steps: QEMUOOBEBypassKeySequence.steps)
    }

    private static func sendQEMUGuestAgentInstall(json: Bool) async throws {
        try await sendQEMUKeySteps(json: json, steps: QEMUGuestAgentInstallKeySequence.steps)
    }

    private static func sendQEMUKeys(
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

        let record = QEMUKeySendRecord(
            monitorSocketPath: launchRecord.monitorSocketPath,
            keys: steps.map(\.key),
            results: results,
            sentAt: Date()
        )

        if json {
            let data = try JSONEncoder.veilDiagnostics.encode(record)
            print(String(decoding: data, as: UTF8.self))
            return
        }

        print("QEMU key sequence sent")
        print("Monitor socket: \(record.monitorSocketPath)")
        print("Keys: \(record.keys.joined(separator: ", "))")
    }

    private static func typeQEMUText(json: Bool, text: String) async throws {
        let steps = try QEMUQMPKeyboardCommandBuilder
            .keySequence(forText: text)
            .map { QEMUKeySequenceStep(key: $0, delayAfterSend: 0.035) }
        try await sendQEMUKeySteps(json: json, steps: steps)
    }

    private static func clickQEMU(json: Bool, x: Int, y: Int) async throws {
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

    private static func latestQEMULaunchRecord() throws -> QEMULaunchRecord {
        let latestURL = diagnosticsDirectory()
            .appendingPathComponent("QEMU Launch", isDirectory: true)
            .appendingPathComponent("qemu-launch-latest.json")
        guard FileManager.default.fileExists(atPath: latestURL.path) else {
            throw VMControlError.missingQEMULaunchRecord
        }

        let data = try Data(contentsOf: latestURL)
        return try JSONDecoder.veilDiagnostics.decode(QEMULaunchRecord.self, from: data)
    }

    private static func rejectDuplicateQEMULaunchIfNeeded(for profile: VMProfile) throws {
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

    private static func isProcessRunning(pid: Int32) -> Bool {
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

    private static func driveInitialQEMULaunch(
        process: Process,
        waitSeconds: Int,
        shouldSendInstallerBootKey: Bool,
        monitorSocketURL: URL,
        consoleScreenshotURL: URL
    ) {
        let boundedSeconds = min(max(waitSeconds, 0), 120)
        let startDate = Date()
        let deadline = startDate.addingTimeInterval(TimeInterval(boundedSeconds))
        var bootPromptAutomation = QEMUWindowsBootPromptAutomation()

        while process.isRunning, Date() < deadline {
            Thread.sleep(forTimeInterval: 0.25)
            if shouldSendInstallerBootKey {
                _ = bootPromptAutomation.tick(
                    elapsedSeconds: Int(Date().timeIntervalSince(startDate)),
                    monitorSocketURL: monitorSocketURL,
                    sendBootKey: QEMUVMRuntimeBooter.sendWindowsInstallerBootKey
                )
            }
        }

        if process.isRunning {
            QEMUVMRuntimeBooter.captureConsoleScreenshot(
                monitorSocketURL: monitorSocketURL,
                imageURL: consoleScreenshotURL
            )
        }
    }

    private static func bringQEMUToFrontIfAllowed() {
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

    private static func runBoundedQEMU(
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

        let data = outputPipe.fileHandleForReading.readDataToEndOfFile()
        try data.write(to: processLogURL, options: [.atomic])
        return (
            String(data: data, encoding: .utf8) ?? "",
            didRemainRunningUntilTimeout,
            bootPromptKeySendCount
        )
    }

    private static func makeQEMUPlan(for profile: VMProfile) throws -> QEMUWindowsBootPlan {
        try LocalQEMUWindowsBootPlanFactory.makePlan(
            for: profile,
            architecture: hostArchitecture(),
            minimumOSSupported: ProcessInfo.processInfo.isOperatingSystemAtLeast(
                OperatingSystemVersion(majorVersion: 15, minorVersion: 0, patchVersion: 0)
            )
        )
    }

    private static func shellQuoted(_ value: String) -> String {
        guard value.rangeOfCharacter(from: .whitespacesAndNewlines) != nil else {
            return value
        }

        return "'\(value.replacingOccurrences(of: "'", with: "'\\''"))'"
    }

    private static func hostArchitecture() -> String {
        #if arch(arm64)
        return "arm64"
        #elseif arch(x86_64)
        return "x86_64"
        #else
        return "unknown"
        #endif
    }

    private static func diagnosticsDirectory() -> URL {
        QEMUVMRuntimeBooter.defaultDiagnosticsDirectory()
    }

}
