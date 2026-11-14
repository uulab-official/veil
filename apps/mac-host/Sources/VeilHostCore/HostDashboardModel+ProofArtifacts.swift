import CoreGraphics
import Foundation
import Observation

private struct ProofArtifactCandidate {
    var kind: String
    var url: URL
    var modifiedAt: Date
}

private struct ProofArtifactLatencySummary: Equatable {
    var health: String
    var slowestMeasurement: String
    var slowestElapsedMilliseconds: Int
    var freshFrameBudgetMilliseconds: Int
    var staleFrameTimeoutMilliseconds: Int
    var recommendedAction: String
}

private struct ProofArtifactMetadata: Equatable {
    var appId: String?
    var latencySummary: ProofArtifactLatencySummary?
}

private struct NotificationProofArtifactMetadata: Equatable {
    var status: String?
    var notificationId: String?
    var notificationTitle: String?
    var notificationReceivedAt: Date?
}

private struct PrinterBridgeProofArtifactMetadata: Equatable {
    var status: String?
    var evidencePath: String?
    var evidenceFileName: String?
    var evidenceByteCount: Int?
    var evidenceModifiedAt: Date?
    var sharedPrinterName: String?
    var windowsPrinterName: String?
    var ippEndpoint: String?
}

private struct ProofArtifactLatencyEvidence: Decodable {
    var measurement: String
    var elapsedMilliseconds: Int
    var freshFrameBudgetMilliseconds: Int
    var staleFrameTimeoutMilliseconds: Int
    var recommendedAction: String
}

private struct ProofArtifactLatencyEnvelope: Decodable {
    var appId: String?
    var firstFrameLatency: ProofArtifactLatencyEvidence?
    var initialFrameLatency: ProofArtifactLatencyEvidence?
    var postInputFrameLatency: ProofArtifactLatencyEvidence?
    var coherence: ProofArtifactCoherenceLatencyEnvelope?
}

private struct ProofArtifactCoherenceLatencyEnvelope: Decodable {
    var initialFrameLatency: ProofArtifactLatencyEvidence?
    var postInputFrameLatency: ProofArtifactLatencyEvidence?
}

private struct NotificationProofArtifactEnvelope: Decodable {
    var status: String?
    var notification: NotificationProofArtifactNotification?
}

private struct NotificationProofArtifactNotification: Decodable {
    var notificationId: String?
    var title: String?
    var receivedAt: Date?
}

private struct PrinterBridgeProofArtifactEnvelope: Decodable {
    var status: String?
    var evidencePath: String?
    var evidenceFileName: String?
    var evidenceByteCount: Int?
    var evidenceModifiedAt: Date?
    var plan: PrinterBridgeProofPlanEnvelope?
}

private struct PrinterBridgeProofPlanEnvelope: Decodable {
    var sharedPrinterName: String?
    var windowsPrinterName: String?
    var ippEndpoint: String?
}

