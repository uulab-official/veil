import Foundation
import Darwin
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers
import Vision
import VeilHostCore

@main
struct VeilVMControl {
    static func main() async {
        do {
            if let guestCommand = try GuestCommand.parse(Array(CommandLine.arguments.dropFirst())) {
                try runGuestCommand(guestCommand)
                return
            }
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
        case .appRuntimeStatus(let json, let demo, let hostBackingScale):
            try await printAppRuntimeStatus(json: json, demo: demo, hostBackingScale: hostBackingScale)
        case .appRuntimeReview(let json, let demo, let evidenceDirectoryPath):
            try await printAppRuntimeReview(json: json, demo: demo, evidenceDirectoryPath: evidenceDirectoryPath)
        case .appRuntimeReviewInit(let json, let demo, let evidenceDirectoryPath):
            try await initAppRuntimeReview(json: json, demo: demo, evidenceDirectoryPath: evidenceDirectoryPath)
        case .appRuntimeReviewVerify(let json, let demo, let evidenceDirectoryPath):
            try await verifyAppRuntimeReview(json: json, demo: demo, evidenceDirectoryPath: evidenceDirectoryPath)
        case .appRuntimeAction(let json, let demo, let action, let appId, let windowId, let text, let x, let y, let waitSeconds):
            try await runAppRuntimeAction(json: json, demo: demo, action: action, appId: appId, windowId: windowId, text: text, x: x, y: y, waitSeconds: waitSeconds)
        case .appWindowProof(let json, let appId, let waitSeconds, let outputPath):
            try await proveAppWindow(json: json, appId: appId, waitSeconds: waitSeconds, outputPath: outputPath)
        case .coherenceProof(let json, let appId, let waitSeconds, let outputPath):
            try await proveCoherence(json: json, appId: appId, waitSeconds: waitSeconds, outputPath: outputPath)
        case .mvpProof(let json, let appId, let waitSeconds, let outputPath, let requireProved):
            try await proveMVP(json: json, appId: appId, waitSeconds: waitSeconds, outputPath: outputPath, requireProved: requireProved)
        case .multiAppProof(let json, let appIds, let waitSeconds, let outputDirectoryPath, let requireComplete):
            _ = try await proveMultipleApps(json: json, appIds: appIds, waitSeconds: waitSeconds, outputDirectoryPath: outputDirectoryPath, requireComplete: requireComplete)
        case .notificationProof(let json, let waitSeconds, let outputPath, let requireProved):
            try await proveNotificationBridge(json: json, waitSeconds: waitSeconds, outputPath: outputPath, requireProved: requireProved)
        case .printerBridgePlan(let json, let sharedPrinterName, let windowsPrinterName):
            try printPrinterBridgePlan(json: json, sharedPrinterName: sharedPrinterName, windowsPrinterName: windowsPrinterName)
        case .printerBridgeProof(let json, let evidencePath, let sharedPrinterName, let windowsPrinterName, let outputPath):
            try printPrinterBridgeProof(json: json, evidencePath: evidencePath, sharedPrinterName: sharedPrinterName, windowsPrinterName: windowsPrinterName, outputPath: outputPath)
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
            try await smokeQEMUDisplay(json: json, waitSeconds: waitSeconds)
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
        case .qemuInstallAgent(let json, let waitSeconds):
            try await sendQEMUGuestAgentInstall(json: json, waitSeconds: waitSeconds)
        case .qemuUpdateTools(let json, let waitSeconds):
            try await sendQEMUGuestToolsUpdate(json: json, waitSeconds: waitSeconds)
        case .qemuPrepareSparsePackage(let json, let waitSeconds):
            try await sendQEMUSparsePackagePreparation(json: json, waitSeconds: waitSeconds)
        case .vmSuspend(let json):
            try await suspendVMSession(json: json)
        case .vmResume(let json):
            try await resumeVMSession(json: json)
        case .vmSessionStatus(let json):
            try await printVMSessionStatus(json: json)
        case .vmSnapshotList(let json):
            try await runVMSnapshotAction(.list, json: json, name: nil)
        case .vmSnapshotCreate(let json, let name):
            try await runVMSnapshotAction(.create, json: json, name: name)
        case .vmSnapshotRestore(let json, let name):
            try await runVMSnapshotAction(.restore, json: json, name: name)
        case .vmSnapshotDelete(let json, let name):
            try await runVMSnapshotAction(.delete, json: json, name: name)
        case .framePipelineReport(let json, let seconds, let outputPath):
            try await measureFramePipeline(json: json, seconds: seconds, outputPath: outputPath)
        case .sharedFolderStatus(let json, let prepare, let requireReady):
            try await printSharedFolderStatus(json: json, prepare: prepare, requireReady: requireReady)
        case .devicePassthroughStatus(let json, let requireAvailable):
            try await printDevicePassthroughStatus(json: json, requireAvailable: requireAvailable)
        case .exportDiagnostics(let json, let outputPath):
            try await printExportDiagnostics(json: json, outputPath: outputPath)
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

}
