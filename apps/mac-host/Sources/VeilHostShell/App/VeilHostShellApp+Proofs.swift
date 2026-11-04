import AppKit
import SwiftUI
import VeilHostCore

extension VeilHostShellApp {
    func runRecommendedProof() {
        Task { @MainActor in
            activateMainWindow()
            let proofPlan = model.runtimeStatusReport().proofPlan
            guard let proofKind = proofPlan.recommendedProofKind,
                  proofPlan.recommendedProofCommand != nil,
                  let appId = proofPlan.selectedAppId else {
                displayMessage = proofPlan.reason
                return
            }

            if model.apps.isEmpty {
                await model.load()
            }

            displayMessage = "Running \(appCheckDisplayName(for: proofKind)) app check for \(proofAppName(appId: appId))."

            do {
                let url = try await writeRecommendedProof(
                    proofKind: proofKind,
                    appId: appId,
                    reviewEvidenceFolder: latestReviewEvidenceFolder
                )
                displayMessage = "\(appCheckDisplayName(for: proofKind)) app check saved: \(url.path)"
                await model.load()
            } catch {
                displayMessage = "\(appCheckDisplayName(for: proofKind)) app check could not complete: \(userMessage(for: error))"
            }
        }
    }

    func runMultiAppProof() {
        Task { @MainActor in
            activateMainWindow()
            let proofPlan = model.runtimeStatusReport().proofPlan
            guard proofPlan.recommendedMultiAppProofCommand != nil else {
                displayMessage = "Daily Use app check needs Notepad, Calculator, and Paint to be launchable first."
                return
            }

            if model.apps.isEmpty {
                await model.load()
            }

            displayMessage = "Checking Daily Use apps: Notepad, Calculator, and Paint."

            do {
                let url = try await writeMultiAppProof()
                displayMessage = "Daily Use app check saved: \(url.path)"
                await model.load()
            } catch {
                displayMessage = "Daily Use app check could not complete: \(userMessage(for: error))"
            }
        }
    }

    func runNotificationProof() {
        Task { @MainActor in
            activateMainWindow()
            let report = model.runtimeStatusReport()
            guard report.notificationBridge.canReceiveNotifications,
                  report.notificationBridge.recommendedAction == "run-notification-proof" else {
                displayMessage = report.notificationBridge.reason
                return
            }

            displayMessage = "Waiting for a Windows notification to prove the Mac notification bridge."

            do {
                let url = try await writeNotificationProof()
                displayMessage = "Windows notification check saved: \(url.path)"
                await model.load()
            } catch {
                displayMessage = "Windows notification check could not complete: \(userMessage(for: error))"
            }
        }
    }

    private func writeRecommendedProof(
        proofKind: String,
        appId: String,
        reviewEvidenceFolder: ReviewEvidenceFolder? = nil
    ) async throws -> URL {
        let transport = URLSessionWebSocketTransport(url: URL(string: agentURLString)!)
        let client = VeilHostClient(transport: transport)
        let directory = QEMUVMRuntimeBooter.defaultDiagnosticsDirectory()
            .appendingPathComponent("Recommended Proof", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)

        let stamp = Self.diagnosticTimestamp()
        switch proofKind {
        case "app-window":
            var report = try await client.proveAppWindow(
                appId: appId,
                endpoint: agentURLString,
                eventSource: transport
            )
            let outputURL = directory.appendingPathComponent("app-window-proof-\(stamp).json")
            report.savedProofPath = outputURL.path
            try writeProof(report, to: outputURL)
            return outputURL
        case "coherence":
            var report = try await client.proveCoherenceAppWindow(
                appId: appId,
                endpoint: agentURLString,
                eventSource: transport
            )
            let outputURL = directory.appendingPathComponent("coherence-proof-\(stamp).json")
            report.savedProofPath = outputURL.path
            try writeProof(report, to: outputURL)
            return outputURL
        case "mvp":
            var report = try await client.proveMVPAppRuntime(
                appId: appId,
                endpoint: agentURLString,
                eventSource: transport,
                waitSeconds: 30,
                proofTimeoutNanoseconds: 30_000_000_000
            )
            let outputURL = reviewEvidenceFolder?.appCheckProof
                ?? directory.appendingPathComponent("mvp-proof-\(stamp).json")
            report.savedProofPath = outputURL.path
            try writeProof(report, to: outputURL)
            return outputURL
        default:
            throw RecommendedProofError.unsupportedKind(proofKind)
        }
    }

    private func writeNotificationProof() async throws -> URL {
        let transport = URLSessionWebSocketTransport(url: URL(string: agentURLString)!)
        let client = VeilHostClient(transport: transport)
        let directory = QEMUVMRuntimeBooter.defaultDiagnosticsDirectory()
            .appendingPathComponent("Notification Proof", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)

        let outputURL = directory.appendingPathComponent("notification-proof-\(Self.diagnosticTimestamp()).json")
        var report = await client.proveWindowsNotificationBridge(
            endpoint: agentURLString,
            eventSource: transport,
            waitSeconds: 30,
            notificationTimeoutNanoseconds: 30_000_000_000
        )
        report.savedProofPath = outputURL.path
        try writeProof(report, to: outputURL)
        return outputURL
    }