extension HostDashboardModel {
    public func proofPlanStatus() -> WindowsAppRuntimeProofPlanStatus {
        let canRunMultiAppProof = hasLiveAgentConnection
            && health?.capabilities.windowCapture == true
            && health?.capabilities.input == true
            && health?.capabilities.clipboardText == true
            && WindowsAppRuntimeProofCoverageDefaults.targetAppIds.allSatisfy { canLaunchApp(appId: $0) }
        let multiAppProofCommand = canRunMultiAppProof
            ? "veil-vmctl multi-app-proof --json --require-complete"
            : nil

        guard let selectedAppId else {
            return WindowsAppRuntimeProofPlanStatus(
                selectedAppId: nil,
                canRunAppWindowProof: false,
                canRunCoherenceProof: false,
                canRunMVPProof: false,
                canRunMultiAppProof: canRunMultiAppProof,
                recommendedMultiAppProofCommand: multiAppProofCommand,
                reason: "Select a Windows app before running app checks."
            )
        }

        guard hasLiveAgentConnection else {
            return WindowsAppRuntimeProofPlanStatus(
                selectedAppId: selectedAppId,
                canRunAppWindowProof: false,
                canRunCoherenceProof: false,
                canRunMVPProof: false,
                canRunMultiAppProof: canRunMultiAppProof,
                recommendedMultiAppProofCommand: multiAppProofCommand,
                reason: "Wait for the Windows app connection before running app checks."
            )
        }

        guard canLaunchApp(appId: selectedAppId) else {
            return WindowsAppRuntimeProofPlanStatus(
                selectedAppId: selectedAppId,
                canRunAppWindowProof: false,
                canRunCoherenceProof: false,
                canRunMVPProof: false,
                canRunMultiAppProof: canRunMultiAppProof,
                recommendedMultiAppProofCommand: multiAppProofCommand,
                reason: "The selected Windows app is not available for app checks."
            )
        }

        let appWindowCommand = "veil-vmctl app-window-proof --json --app-id \(selectedAppId)"
        let coherenceCommand = "veil-vmctl coherence-proof --json --app-id \(selectedAppId)"
        let mvpCommand = "veil-vmctl mvp-proof --json --app-id \(selectedAppId) --require-proved"

        guard health?.capabilities.windowCapture == true else {
            return WindowsAppRuntimeProofPlanStatus(
                selectedAppId: selectedAppId,
                canRunAppWindowProof: false,
                canRunCoherenceProof: false,
                canRunMVPProof: false,
                canRunMultiAppProof: canRunMultiAppProof,
                recommendedMultiAppProofCommand: multiAppProofCommand,
                reason: "The Windows app connection must support window capture before the window check can run."
            )
        }

        guard health?.capabilities.input == true,
              health?.capabilities.clipboardText == true else {
            return WindowsAppRuntimeProofPlanStatus(
                selectedAppId: selectedAppId,
                canRunAppWindowProof: true,
                canRunCoherenceProof: false,
                canRunMVPProof: false,
                canRunMultiAppProof: canRunMultiAppProof,
                recommendedProofKind: "app-window",
                recommendedProofCommand: appWindowCommand,
                recommendedAppWindowProofCommand: appWindowCommand,
                recommendedMultiAppProofCommand: multiAppProofCommand,
                reason: "The Windows app connection must support input and clipboard before full app checks can run."
            )
        }

        return WindowsAppRuntimeProofPlanStatus(
            selectedAppId: selectedAppId,
            canRunAppWindowProof: true,
            canRunCoherenceProof: true,
            canRunMVPProof: true,
            canRunMultiAppProof: canRunMultiAppProof,
            recommendedProofKind: "mvp",
            recommendedProofCommand: mvpCommand,
            recommendedAppWindowProofCommand: appWindowCommand,
            recommendedCoherenceProofCommand: coherenceCommand,
            recommendedMVPProofCommand: mvpCommand,
            recommendedMultiAppProofCommand: multiAppProofCommand,
            reason: "The Windows app connection can run window, input, and full app checks for the selected app."
        )
    }

