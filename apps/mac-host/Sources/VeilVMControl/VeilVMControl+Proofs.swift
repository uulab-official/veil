import Foundation
import Darwin
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers
import Vision
import VeilHostCore

extension VeilVMControl {
    static func proveAppWindow(json: Bool, appId: String, waitSeconds: Int, outputPath: String?) async throws {
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
        print("First frame latency: \(report.firstFrameLatency.elapsedMilliseconds)ms (budget \(report.firstFrameLatency.freshFrameBudgetMilliseconds)ms, action \(report.firstFrameLatency.recommendedAction))")
        if let savedProofPath = report.savedProofPath {
            print("Saved proof: \(savedProofPath)")
        }
        print("Next actions:")
        for action in report.nextActions {
            print("  - \(action)")
        }
    }

    static func proveCoherence(json: Bool, appId: String, waitSeconds: Int, outputPath: String?) async throws {
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
        print("Initial frame latency: \(report.initialFrameLatency.elapsedMilliseconds)ms (budget \(report.initialFrameLatency.freshFrameBudgetMilliseconds)ms, action \(report.initialFrameLatency.recommendedAction))")
        print("Post-input frame latency: \(report.postInputFrameLatency.elapsedMilliseconds)ms (budget \(report.postInputFrameLatency.freshFrameBudgetMilliseconds)ms, action \(report.postInputFrameLatency.recommendedAction))")
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

    static func proveMVP(json: Bool, appId: String, waitSeconds: Int, outputPath: String?, requireProved: Bool) async throws {
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
            print("Frame latency: initial \(coherence.initialFrameLatency.elapsedMilliseconds)ms, post-input \(coherence.postInputFrameLatency.elapsedMilliseconds)ms")
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

    static func proveNotificationBridge(
        json: Bool,
        waitSeconds: Int,
        outputPath: String?,
        requireProved: Bool
    ) async throws {
        let endpoint = ProcessInfo.processInfo.environment["VEIL_AGENT_URL"] ?? "ws://127.0.0.1:18444"
        let url = URL(string: endpoint) ?? URL(string: "ws://127.0.0.1:18444")!
        let boundedWaitSeconds = min(max(waitSeconds, 0), 300)
        let transport = URLSessionWebSocketTransport(url: url)
        let client = VeilHostClient(transport: transport)
        var report = await client.proveWindowsNotificationBridge(
            endpoint: endpoint,
            eventSource: transport,
            waitSeconds: boundedWaitSeconds,
            notificationTimeoutNanoseconds: UInt64(max(boundedWaitSeconds, 1)) * 1_000_000_000
        )
        if let outputURL = proofOutputURL(from: outputPath) {
            report.savedProofPath = outputURL.path
            try writeProof(report, to: outputURL)
        }

        if json {
            let data = try JSONEncoder.veilDiagnostics.encode(report)
            print(String(decoding: data, as: UTF8.self))
            if requireProved, report.status != .proved {
                throw VMControlError.notificationProofNotProved(report.nextActions)
            }
            return
        }

        print("Windows notification proof: \(report.status.rawValue)")
        print("Endpoint: \(report.endpoint)")
        print("Agent wait: \(report.wait.status.rawValue) after \(report.wait.attempts) attempt(s)")
        print("Waited for notification: \(report.waitedForNotificationSeconds)s")
        if let notification = report.notification {
            print("Notification: \(notification.title)")
            print("Notification id: \(notification.notificationId)")
            if let appName = notification.appName {
                print("App: \(appName)")
            }
            if let sourceAumid = notification.sourceAumid {
                print("Source AUMID: \(sourceAumid)")
            }
        }
        if let savedProofPath = report.savedProofPath {
            print("Saved proof: \(savedProofPath)")
        }
        print("Next actions:")
        for action in report.nextActions {
            print("  - \(action)")
        }
        if requireProved, report.status != .proved {
            throw VMControlError.notificationProofNotProved(report.nextActions)
        }
    }

    static func proveMultipleApps(
        json: Bool,
        appIds: [String],
        waitSeconds: Int,
        outputDirectoryPath: String?,
        requireComplete: Bool,
        shouldPrint: Bool = true
    ) async throws -> WindowsMultiAppProofReport {
        let endpoint = ProcessInfo.processInfo.environment["VEIL_AGENT_URL"] ?? "ws://127.0.0.1:18444"
        let url = URL(string: endpoint) ?? URL(string: "ws://127.0.0.1:18444")!
        let boundedWaitSeconds = min(max(waitSeconds, 1), 60)
        let targetAppIds = orderedUniqueAppIds(appIds)
        guard !targetAppIds.isEmpty else {
            throw VMControlError.missingMultiAppProofAppIds
        }

        let diagnosticsDirectory = outputDirectoryPath.map(URL.init(fileURLWithPath:))
            ?? QEMUVMRuntimeBooter.defaultDiagnosticsDirectory()
        let coherenceProofDirectory = diagnosticsDirectory
            .appendingPathComponent("Coherence Proof", isDirectory: true)
        let recommendedProofDirectory = diagnosticsDirectory
            .appendingPathComponent("Recommended Proof", isDirectory: true)
        let stamp = proofFileTimestamp()
        let aggregateReportURL = recommendedProofDirectory
            .appendingPathComponent("multi-app-proof-\(stamp).json")
        var results: [WindowsMultiAppProofResult] = []

        for appId in targetAppIds {
            let outputURL = coherenceProofDirectory
                .appendingPathComponent("\(proofFileComponent(appId))-coherence-proof-\(stamp).json")
            let transport = URLSessionWebSocketTransport(url: url)
            let client = VeilHostClient(transport: transport)

            do {
                var proof = try await client.proveCoherenceAppWindow(
                    appId: appId,
                    endpoint: endpoint,
                    eventSource: transport,
                    timeoutNanoseconds: UInt64(boundedWaitSeconds) * 1_000_000_000
                )
                proof.savedProofPath = outputURL.path
                try writeProof(proof, to: outputURL)

                let latency = multiAppLatencySummary(for: proof)
                results.append(
                    WindowsMultiAppProofResult(
                        appId: appId,
                        status: "proved",
                        proofKind: "coherence",
                        proofPath: outputURL.path,
                        latencyHealth: latency.health,
                        slowestLatencyMeasurement: latency.slowestMeasurement,
                        slowestLatencyMilliseconds: latency.slowestElapsedMilliseconds,
                        latencyBudgetMilliseconds: latency.freshFrameBudgetMilliseconds,
                        staleTimeoutMilliseconds: latency.staleFrameTimeoutMilliseconds,
                        latencyRecommendedAction: latency.recommendedAction,
                        windowId: proof.window.windowId,
                        windowTitle: proof.window.title,
                        errorMessage: nil
                    )
                )
            } catch {
                results.append(
                    WindowsMultiAppProofResult(
                        appId: appId,
                        status: "failed",
                        proofKind: "coherence",
                        proofPath: nil,
                        latencyHealth: nil,
                        slowestLatencyMeasurement: nil,
                        slowestLatencyMilliseconds: nil,
                        latencyBudgetMilliseconds: nil,
                        staleTimeoutMilliseconds: nil,
                        latencyRecommendedAction: nil,
                        windowId: nil,
                        windowTitle: nil,
                        errorMessage: errorMessage(for: error)
                    )
                )
            }
        }

        let provedAppCount = results.filter { $0.status == "proved" }.count
        let failedAppCount = results.count - provedAppCount
        let coverageHealth: String
        if provedAppCount == targetAppIds.count {
            coverageHealth = "complete"
        } else if provedAppCount > 0 {
            coverageHealth = "partial"
        } else {
            coverageHealth = "missing"
        }

        let nextActions = multiAppProofNextActions(
            coverageHealth: coverageHealth,
            aggregateReportPath: aggregateReportURL.path,
            failedResults: results.filter { $0.status == "failed" }
        )
        let report = WindowsMultiAppProofReport(
            endpoint: endpoint,
            provedAt: Date(),
            proofDirectory: coherenceProofDirectory.path,
            aggregateReportPath: aggregateReportURL.path,
            appIds: targetAppIds,
            targetAppIds: WindowsAppRuntimeProofCoverageDefaults.targetAppIds,
            waitSeconds: boundedWaitSeconds,
            proofKind: "coherence",
            provedAppCount: provedAppCount,
            failedAppCount: failedAppCount,
            coverageHealth: coverageHealth,
            results: results,
            nextActions: nextActions
        )
        try writeProof(report, to: aggregateReportURL)

        if json && shouldPrint {
            let data = try JSONEncoder.veilDiagnostics.encode(report)
            print(String(decoding: data, as: UTF8.self))
            if requireComplete, coverageHealth != "complete" {
                throw VMControlError.multiAppProofIncomplete(nextActions)
            }
            return report
        }

        if shouldPrint {
            print("Windows multi-app proof: \(coverageHealth) (\(provedAppCount)/\(targetAppIds.count))")
            print("Endpoint: \(endpoint)")
            print("Proof directory: \(coherenceProofDirectory.path)")
            print("Aggregate report: \(aggregateReportURL.path)")
            for result in results {
                if result.status == "proved" {
                    let latency = result.slowestLatencyMilliseconds.map(String.init) ?? "unknown"
                    let health = result.latencyHealth ?? "unknown"
                    print("  - \(result.appId): proved, latency \(health) \(latency)ms, proof \(result.proofPath ?? "not saved")")
                } else {
                    print("  - \(result.appId): failed, \(result.errorMessage ?? "unknown error")")
                }
            }
            print("Next actions:")
            for action in nextActions {
                print("  - \(action)")
            }
        }
        if requireComplete, coverageHealth != "complete" {
            throw VMControlError.multiAppProofIncomplete(nextActions)
        }
        return report
    }

    private static func proofOutputURL(from outputPath: String?) -> URL? {
        guard let outputPath,
              !outputPath.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return nil
        }

        return URL(fileURLWithPath: outputPath)
    }

    private static func orderedUniqueAppIds(_ appIds: [String]) -> [String] {
        var seen = Set<String>()
        var result: [String] = []
        for appId in appIds {
            let trimmed = appId.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty, !seen.contains(trimmed) else {
                continue
            }
            seen.insert(trimmed)
            result.append(trimmed)
        }
        return result
    }

    private static func proofFileComponent(_ appId: String) -> String {
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-_"))
        return String(appId.unicodeScalars.map { scalar in
            allowed.contains(scalar) ? Character(scalar) : "-"
        })
    }

    private static func proofFileTimestamp() -> String {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "yyyyMMdd-HHmmss"
        return formatter.string(from: Date())
    }

    private static func multiAppLatencySummary(
        for proof: WindowsAppCoherenceProofReport
    ) -> WindowsMultiAppProofLatencySummary {
        let slowest = [proof.initialFrameLatency, proof.postInputFrameLatency].max {
            $0.elapsedMilliseconds < $1.elapsedMilliseconds
        } ?? proof.postInputFrameLatency
        let health: String
        if slowest.elapsedMilliseconds <= slowest.freshFrameBudgetMilliseconds {
            health = "healthy"
        } else if slowest.elapsedMilliseconds <= slowest.staleFrameTimeoutMilliseconds {
            health = "delayed"
        } else {
            health = "stale"
        }

        return WindowsMultiAppProofLatencySummary(
            health: health,
            slowestMeasurement: slowest.measurement,
            slowestElapsedMilliseconds: slowest.elapsedMilliseconds,
            freshFrameBudgetMilliseconds: slowest.freshFrameBudgetMilliseconds,
            staleFrameTimeoutMilliseconds: slowest.staleFrameTimeoutMilliseconds,
            recommendedAction: slowest.recommendedAction
        )
    }

    private static func multiAppProofNextActions(
        coverageHealth: String,
        aggregateReportPath: String,
        failedResults: [WindowsMultiAppProofResult]
    ) -> [String] {
        var actions = [
            "Run `veil-vmctl app-runtime-status --json` to confirm proofArtifacts.multiAppProofCoverageHealth.",
            "Attach `\(aggregateReportPath)` with the saved per-app proof artifacts when filing app-runtime evidence."
        ]
        if coverageHealth != "complete" {
            actions.append("Run `veil-vmctl guest-agent-wait --json --wait-seconds 30` and retry `veil-vmctl multi-app-proof --json --require-complete` after the Windows app connection is live.")
        }
        for result in failedResults {
            actions.append("Retry `veil-vmctl coherence-proof --json --app-id \(result.appId)` to isolate the \(result.appId) failure.")
        }
        return actions
    }

    private static func errorMessage(for error: Error) -> String {
        if let localizedError = error as? LocalizedError,
           let description = localizedError.errorDescription {
            return description
        }
        return String(describing: error)
    }

    private static func writeProof<T: Encodable>(_ report: T, to outputURL: URL) throws {
        let directory = outputURL.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let data = try JSONEncoder.veilDiagnostics.encode(report)
        try data.write(to: outputURL, options: .atomic)
    }

    static func printPrinterBridgePlan(
        json: Bool,
        sharedPrinterName: String?,
        windowsPrinterName: String?
    ) throws {
        let plan = makePrinterBridgePlan(
            sharedPrinterName: sharedPrinterName,
            windowsPrinterName: windowsPrinterName
        )

        if json {
            let data = try JSONEncoder.veilDiagnostics.encode(plan)
            print(String(decoding: data, as: UTF8.self))
            return
        }

        print("Windows printer bridge: \(plan.mode)")
        print("IPP endpoint: \(plan.ippEndpoint)")
        print("Windows printer: \(plan.windowsPrinterName)")
        print("macOS setup: \(plan.macOSSharingHint)")
        print("Windows command: \(plan.windowsAddPrinterCommand)")
        print("Verify: \(plan.windowsVerifyPrinterCommand)")
        print("Test page: \(plan.manualTestPageInstruction)")
        print("Next actions:")
        for action in plan.nextActions {
            print("  - \(action)")
        }
    }

    static func printPrinterBridgeProof(
        json: Bool,
        evidencePath: String,
        sharedPrinterName: String?,
        windowsPrinterName: String?,
        outputPath: String?
    ) throws {
        var report = try makePrinterBridgeProof(
            evidencePath: evidencePath,
            sharedPrinterName: sharedPrinterName,
            windowsPrinterName: windowsPrinterName
        )
        let outputURL = outputPath.map { URL(fileURLWithPath: $0) }
            ?? diagnosticsDirectory()
                .appendingPathComponent("Printer Proof", isDirectory: true)
                .appendingPathComponent("printer-bridge-proof.json")
        report.savedProofPath = outputURL.path
        try writeProof(report, to: outputURL)

        if json {
            let data = try JSONEncoder.veilDiagnostics.encode(report)
            print(String(decoding: data, as: UTF8.self))
            return
        }

        print("Windows printer bridge proof: \(report.status)")
        print("Evidence: \(report.evidenceFileName) (\(report.evidenceByteCount) bytes)")
        print("IPP endpoint: \(report.plan.ippEndpoint)")
        print("Saved proof: \(outputURL.path)")
        print("Next actions:")
        for action in report.nextActions {
            print("  - \(action)")
        }
    }

    private static func makePrinterBridgeProof(
        evidencePath: String,
        sharedPrinterName: String?,
        windowsPrinterName: String?
    ) throws -> WindowsPrinterBridgeProofReport {
        let evidenceURL = URL(fileURLWithPath: evidencePath)
        guard FileManager.default.fileExists(atPath: evidenceURL.path) else {
            throw VMControlError.printerBridgeEvidenceNotFound(evidencePath)
        }

        let attributes = try FileManager.default.attributesOfItem(atPath: evidenceURL.path)
        let byteCount = (attributes[.size] as? NSNumber)?.intValue ?? 0
        let modifiedAt = attributes[.modificationDate] as? Date
        let plan = makePrinterBridgePlan(
            sharedPrinterName: sharedPrinterName,
            windowsPrinterName: windowsPrinterName
        )

        return WindowsPrinterBridgeProofReport(
            status: "proved",
            provedAt: Date(),
            evidencePath: evidenceURL.path,
            evidenceFileName: evidenceURL.lastPathComponent,
            evidenceByteCount: byteCount,
            evidenceModifiedAt: modifiedAt,
            plan: plan,
            nextActions: [
                "Run `veil-vmctl app-runtime-status --json` to confirm proofArtifacts.latestPrinterBridgeProofPath.",
                "Keep the original evidence file available locally; Veil records metadata and does not copy printer output into diagnostics.",
                "Use this proof before graduating printer bridge beyond manual-ipp-experiment."
            ]
        )
    }

    private static func makePrinterBridgePlan(
        sharedPrinterName: String?,
        windowsPrinterName: String?
    ) -> WindowsPrinterBridgePlan {
        let sharedPrinter = normalizedPrinterBridgeName(
            sharedPrinterName,
            fallback: "<shared-printer-name>"
        )
        let windowsPrinter = normalizedPrinterBridgeName(
            windowsPrinterName,
            fallback: "Veil Mac Printer"
        )
        let endpoint = printerBridgeEndpoint(sharedPrinterName: sharedPrinter)
        let addCommand = "Add-Printer -Name \(powershellSingleQuoted(windowsPrinter)) -IppURL \(powershellSingleQuoted(endpoint))"
        let verifyCommand = "Get-Printer -Name \(powershellSingleQuoted(windowsPrinter)) | Format-List Name,Type,PrinterStatus"

        return WindowsPrinterBridgePlan(
            generatedAt: Date(),
            mode: WindowsAppRuntimePrinterBridgeDefaults.recommendedAction,
            hostAddress: "10.0.2.2",
            ippPort: 631,
            sharedPrinterName: sharedPrinter,
            windowsPrinterName: windowsPrinter,
            ippEndpoint: endpoint,
            macOSSharingHint: "Enable macOS Printer Sharing, then share the target printer as \(sharedPrinter).",
            windowsAddPrinterCommand: addCommand,
            windowsVerifyPrinterCommand: verifyCommand,
            manualTestPageInstruction: "From Windows Settings, open Printers & scanners, select \(windowsPrinter), and print a test page.",
            setupSteps: [
                "On macOS, enable Printer Sharing and share the printer name shown in sharedPrinterName.",
                "Start the Veil Windows VM on the default QEMU user-mode network.",
                "In an elevated Windows PowerShell session, run windowsAddPrinterCommand.",
                "Open Windows Printers & scanners and confirm the new printer appears."
            ],
            verificationSteps: [
                "Run windowsVerifyPrinterCommand and confirm the printer is present.",
                "Print a Windows test page and save screenshot or paper/PDF evidence before claiming printer bridge support.",
                "Run `veil-vmctl app-runtime-status --json` and confirm dailyUseReadiness.printerBridgeRecommendedAction remains manual-ipp-experiment until live proof exists."
            ],
            limitations: [
                "This is a manual IPP experiment, not automatic Parallels-style printer provisioning yet.",
                "It depends on macOS Printer Sharing, the Windows IPP print path, and the selected printer driver.",
                "Veil must not claim printer bridge support until a real Windows test page proof is saved."
            ],
            nextActions: [
                "Run `veil-vmctl printer-bridge-plan --json --shared-printer <shared-printer-name>` with the actual macOS shared printer name.",
                "Run the generated Add-Printer command inside Windows after the guest is installed and networked.",
                "Save the successful Windows test-page evidence, then promote this from manual experiment to app-guided printer setup."
            ]
        )
    }

    private static func normalizedPrinterBridgeName(_ value: String?, fallback: String) -> String {
        let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return trimmed.isEmpty ? fallback : trimmed
    }

    private static func printerBridgeEndpoint(sharedPrinterName: String) -> String {
        if sharedPrinterName == "<shared-printer-name>" {
            return WindowsAppRuntimePrinterBridgeDefaults.endpointTemplate
        }

        let allowed = CharacterSet(charactersIn: "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._~")
        let encoded = sharedPrinterName.addingPercentEncoding(withAllowedCharacters: allowed) ?? sharedPrinterName
        return "http://10.0.2.2:631/printers/\(encoded)"
    }

    private static func powershellSingleQuoted(_ value: String) -> String {
        "'\(value.replacingOccurrences(of: "'", with: "''"))'"
    }
}
