import Foundation

public protocol VMRuntimeService: Sendable {
    func loadSnapshot() async throws -> VMRuntimeSnapshot
}

public enum VMRuntimeState: String, Codable, Equatable, Sendable {
    case unsupported
    case notConfigured
    case stopped
    case starting
    case running
    case suspended
    case failed
}

public struct VMRuntimeSnapshot: Codable, Equatable, Sendable {
    public var state: VMRuntimeState
    public var virtualizationAvailable: Bool
    public var architecture: String
    public var minimumOSSupported: Bool
    public var profileName: String?
    public var detail: String

    public init(
        state: VMRuntimeState,
        virtualizationAvailable: Bool,
        architecture: String,
        minimumOSSupported: Bool,
        profileName: String?,
        detail: String
    ) {
        self.state = state
        self.virtualizationAvailable = virtualizationAvailable
        self.architecture = architecture
        self.minimumOSSupported = minimumOSSupported
        self.profileName = profileName
        self.detail = detail
    }
}

public enum VMRuntimeError: Error, LocalizedError, Equatable, Sendable {
    case capabilityProbeFailed

    public var errorDescription: String? {
        switch self {
        case .capabilityProbeFailed:
            "Unable to inspect VM runtime capabilities."
        }
    }
}

public enum VMRuntimePhase: Equatable, Sendable {
    case idle
    case loading
    case loaded
    case failed
}

@MainActor
@Observable
public final class VMRuntimeModel {
    public private(set) var phase: VMRuntimePhase = .idle
    public private(set) var snapshot: VMRuntimeSnapshot?
    public private(set) var errorMessage: String?

    private let service: any VMRuntimeService

    public init(service: any VMRuntimeService) {
        self.service = service
    }

    public var statusText: String {
        guard let snapshot else {
            return phase == .failed ? (errorMessage ?? "VM runtime unavailable") : "VM runtime not loaded"
        }

        switch snapshot.state {
        case .unsupported:
            return "VM runtime unsupported"
        case .notConfigured:
            return "VM profile not configured"
        case .stopped:
            return "VM stopped"
        case .starting:
            return "VM starting"
        case .running:
            return "VM running"
        case .suspended:
            return "VM suspended"
        case .failed:
            return "VM failed"
        }
    }

    public var canStart: Bool {
        guard let snapshot else {
            return false
        }

        return snapshot.virtualizationAvailable &&
            snapshot.minimumOSSupported &&
            snapshot.profileName != nil &&
            (snapshot.state == .stopped || snapshot.state == .suspended)
    }

    public var capabilitySummary: String {
        guard let snapshot else {
            return "VM runtime capabilities not loaded"
        }

        let availability = snapshot.virtualizationAvailable ? "available" : "unavailable"
        return "Virtualization.framework \(availability) on \(snapshot.architecture)"
    }

    public func load() async {
        phase = .loading
        errorMessage = nil

        do {
            snapshot = try await service.loadSnapshot()
            phase = .loaded
        } catch {
            errorMessage = userMessage(for: error)
            phase = .failed
        }
    }

    private func userMessage(for error: any Error) -> String {
        if let localized = error as? LocalizedError,
           let description = localized.errorDescription {
            return description
        }

        return String(describing: error)
    }
}

public struct LocalVMRuntimeService: VMRuntimeService {
    public init() {}

    public func loadSnapshot() async throws -> VMRuntimeSnapshot {
        let architecture = Self.hostArchitecture()
        let minimumOSSupported = ProcessInfo.processInfo.isOperatingSystemAtLeast(
            OperatingSystemVersion(majorVersion: 15, minorVersion: 0, patchVersion: 0)
        )
        let virtualizationAvailable = architecture == "arm64" && minimumOSSupported

        return VMRuntimeSnapshot(
            state: virtualizationAvailable ? .notConfigured : .unsupported,
            virtualizationAvailable: virtualizationAvailable,
            architecture: architecture,
            minimumOSSupported: minimumOSSupported,
            profileName: nil,
            detail: virtualizationAvailable
                ? "No Windows VM profile has been created."
                : "Veil requires macOS 15+ on Apple Silicon."
        )
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
}