    public func proofArtifactStatus(
        diagnosticsDirectory: URL = QEMUVMRuntimeBooter.defaultDiagnosticsDirectory()
    ) -> WindowsAppRuntimeProofArtifactStatus {
        let recommendedProofDirectory = diagnosticsDirectory
            .appendingPathComponent("Recommended Proof", isDirectory: true)
        let notificationProofDirectory = diagnosticsDirectory
            .appendingPathComponent("Notification Proof", isDirectory: true)
        let printerProofDirectory = diagnosticsDirectory
            .appendingPathComponent("Printer Proof", isDirectory: true)
        let searchDirectories: [(kind: String, url: URL)] = [
            ("recommended", recommendedProofDirectory),
            ("mvp", diagnosticsDirectory.appendingPathComponent("MVP Proof", isDirectory: true)),
            ("coherence", diagnosticsDirectory.appendingPathComponent("Coherence Proof", isDirectory: true)),
            ("app-window", diagnosticsDirectory.appendingPathComponent("App Window Proof", isDirectory: true))
        ]

        let proofCandidates = searchDirectories
            .flatMap { proofArtifacts(in: $0.url, kind: $0.kind) }
        let latestProof = proofCandidates.max { lhs, rhs in
                lhs.modifiedAt < rhs.modifiedAt
            }
        let latestNotificationProof = proofArtifacts(in: notificationProofDirectory, kind: "notification")
            .max { lhs, rhs in
                lhs.modifiedAt < rhs.modifiedAt
            }
        let latestNotificationProofMetadata = latestNotificationProof.map {
            notificationProofArtifactMetadata(for: $0.url)
        }
        let latestPrinterBridgeProof = proofArtifacts(in: printerProofDirectory, kind: "printer-bridge")
            .max { lhs, rhs in
                lhs.modifiedAt < rhs.modifiedAt
            }
        let latestPrinterBridgeProofMetadata = latestPrinterBridgeProof.map {
            printerBridgeProofArtifactMetadata(for: $0.url)
        }
        let latestProofsByApp = proofArtifactSummariesByApp(from: proofCandidates)
        let targetAppIds = WindowsAppRuntimeProofCoverageDefaults.targetAppIds
        let coveredTargetCount = Set(latestProofsByApp.map(\.appId))
            .intersection(Set(targetAppIds))
            .count
        let coverageHealth: String
        if coveredTargetCount == targetAppIds.count {
            coverageHealth = "complete"
        } else if coveredTargetCount > 0 {
            coverageHealth = "partial"
        } else {
            coverageHealth = "missing"
        }

        guard let latestProof else {
            return WindowsAppRuntimeProofArtifactStatus(
                diagnosticsDirectory: diagnosticsDirectory.path,
                recommendedProofDirectory: recommendedProofDirectory.path,
                notificationProofDirectory: notificationProofDirectory.path,
                printerProofDirectory: printerProofDirectory.path,
                multiAppProofTargetAppIds: targetAppIds,
                multiAppProofCoverageCount: coveredTargetCount,
                multiAppProofCoverageHealth: coverageHealth,
                latestProofsByApp: latestProofsByApp,
                latestNotificationProofPath: latestNotificationProof?.url.path,
                latestNotificationProofFileName: latestNotificationProof?.url.lastPathComponent,
                latestNotificationProofModifiedAt: latestNotificationProof?.modifiedAt,
                latestNotificationProofStatus: latestNotificationProofMetadata?.status,
                latestNotificationProofId: latestNotificationProofMetadata?.notificationId,
                latestNotificationProofTitle: latestNotificationProofMetadata?.notificationTitle,
                latestNotificationProofReceivedAt: latestNotificationProofMetadata?.notificationReceivedAt,
                latestPrinterBridgeProofPath: latestPrinterBridgeProof?.url.path,
                latestPrinterBridgeProofFileName: latestPrinterBridgeProof?.url.lastPathComponent,
                latestPrinterBridgeProofModifiedAt: latestPrinterBridgeProof?.modifiedAt,
                latestPrinterBridgeProofStatus: latestPrinterBridgeProofMetadata?.status,
                latestPrinterBridgeProofEvidencePath: latestPrinterBridgeProofMetadata?.evidencePath,
                latestPrinterBridgeProofEvidenceFileName: latestPrinterBridgeProofMetadata?.evidenceFileName,
                latestPrinterBridgeProofEvidenceByteCount: latestPrinterBridgeProofMetadata?.evidenceByteCount,
                latestPrinterBridgeProofEvidenceModifiedAt: latestPrinterBridgeProofMetadata?.evidenceModifiedAt,
                latestPrinterBridgeProofSharedPrinterName: latestPrinterBridgeProofMetadata?.sharedPrinterName,
                latestPrinterBridgeProofWindowsPrinterName: latestPrinterBridgeProofMetadata?.windowsPrinterName,
                latestPrinterBridgeProofIppEndpoint: latestPrinterBridgeProofMetadata?.ippEndpoint,
                reason: "No app check artifact has been saved under Veil diagnostics yet."
            )
        }

        let latencySummary = proofArtifactMetadata(for: latestProof.url).latencySummary
        return WindowsAppRuntimeProofArtifactStatus(
            diagnosticsDirectory: diagnosticsDirectory.path,
            recommendedProofDirectory: recommendedProofDirectory.path,
            notificationProofDirectory: notificationProofDirectory.path,
            printerProofDirectory: printerProofDirectory.path,
            multiAppProofTargetAppIds: targetAppIds,
            multiAppProofCoverageCount: coveredTargetCount,
            multiAppProofCoverageHealth: coverageHealth,
            latestProofsByApp: latestProofsByApp,
            latestProofKind: latestProof.kind,
            latestProofPath: latestProof.url.path,
            latestProofFileName: latestProof.url.lastPathComponent,
            latestProofModifiedAt: latestProof.modifiedAt,
            latestProofLatencyHealth: latencySummary?.health,
            latestProofSlowestLatencyMeasurement: latencySummary?.slowestMeasurement,
            latestProofSlowestLatencyMilliseconds: latencySummary?.slowestElapsedMilliseconds,
            latestProofLatencyBudgetMilliseconds: latencySummary?.freshFrameBudgetMilliseconds,
            latestProofStaleTimeoutMilliseconds: latencySummary?.staleFrameTimeoutMilliseconds,
            latestProofLatencyRecommendedAction: latencySummary?.recommendedAction,
            latestNotificationProofPath: latestNotificationProof?.url.path,
            latestNotificationProofFileName: latestNotificationProof?.url.lastPathComponent,
            latestNotificationProofModifiedAt: latestNotificationProof?.modifiedAt,
            latestNotificationProofStatus: latestNotificationProofMetadata?.status,
            latestNotificationProofId: latestNotificationProofMetadata?.notificationId,
            latestNotificationProofTitle: latestNotificationProofMetadata?.notificationTitle,
            latestNotificationProofReceivedAt: latestNotificationProofMetadata?.notificationReceivedAt,
            latestPrinterBridgeProofPath: latestPrinterBridgeProof?.url.path,
            latestPrinterBridgeProofFileName: latestPrinterBridgeProof?.url.lastPathComponent,
            latestPrinterBridgeProofModifiedAt: latestPrinterBridgeProof?.modifiedAt,
            latestPrinterBridgeProofStatus: latestPrinterBridgeProofMetadata?.status,
            latestPrinterBridgeProofEvidencePath: latestPrinterBridgeProofMetadata?.evidencePath,
            latestPrinterBridgeProofEvidenceFileName: latestPrinterBridgeProofMetadata?.evidenceFileName,
            latestPrinterBridgeProofEvidenceByteCount: latestPrinterBridgeProofMetadata?.evidenceByteCount,
            latestPrinterBridgeProofEvidenceModifiedAt: latestPrinterBridgeProofMetadata?.evidenceModifiedAt,
            latestPrinterBridgeProofSharedPrinterName: latestPrinterBridgeProofMetadata?.sharedPrinterName,
            latestPrinterBridgeProofWindowsPrinterName: latestPrinterBridgeProofMetadata?.windowsPrinterName,
            latestPrinterBridgeProofIppEndpoint: latestPrinterBridgeProofMetadata?.ippEndpoint,
            reason: "Latest app check artifact is available in Veil diagnostics."
        )
    }

