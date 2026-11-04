import Foundation

public struct UnavailableVMRuntimeBooter: VMRuntimeBooting {
    public init() {}

    public func runtimeState() async -> VMRuntimeState? {
        nil
    }

    public func start(profile: VMProfile) async throws -> VMRuntimeState {
        throw VMRuntimeError.bootNotImplemented
    }

    public func stop() async throws -> VMRuntimeState {
        .stopped
    }
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

public enum VMRuntimeProviderKind: String, Codable, Equatable, Sendable {
    case appleVirtualization
    case qemuHypervisor
}

public enum VMRuntimeProviderStatus: String, Codable, Equatable, Sendable {
    case active
    case planned
    case unavailable
}

public struct VMRuntimeProviderSummary: Codable, Equatable, Sendable {
    public var kind: VMRuntimeProviderKind
    public var displayName: String
    public var mode: String
    public var acceleration: String
    public var isServerBacked: Bool
    public var status: VMRuntimeProviderStatus
    public var detail: String
    public var executablePath: String?
    public var executableVersion: String?

    public init(
        kind: VMRuntimeProviderKind,
        displayName: String,
        mode: String,
        acceleration: String,
        isServerBacked: Bool,
        status: VMRuntimeProviderStatus,
        detail: String,
        executablePath: String? = nil,
        executableVersion: String? = nil
    ) {
        self.kind = kind
        self.displayName = displayName
        self.mode = mode
        self.acceleration = acceleration
        self.isServerBacked = isServerBacked
        self.status = status
        self.detail = detail
        self.executablePath = executablePath
        self.executableVersion = executableVersion
    }
}

public enum VMRuntimeError: Error, LocalizedError, Equatable, Sendable {
    case capabilityProbeFailed
    case bootNotImplemented
    case bootPrerequisitesMissing
    case automaticInstallMediaCreationFailed(String)
    case qemuNotReady(String)
    case qemuDisplayPortUnavailable
    case qemuAlreadyRunning(pid: Int32)
    case suspendNotSupported

    public var errorDescription: String? {
        switch self {
        case .capabilityProbeFailed:
            "Unable to inspect VM runtime capabilities."
        case .bootNotImplemented:
            "VM boot is not implemented yet."
        case .bootPrerequisitesMissing:
            "Windows setup media is required before installation; after Windows is installed, the system disk, shared folder, and preflight checks must be ready before starting."
        case let .automaticInstallMediaCreationFailed(message):
            "Unable to create automatic Windows install media: \(message)"
        case let .qemuNotReady(message):
            "QEMU/HVF is not ready: \(message)"
        case .qemuDisplayPortUnavailable:
            "No loopback VNC display port is available. Close stale QEMU/VNC listeners and try again."
        case let .qemuAlreadyRunning(pid):
            "QEMU is already running as PID \(pid) with the configured Windows disk attached. Shut down that VM before starting another one."
        case .suspendNotSupported:
            "The active local VM runtime provider cannot suspend a Windows session yet. Stop the VM instead."
        }
    }
}

public protocol AutomaticInstallMediaBuilding: Sendable {
    func prepareMedia(answerFileURL: URL, mediaURL: URL) throws
}