    private func writeMultiAppProof() async throws -> URL {
        let appIds = WindowsAppRuntimeProofCoverageDefaults.targetAppIds
        let endpoint = agentURLString
        let diagnosticsDirectory = QEMUVMRuntimeBooter.defaultDiagnosticsDirectory()
        let coherenceProofDirectory = diagnosticsDirectory
            .appendingPathComponent("Coherence Proof", isDirectory: true)
        let recommendedProofDirectory = diagnosticsDirectory
            .appendingPathComponent("Recommended Proof", isDirectory: true)
        try FileManager.default.createDirectory(at: coherenceProofDirectory, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: recommendedProofDirectory, withIntermediateDirectories: true)

        let stamp = Self.diagnosticTimestamp()
        let aggregateURL = recommendedProofDirectory
            .appendingPathComponent("multi-app-proof-\(stamp).json")
        var results: [ShellMultiAppProofResult] = []

        for appId in appIds {
            let proofURL = coherenceProofDirectory
                .appendingPathComponent("\(Self.proofFileComponent(appId))-coherence-proof-\(stamp).json")
            let transport = URLSessionWebSocketTransport(url: URL(string: endpoint)!)
            let client = VeilHostClient(transport: transport)

            do {
                var proof = try await client.proveCoherenceAppWindow(
                    appId: appId,
                    endpoint: endpoint,
                    eventSource: transport,
                    timeoutNanoseconds: 10_000_000_000
                )
                proof.savedProofPath = proofURL.path
                try writeProof(proof, to: proofURL)

                let latency = Self.multiAppLatencySummary(for: proof)
                results.append(
                    ShellMultiAppProofResult(
                        appId: appId,
                        status: "proved",
                        proofKind: "coherence",
                        proofPath: proofURL.path,
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
                    ShellMultiAppProofResult(
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
                        errorMessage: userMessage(for: error)
                    )
                )
            }
        }

        let provedAppCount = results.filter { $0.status == "proved" }.count
        let failedAppCount = results.count - provedAppCount
        let coverageHealth = provedAppCount == appIds.count
            ? "complete"
            : (provedAppCount > 0 ? "partial" : "missing")
        let report = ShellMultiAppProofReport(
            endpoint: endpoint,
            provedAt: Date(),
            proofDirectory: coherenceProofDirectory.path,
            aggregateReportPath: aggregateURL.path,
            appIds: appIds,
            targetAppIds: appIds,
            waitSeconds: 10,
            proofKind: "coherence",
            provedAppCount: provedAppCount,
            failedAppCount: failedAppCount,
            coverageHealth: coverageHealth,
            results: results,
            nextActions: Self.multiAppProofNextActions(
                coverageHealth: coverageHealth,
                aggregateReportPath: aggregateURL.path,
                failedResults: results.filter { $0.status == "failed" }
            )
        )
        try writeProof(report, to: aggregateURL)
        return aggregateURL
    }

    private func writeProof<T: Encodable>(_ report: T, to outputURL: URL) throws {
        let data = try JSONEncoder.veilDiagnostics.encode(report)
        try data.write(to: outputURL, options: .atomic)
    }

    func prepareReviewEvidenceFolder() {
        Task { @MainActor in
            activateMainWindow()
            do {
                let folder = try ReviewEvidenceFolderStore.prepare()
                latestReviewEvidenceFolder = folder
                ReviewEvidenceFolderStore.rememberLatest(folder)
                NSWorkspace.shared.open(folder.directory)
                displayMessage = "Review Evidence folder ready: \(folder.directory.path). App checks will save \(folder.appCheckProof.lastPathComponent) there."
            } catch {
                displayMessage = "Review Evidence folder could not be prepared: \(userMessage(for: error))"
            }
        }
    }

    private func appCheckDisplayName(for proofKind: String) -> String {
        switch proofKind {
        case "app-window":
            "Window"
        case "coherence":
            "Input"
        case "mvp":
            "Full"
        default:
            "Recommended"
        }
    }

    private func proofAppName(appId: String) -> String {
        model.apps.first { $0.id == appId }?.name ?? appId
    }

    private static func diagnosticTimestamp(date: Date = Date()) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter.string(from: date)
            .replacingOccurrences(of: ":", with: "-")
    }

    private static func proofFileComponent(_ appId: String) -> String {
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-_"))
        return String(appId.unicodeScalars.map { scalar in
            allowed.contains(scalar) ? Character(scalar) : "-"
        })
    }

    private static func multiAppLatencySummary(
        for proof: WindowsAppCoherenceProofReport
    ) -> ShellMultiAppLatencySummary {
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

        return ShellMultiAppLatencySummary(
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
        failedResults: [ShellMultiAppProofResult]
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
}
