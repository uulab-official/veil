import Foundation

public protocol VMRuntimeService: Sendable {
    func loadSnapshot() async throws -> VMRuntimeSnapshot
    func createDefaultProfile() async throws -> VMRuntimeSnapshot
    func updateProfilePaths(installerMediaPath: String?, virtualDiskPath: String?) async throws -> VMRuntimeSnapshot
    func start() async throws -> VMRuntimeSnapshot
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
    public var installerMediaPath: String?
    public var virtualDiskPath: String?
    public var bootReady: Bool
    public var detail: String

    public init(
        state: VMRuntimeState,
        virtualizationAvailable: Bool,
        architecture: String,
        minimumOSSupported: Bool,
        profileName: String?,
        installerMediaPath: String? = nil,
        virtualDiskPath: String? = nil,
        bootReady: Bool = false,
        detail: String
    ) {
        self.state = state
        self.virtualizationAvailable = virtualizationAvailable
        self.architecture = architecture
        self.minimumOSSupported = minimumOSSupported
        self.profileName = profileName
        self.installerMediaPath = installerMediaPath
        self.virtualDiskPath = virtualDiskPath
        self.bootReady = bootReady
        self.detail = detail
    }
}

public enum VMRuntimeError: Error, LocalizedError, Equatable, Sendable {
    case capabilityProbeFailed
    case bootNotImplemented

    public var errorDescription: String? {
        switch self {
        case .capabilityProbeFailed:
            "Unable to inspect VM runtime capabilities."
        case .bootNotImplemented:
            "VM boot is not implemented yet."
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
            snapshot.bootReady &&
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

    public func createDefaultProfile() async {
        phase = .loading
        errorMessage = nil

        do {
            snapshot = try await service.createDefaultProfile()
            phase = .loaded
        } catch {
            errorMessage = userMessage(for: error)
            phase = .failed
        }
    }

    public func updateProfilePaths(installerMediaPath: String?, virtualDiskPath: String?) async {
        phase = .loading
        errorMessage = nil

        do {
            snapshot = try await service.updateProfilePaths(
                installerMediaPath: installerMediaPath,
                virtualDiskPath: virtualDiskPath
            )
            phase = .loaded
        } catch {
            errorMessage = userMessage(for: error)
            phase = .failed
        }
    }

    public func start() async {
        phase = .loading
        errorMessage = nil

        do {
            snapshot = try await service.start()
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
    private let profileStore: any VMProfileStore

    public init(profileStore: any VMProfileStore = JSONVMProfileStore()) {
        self.profileStore = profileStore
    }

    public func loadSnapshot() async throws -> VMRuntimeSnapshot {
        let architecture = Self.hostArchitecture()
        let minimumOSSupported = ProcessInfo.processInfo.isOperatingSystemAtLeast(
            OperatingSystemVersion(majorVersion: 15, minorVersion: 0, patchVersion: 0)
        )
        let virtualizationAvailable = architecture == "arm64" && minimumOSSupported
        let profile = try await profileStore.load()

        if virtualizationAvailable, let profile {
            let bootPathReadiness = Self.bootPathReadiness(for: profile)
            return VMRuntimeSnapshot(
                state: .stopped,
                virtualizationAvailable: true,
                architecture: architecture,
                minimumOSSupported: true,
                profileName: profile.name,
                installerMediaPath: profile.installerMediaPath,
                virtualDiskPath: profile.virtualDiskPath,
                bootReady: bootPathReadiness.isReady,
                detail: bootPathReadiness.isReady
                    ? "Ready to boot when VM boot support lands."
                    : bootPathReadiness.detail
            )
        }

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

    public func createDefaultProfile() async throws -> VMRuntimeSnapshot {
        let profile = VMProfile.defaultWindows11Arm()
        try await profileStore.save(profile)
        return try await loadSnapshot()
    }

    public func updateProfilePaths(installerMediaPath: String?, virtualDiskPath: String?) async throws -> VMRuntimeSnapshot {
        var profile = try await profileStore.load() ?? VMProfile.defaultWindows11Arm()
        profile.installerMediaPath = installerMediaPath
        profile.virtualDiskPath = virtualDiskPath
        try await profileStore.save(profile)
        return try await loadSnapshot()
    }

    public func start() async throws -> VMRuntimeSnapshot {
        _ = try await loadSnapshot()
        throw VMRuntimeError.bootNotImplemented
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

    private static func bootPathReadiness(for profile: VMProfile) -> (isReady: Bool, detail: String) {
        guard let installerMediaPath = profile.installerMediaPath, !installerMediaPath.isEmpty,
              let virtualDiskPath = profile.virtualDiskPath, !virtualDiskPath.isEmpty else {
            return (false, "Installer media and virtual disk paths are required before boot.")
        }

        if let detail = fileValidationDetail(path: installerMediaPath, label: "Installer media") {
            return (false, detail)
        }

        if let detail = fileValidationDetail(path: virtualDiskPath, label: "Virtual disk") {
            return (false, detail)
        }

        return (true, "Ready to boot when VM boot support lands.")
    }

    private static func fileValidationDetail(path: String, label: String) -> String? {
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: path, isDirectory: &isDirectory) else {
            return "\(label) path does not exist."
        }

        if isDirectory.boolValue {
            return "\(label) path must reference a file."
        }

        return nil
    }
}
