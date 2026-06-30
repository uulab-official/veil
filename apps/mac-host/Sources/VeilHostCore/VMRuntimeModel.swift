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
    public var installationSteps: [VMInstallationStep]
    public var preflightChecks: [VMPreflightCheck]
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
        installationSteps: [VMInstallationStep] = [],
        preflightChecks: [VMPreflightCheck] = [],
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
        self.installationSteps = installationSteps
        self.preflightChecks = preflightChecks
        self.bootReady = bootReady
        self.detail = detail
    }
}

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
    private let defaultHomeDirectory: URL

    public init(
        profileStore: any VMProfileStore = JSONVMProfileStore(),
        defaultHomeDirectory: URL = FileManager.default.homeDirectoryForCurrentUser
    ) {
        self.profileStore = profileStore
        self.defaultHomeDirectory = defaultHomeDirectory
    }

    public func loadSnapshot() async throws -> VMRuntimeSnapshot {
        let architecture = Self.hostArchitecture()
        let minimumOSSupported = ProcessInfo.processInfo.isOperatingSystemAtLeast(
            OperatingSystemVersion(majorVersion: 15, minorVersion: 0, patchVersion: 0)
        )
        let virtualizationAvailable = architecture == "arm64" && minimumOSSupported
        let profile = try await profileStore.load()

        if virtualizationAvailable, let profile {
            let installationSteps = Self.installationSteps(for: profile)
            let preflightChecks = Self.preflightChecks(for: profile)
            let bootPathReadiness = Self.bootPathReadiness(
                installationSteps: installationSteps,
                preflightChecks: preflightChecks
            )
            return VMRuntimeSnapshot(
                state: .stopped,
                virtualizationAvailable: true,
                architecture: architecture,
                minimumOSSupported: true,
                profileName: profile.name,
                installerMediaPath: profile.installerMediaPath,
                virtualDiskPath: profile.virtualDiskPath,
                installationSteps: installationSteps,
                preflightChecks: preflightChecks,
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
        let profile = VMProfile.defaultWindows11Arm(homeDirectory: defaultHomeDirectory)
        try FileManager.default.createDirectory(
            atPath: profile.sharedFolderPath,
            withIntermediateDirectories: true
        )
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

    private static func bootPathReadiness(
        installationSteps: [VMInstallationStep],
        preflightChecks: [VMPreflightCheck]
    ) -> (isReady: Bool, detail: String) {
        for step in installationSteps where step.id != "guest-agent" && step.state != .complete {
            if step.id == "windows-installer" || step.id == "virtual-disk" {
                let missingPathDetails = [
                    "Select a Windows 11 Arm installer before setup can continue.",
                    "Select a virtual disk file before setup can continue."
                ]

                if missingPathDetails.contains(step.detail) {
                    return (false, "Installer media and virtual disk paths are required before boot.")
                }
            }

            return (false, step.detail)
        }

        if preflightChecks.contains(where: { $0.state == .failed }) {
            return (false, "VM profile needs attention before boot.")
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

    private static func installationSteps(for profile: VMProfile) -> [VMInstallationStep] {
        let installerState = fileStepState(
            path: profile.installerMediaPath,
            missingDetail: "Select a Windows 11 Arm installer before setup can continue.",
            validationLabel: "Installer media"
        )
        let diskState = fileStepState(
            path: profile.virtualDiskPath,
            missingDetail: "Select a virtual disk file before setup can continue.",
            validationLabel: "Virtual disk"
        )
        let sharedFolderState = directoryStepState(path: profile.sharedFolderPath)

        return [
            VMInstallationStep(
                id: "windows-installer",
                title: "Windows 11 Arm installer",
                detail: installerState.detail ?? "User-provided installer media is ready.",
                state: installerState.state
            ),
            VMInstallationStep(
                id: "virtual-disk",
                title: "Virtual disk",
                detail: diskState.detail ?? "User-provided virtual disk path is ready.",
                state: diskState.state
            ),
            VMInstallationStep(
                id: "shared-folder",
                title: "macOS shared folder",
                detail: sharedFolderState.detail ?? "Shared folder is ready for host and guest file exchange.",
                state: sharedFolderState.state
            ),
            VMInstallationStep(
                id: "guest-agent",
                title: "Veil guest agent",
                detail: "Install the guest agent inside Windows after the VM boot spike lands.",
                state: .pending
            )
        ]
    }

    private static func fileStepState(
        path: String?,
        missingDetail: String,
        validationLabel: String
    ) -> (state: VMInstallationStepState, detail: String?) {
        guard let path, !path.isEmpty else {
            return (.blocked, missingDetail)
        }

        if let detail = fileValidationDetail(path: path, label: validationLabel) {
            return (.blocked, detail)
        }

        return (.complete, nil)
    }

    private static func directoryStepState(path: String) -> (state: VMInstallationStepState, detail: String?) {
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: path, isDirectory: &isDirectory) else {
            return (.blocked, "Create the macOS shared folder before Windows setup can continue.")
        }

        guard isDirectory.boolValue else {
            return (.blocked, "Shared folder path must reference a directory.")
        }

        return (.complete, nil)
    }

    private static func preflightChecks(for profile: VMProfile) -> [VMPreflightCheck] {
        [
            VMPreflightCheck(
                id: "guest-os",
                title: "Windows Arm guest",
                detail: profile.os == "windows-arm64"
                    ? "Configured for Windows 11 Arm."
                    : "Only Windows 11 Arm profiles are supported on Apple Silicon.",
                state: profile.os == "windows-arm64" ? .passed : .failed
            ),
            VMPreflightCheck(
                id: "cpu",
                title: "CPU allocation",
                detail: profile.cpuCount >= 2
                    ? "\(profile.cpuCount) virtual CPUs configured."
                    : "At least 2 virtual CPUs are required.",
                state: profile.cpuCount >= 2 ? .passed : .failed
            ),
            VMPreflightCheck(
                id: "memory",
                title: "Memory allocation",
                detail: profile.memoryMB >= 4096
                    ? "\(profile.memoryMB) MB memory configured."
                    : "At least 4096 MB memory is required.",
                state: profile.memoryMB >= 4096 ? .passed : .failed
            ),
            VMPreflightCheck(
                id: "disk-size",
                title: "Disk size",
                detail: profile.diskGB >= 64
                    ? "\(profile.diskGB) GB virtual disk configured."
                    : "At least 64 GB disk capacity is required.",
                state: profile.diskGB >= 64 ? .passed : .failed
            )
        ]
    }
}