    private func proofArtifacts(in directory: URL, kind: String) -> [ProofArtifactCandidate] {
        guard let urls = try? FileManager.default.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: [.contentModificationDateKey, .isRegularFileKey],
            options: [.skipsHiddenFiles]
        ) else {
            return []
        }

        return urls.compactMap { url in
            guard url.pathExtension.lowercased() == "json",
                  let values = try? url.resourceValues(forKeys: [.contentModificationDateKey, .isRegularFileKey]),
                  values.isRegularFile == true,
                  let modifiedAt = values.contentModificationDate else {
                return nil
            }

            return ProofArtifactCandidate(kind: proofKind(for: url, fallback: kind), url: url, modifiedAt: modifiedAt)
        }
    }

    private func proofArtifactSummariesByApp(
        from candidates: [ProofArtifactCandidate]
    ) -> [WindowsAppRuntimeProofArtifactAppSummary] {
        let latestByApp = candidates.reduce(into: [String: ProofArtifactCandidate]()) { result, candidate in
            let metadata = proofArtifactMetadata(for: candidate.url)
            guard let appId = metadata.appId else {
                return
            }
            if let existing = result[appId],
               existing.modifiedAt >= candidate.modifiedAt {
                return
            }
            result[appId] = candidate
        }

        let targetOrder = Dictionary(
            uniqueKeysWithValues: WindowsAppRuntimeProofCoverageDefaults.targetAppIds.enumerated().map { index, appId in
                (appId, index)
            }
        )

        return latestByApp
            .map { appId, candidate in
                let latencySummary = proofArtifactMetadata(for: candidate.url).latencySummary
                return WindowsAppRuntimeProofArtifactAppSummary(
                    appId: appId,
                    latestProofKind: candidate.kind,
                    latestProofPath: candidate.url.path,
                    latestProofFileName: candidate.url.lastPathComponent,
                    latestProofModifiedAt: candidate.modifiedAt,
                    latestProofLatencyHealth: latencySummary?.health,
                    latestProofSlowestLatencyMeasurement: latencySummary?.slowestMeasurement,
                    latestProofSlowestLatencyMilliseconds: latencySummary?.slowestElapsedMilliseconds,
                    latestProofLatencyBudgetMilliseconds: latencySummary?.freshFrameBudgetMilliseconds,
                    latestProofStaleTimeoutMilliseconds: latencySummary?.staleFrameTimeoutMilliseconds,
                    latestProofLatencyRecommendedAction: latencySummary?.recommendedAction
                )
            }
            .sorted { lhs, rhs in
                let lhsIndex = targetOrder[lhs.appId] ?? Int.max
                let rhsIndex = targetOrder[rhs.appId] ?? Int.max
                if lhsIndex != rhsIndex {
                    return lhsIndex < rhsIndex
                }
                return lhs.appId < rhs.appId
            }
    }

    private func proofArtifactMetadata(for url: URL) -> ProofArtifactMetadata {
        guard let data = try? Data(contentsOf: url),
              let envelope = try? JSONDecoder().decode(ProofArtifactLatencyEnvelope.self, from: data) else {
            return ProofArtifactMetadata(appId: nil, latencySummary: nil)
        }

        let evidence = [
            envelope.firstFrameLatency,
            envelope.initialFrameLatency,
            envelope.postInputFrameLatency,
            envelope.coherence?.initialFrameLatency,
            envelope.coherence?.postInputFrameLatency
        ].compactMap { $0 }

        guard let slowest = evidence.max(by: { lhs, rhs in
            lhs.elapsedMilliseconds < rhs.elapsedMilliseconds
        }) else {
            return ProofArtifactMetadata(appId: envelope.appId, latencySummary: nil)
        }

        let health: String
        let recommendedAction: String
        if slowest.elapsedMilliseconds <= slowest.freshFrameBudgetMilliseconds {
            health = "healthy"
            recommendedAction = "none"
        } else if slowest.elapsedMilliseconds <= slowest.staleFrameTimeoutMilliseconds {
            health = "delayed"
            recommendedAction = "measure-again"
        } else {
            health = "stale"
            recommendedAction = "tune-frame-latency"
        }

        return ProofArtifactMetadata(
            appId: envelope.appId,
            latencySummary: ProofArtifactLatencySummary(
                health: health,
                slowestMeasurement: slowest.measurement,
                slowestElapsedMilliseconds: slowest.elapsedMilliseconds,
                freshFrameBudgetMilliseconds: slowest.freshFrameBudgetMilliseconds,
                staleFrameTimeoutMilliseconds: slowest.staleFrameTimeoutMilliseconds,
                recommendedAction: recommendedAction
            )
        )
    }

    private func notificationProofArtifactMetadata(for url: URL) -> NotificationProofArtifactMetadata {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        guard let data = try? Data(contentsOf: url),
              let envelope = try? decoder.decode(NotificationProofArtifactEnvelope.self, from: data) else {
            return NotificationProofArtifactMetadata(
                status: nil,
                notificationId: nil,
                notificationTitle: nil,
                notificationReceivedAt: nil
            )
        }

        return NotificationProofArtifactMetadata(
            status: envelope.status,
            notificationId: envelope.notification?.notificationId,
            notificationTitle: envelope.notification?.title,
            notificationReceivedAt: envelope.notification?.receivedAt
        )
    }

    private func printerBridgeProofArtifactMetadata(for url: URL) -> PrinterBridgeProofArtifactMetadata {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        guard let data = try? Data(contentsOf: url),
              let envelope = try? decoder.decode(PrinterBridgeProofArtifactEnvelope.self, from: data) else {
            return PrinterBridgeProofArtifactMetadata(
                status: nil,
                evidencePath: nil,
                evidenceFileName: nil,
                evidenceByteCount: nil,
                evidenceModifiedAt: nil,
                sharedPrinterName: nil,
                windowsPrinterName: nil,
                ippEndpoint: nil
            )
        }

        return PrinterBridgeProofArtifactMetadata(
            status: envelope.status,
            evidencePath: envelope.evidencePath,
            evidenceFileName: envelope.evidenceFileName,
            evidenceByteCount: envelope.evidenceByteCount,
            evidenceModifiedAt: envelope.evidenceModifiedAt,
            sharedPrinterName: envelope.plan?.sharedPrinterName,
            windowsPrinterName: envelope.plan?.windowsPrinterName,
            ippEndpoint: envelope.plan?.ippEndpoint
        )
    }

    private func proofKind(for url: URL, fallback: String) -> String {
        let fileName = url.lastPathComponent.lowercased()
        if fileName.contains("mvp") {
            return "mvp"
        }
        if fileName.contains("coherence") {
            return "coherence"
        }
        if fileName.contains("app-window") || fileName.contains("appframe") || fileName.contains("app-frame") {
            return "app-window"
        }
        return fallback
    }
}
