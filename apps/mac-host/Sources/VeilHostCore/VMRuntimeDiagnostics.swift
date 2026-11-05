import Foundation

public enum VMInstallationStepState: String, Codable, Equatable, Sendable {
    case complete
    case pending
    case blocked
}

public struct VMInstallationStep: Codable, Equatable, Identifiable, Sendable {
    public var id: String
    public var title: String
    public var detail: String
    public var state: VMInstallationStepState

    public init(
        id: String,
        title: String,
        detail: String,
        state: VMInstallationStepState
    ) {
        self.id = id
        self.title = title
        self.detail = detail
        self.state = state
    }
}

public enum VMPreflightCheckState: String, Codable, Equatable, Sendable {
    case passed
    case failed
}

public struct VMPreflightCheck: Codable, Equatable, Identifiable, Sendable {
    public var id: String
    public var title: String
    public var detail: String
    public var state: VMPreflightCheckState

    public init(
        id: String,
        title: String,
        detail: String,
        state: VMPreflightCheckState
    ) {
        self.id = id
        self.title = title
        self.detail = detail
        self.state = state
    }
}

public struct VMRuntimeDiagnosticHost: Codable, Equatable, Sendable {
    public var architecture: String
    public var processorCount: Int
    public var physicalMemoryBytes: UInt64
    public var operatingSystemVersion: String

    public init(
        architecture: String,
        processorCount: Int,
        physicalMemoryBytes: UInt64,
        operatingSystemVersion: String
    ) {
        self.architecture = architecture
        self.processorCount = processorCount
        self.physicalMemoryBytes = physicalMemoryBytes
        self.operatingSystemVersion = operatingSystemVersion
    }
}

public struct VMRuntimeDiagnosticBundle: Codable, Equatable, Sendable {
    public var generatedAt: Date
    public var host: VMRuntimeDiagnosticHost
    public var snapshot: VMRuntimeSnapshot
    public var profile: VMProfile?
    public var lastBootReport: VMRuntimeBootReport?

    public init(
        generatedAt: Date,
        host: VMRuntimeDiagnosticHost,
        snapshot: VMRuntimeSnapshot,
        profile: VMProfile?,
        lastBootReport: VMRuntimeBootReport? = nil
    ) {
        self.generatedAt = generatedAt
        self.host = host
        self.snapshot = snapshot
        self.profile = profile
        self.lastBootReport = lastBootReport
    }
}

public enum VMRuntimeBootReportResult: String, Codable, Equatable, Sendable {
    case succeeded
    case failed
}

public struct VMRuntimeBootReport: Codable, Equatable, Sendable {
    public var startedAt: Date
    public var completedAt: Date
    public var result: VMRuntimeBootReportResult
    public var resultingState: VMRuntimeState
    public var errorMessage: String?
    public var profile: VMProfile
    public var deviceSummary: VMRuntimeDeviceSummary

    public init(
        startedAt: Date,
        completedAt: Date,
        result: VMRuntimeBootReportResult,
        resultingState: VMRuntimeState,
        errorMessage: String?,
        profile: VMProfile,
        deviceSummary: VMRuntimeDeviceSummary
    ) {
        self.startedAt = startedAt
        self.completedAt = completedAt
        self.result = result
        self.resultingState = resultingState
        self.errorMessage = errorMessage
        self.profile = profile
        self.deviceSummary = deviceSummary
    }

    public func withoutSecurityScopedBookmarks() -> VMRuntimeBootReport {
        VMRuntimeBootReport(
            startedAt: startedAt,
            completedAt: completedAt,
            result: result,
            resultingState: resultingState,
            errorMessage: errorMessage,
            profile: profile.withoutSecurityScopedBookmarks(),
            deviceSummary: deviceSummary
        )
    }
}

public protocol VMRuntimeBootReportStore: Sendable {
    func load() async throws -> VMRuntimeBootReport?
    func save(_ report: VMRuntimeBootReport) async throws
}

public struct JSONVMRuntimeBootReportStore: VMRuntimeBootReportStore {
    /// The selected library machine's diagnostics folder.
    public static var defaultDirectory: URL {
        QEMUVMRuntimeBooter.defaultDiagnosticsDirectory()
    }

    private let fixedDirectory: URL?
    private let fileName: String

    public init(
        directory: URL? = nil,
        fileName: String = "last-boot-report.json"
    ) {
        self.fixedDirectory = directory
        self.fileName = fileName
    }

    private var directory: URL {
        fixedDirectory ?? Self.defaultDirectory
    }

    public func load() async throws -> VMRuntimeBootReport? {
        let url = reportURL
        guard FileManager.default.fileExists(atPath: url.path) else {
            return nil
        }

        let data = try Data(contentsOf: url)
        return try JSONDecoder.veilDiagnostics.decode(VMRuntimeBootReport.self, from: data)
    }

    public func save(_ report: VMRuntimeBootReport) async throws {
        try FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true
        )
        let data = try JSONEncoder.veilDiagnostics.encode(report)
        try data.write(to: reportURL, options: [.atomic])
    }

    private var reportURL: URL {
        directory.appendingPathComponent(fileName)
    }
}

public extension JSONEncoder {
    static var veilDiagnostics: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }
}

public extension JSONDecoder {
    static var veilDiagnostics: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }
}
