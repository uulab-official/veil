import AppKit
import SwiftUI
import VeilHostCore

enum RecommendedProofError: Error, LocalizedError {
    case unsupportedKind(String)

    var errorDescription: String? {
        switch self {
        case .unsupportedKind(let kind):
            "Unsupported recommended proof kind: \(kind)"
        }
    }
}

struct ShellMultiAppProofReport: Encodable {
    var kind = "windowsMultiAppProof"
    var endpoint: String
    var provedAt: Date
    var proofDirectory: String
    var aggregateReportPath: String
    var appIds: [String]
    var targetAppIds: [String]
    var waitSeconds: Int
    var proofKind: String
    var provedAppCount: Int
    var failedAppCount: Int
    var coverageHealth: String
    var results: [ShellMultiAppProofResult]
    var nextActions: [String]
}

struct ShellMultiAppProofResult: Encodable {
    var appId: String
    var status: String
    var proofKind: String?
    var proofPath: String?
    var latencyHealth: String?
    var slowestLatencyMeasurement: String?
    var slowestLatencyMilliseconds: Int?
    var latencyBudgetMilliseconds: Int?
    var staleTimeoutMilliseconds: Int?
    var latencyRecommendedAction: String?
    var windowId: String?
    var windowTitle: String?
    var errorMessage: String?
}

struct ShellMultiAppLatencySummary {
    var health: String
    var slowestMeasurement: String
    var slowestElapsedMilliseconds: Int
    var freshFrameBudgetMilliseconds: Int
    var staleFrameTimeoutMilliseconds: Int
    var recommendedAction: String
}
