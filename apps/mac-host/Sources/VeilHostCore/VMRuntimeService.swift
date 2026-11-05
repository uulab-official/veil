import Foundation

public protocol VMRuntimeService: Sendable {
    func loadSnapshot() async throws -> VMRuntimeSnapshot
    func prepareDefaultVM() async throws -> VMRuntimeSnapshot
    func createDefaultProfile() async throws -> VMRuntimeSnapshot
    func createDefaultVirtualDisk() async throws -> VMRuntimeSnapshot
    func updateProfilePaths(installerMediaPath: String?, driverMediaPath: String?, virtualDiskPath: String?) async throws -> VMRuntimeSnapshot
    func markWindowsInstalled() async throws -> VMRuntimeSnapshot
    func restartWindowsInstallation() async throws -> VMRuntimeSnapshot
    func updateWindowsAccountName(_ name: String?) async throws -> VMRuntimeSnapshot
    func updateHardware(cpuCount: Int, memoryMB: Int) async throws -> VMRuntimeSnapshot
    func updateStartupBehavior(autoStart: Bool, suspendOnQuit: Bool) async throws -> VMRuntimeSnapshot
    func updateCommandKeyMapping(_ mapping: VMCommandKeyMapping) async throws -> VMRuntimeSnapshot
    func updatePortForwards(_ rules: [VMPortForwardRule]) async throws -> VMRuntimeSnapshot
    func removableMediaStatus() async -> VMRemovableMediaStatus
    func insertRemovableMedia(path: String) async throws -> VMRemovableMediaStatus
    func ejectRemovableMedia() async throws -> VMRemovableMediaStatus
    func markGuestAgentConnected(agentVersion: String) async throws -> VMRuntimeSnapshot
    func start() async throws -> VMRuntimeSnapshot
    func stop() async throws -> VMRuntimeSnapshot
    func suspend() async throws -> VMRuntimeSnapshot
    func resume() async throws -> VMRuntimeSnapshot
    func suspendedSession() async -> VMSuspensionRecord?
    func sendConsolePointerTap(normalizedX: Double, normalizedY: Double) async throws -> QEMUPointerTapRecord
    func sendConsoleKey(_ key: String) async throws -> QEMUKeySendRecord
    func exportDiagnostics(to directory: URL) async throws -> URL
    /// The Mac's USB devices and which of them the running Windows has.
    func usbPassthroughSnapshot() async -> USBPassthroughSnapshot
    func attachUSBDevice(_ device: MacUSBDevice) async throws -> USBPassthroughSnapshot
    func detachUSBDevice(id: String) async throws -> USBPassthroughSnapshot
}

/// Defaults so a runtime service that predates session persistence -- including test doubles -- keeps
/// compiling and reports the honest answer instead of pretending to suspend.
public extension VMRuntimeService {
    func suspend() async throws -> VMRuntimeSnapshot {
        throw VMRuntimeError.suspendNotSupported
    }

    func resume() async throws -> VMRuntimeSnapshot {
        throw VMRuntimeError.suspendNotSupported
    }

    func suspendedSession() async -> VMSuspensionRecord? {
        nil
    }

    func restartWindowsInstallation() async throws -> VMRuntimeSnapshot {
        throw VMRuntimeError.bootNotImplemented
    }

    func updateWindowsAccountName(_ name: String?) async throws -> VMRuntimeSnapshot {
        try await loadSnapshot()
    }

    func updateHardware(cpuCount: Int, memoryMB: Int) async throws -> VMRuntimeSnapshot {
        throw VMRuntimeError.bootNotImplemented
    }

    func updateStartupBehavior(autoStart: Bool, suspendOnQuit: Bool) async throws -> VMRuntimeSnapshot {
        throw VMRuntimeError.bootNotImplemented
    }

    func updateCommandKeyMapping(_ mapping: VMCommandKeyMapping) async throws -> VMRuntimeSnapshot {
        throw VMRuntimeError.bootNotImplemented
    }

    func updatePortForwards(_ rules: [VMPortForwardRule]) async throws -> VMRuntimeSnapshot {
        throw VMRuntimeError.bootNotImplemented
    }

    func removableMediaStatus() async -> VMRemovableMediaStatus {
        .unavailable(.notRunning)
    }

    func insertRemovableMedia(path: String) async throws -> VMRemovableMediaStatus {
        throw VMRemovableMediaError.notRunning
    }

    func ejectRemovableMedia() async throws -> VMRemovableMediaStatus {
        throw VMRemovableMediaError.notRunning
    }

    func usbPassthroughSnapshot() async -> USBPassthroughSnapshot {
        USBPassthroughSnapshot(isVMRunning: false, macDevices: [])
    }

    func attachUSBDevice(_ device: MacUSBDevice) async throws -> USBPassthroughSnapshot {
        throw USBPassthroughError.vmNotRunning
    }

    func detachUSBDevice(id: String) async throws -> USBPassthroughSnapshot {
        throw USBPassthroughError.vmNotRunning
    }
}

public protocol VMRuntimeBooting: Sendable {
    func runtimeState() async -> VMRuntimeState?
    func start(profile: VMProfile) async throws -> VMRuntimeState
    func stop() async throws -> VMRuntimeState
    /// Attempts a reversible control-path recovery without restarting a live guest.
    func recoverStalledRuntime() async -> QEMURuntimeRecoveryResult
    /// Pauses the guest and persists its memory state so a later `resume` continues the same Windows
    /// session instead of rebooting it.
    func suspend(profile: VMProfile) async throws -> VMRuntimeState
    func resume(profile: VMProfile) async throws -> VMRuntimeState
}

/// Providers that cannot persist a guest session keep the honest default: a clear "not supported"
/// error instead of silently falling back to stop/start, which would lose the user's open apps.
public extension VMRuntimeBooting {
    func recoverStalledRuntime() async -> QEMURuntimeRecoveryResult {
        .unsupported
    }

    func suspend(profile: VMProfile) async throws -> VMRuntimeState {
        throw VMRuntimeError.suspendNotSupported
    }

    func resume(profile: VMProfile) async throws -> VMRuntimeState {
        throw VMRuntimeError.suspendNotSupported
    }
}

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
    case resourceMutationRequiresStoppedRuntime
    case suspendNotSupported
    case restartInstallationRequiresUninstalledWindows

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
        case .resourceMutationRequiresStoppedRuntime:
            "Stop Windows before changing VM resources. Running, starting, or suspended sessions keep their disk and installer attachments locked."
        case .suspendNotSupported:
            "The active local VM runtime provider cannot suspend a Windows session yet. Stop the VM instead."
        case .restartInstallationRequiresUninstalledWindows:
            "Windows is already installed on this disk, so Veil won't erase it to restart the installation."
        }
    }
}
