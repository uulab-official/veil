import Foundation
import Virtualization

public final class VirtualizationVMRuntimeBooter: VMRuntimeBooting, @unchecked Sendable {
    public static let shared = VirtualizationVMRuntimeBooter()

    @MainActor
    public private(set) var activeVirtualMachine: VZVirtualMachine?

    public init() {}

    public func runtimeState() async -> VMRuntimeState? {
        await MainActor.run {
            guard let activeVirtualMachine else {
                return nil
            }

            return Self.runtimeState(from: activeVirtualMachine.state)
        }
    }

    public func start(profile: VMProfile) async throws -> VMRuntimeState {
        try await startOnMainActor(profile: profile)
    }

    public func stop() async throws -> VMRuntimeState {
        try await stopOnMainActor()
    }

    @MainActor
    private func startOnMainActor(profile: VMProfile) async throws -> VMRuntimeState {
        guard let activeVirtualMachine else {
            let configuration = try makeConfiguration(for: profile)
            let virtualMachine = VZVirtualMachine(configuration: configuration)
            activeVirtualMachine = virtualMachine

            try await virtualMachine.start()
            return Self.runtimeState(from: virtualMachine.state) ?? .running
        }

        if activeVirtualMachine.state == .running {
            return .running
        }

        if activeVirtualMachine.state == .starting {
            return .starting
        }

        if activeVirtualMachine.canStart {
            try await activeVirtualMachine.start()
            return Self.runtimeState(from: activeVirtualMachine.state) ?? .running
        }

        return Self.runtimeState(from: activeVirtualMachine.state) ?? .failed
    }

    @MainActor
    private func stopOnMainActor() async throws -> VMRuntimeState {
        guard let activeVirtualMachine else {
            return .stopped
        }

        if activeVirtualMachine.state == .stopped {
            return .stopped
        }

        if activeVirtualMachine.canStop {
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, any Error>) in
                activeVirtualMachine.stop { error in
                    if let error {
                        continuation.resume(throwing: error)
                    } else {
                        continuation.resume()
                    }
                }
            }
        }

        return Self.runtimeState(from: activeVirtualMachine.state) ?? .stopped
    }

    private func makeConfiguration(for profile: VMProfile) throws -> VZVirtualMachineConfiguration {
        let configuration = VZVirtualMachineConfiguration()
        configuration.platform = try platformConfiguration(for: profile)
        configuration.bootLoader = try efiBootLoader(for: profile)
        configuration.cpuCount = clampedCPUCount(profile.cpuCount)
        configuration.memorySize = clampedMemorySize(profile.memoryMB)
        configuration.storageDevices = try storageDevices(for: profile)
        configuration.networkDevices = [natNetworkDevice()]
        configuration.graphicsDevices = [graphicsDevice()]
        configuration.keyboards = [VZUSBKeyboardConfiguration()]
        configuration.pointingDevices = [VZUSBScreenCoordinatePointingDeviceConfiguration()]
        configuration.entropyDevices = [VZVirtioEntropyDeviceConfiguration()]

        try configuration.validate()
        return configuration
    }

    private func platformConfiguration(for profile: VMProfile) throws -> VZGenericPlatformConfiguration {
        let platform = VZGenericPlatformConfiguration()
        let identifierURL = try metadataURL(for: profile, pathExtension: "machine-id")

        if let data = try? Data(contentsOf: identifierURL),
           let machineIdentifier = VZGenericMachineIdentifier(dataRepresentation: data) {
            platform.machineIdentifier = machineIdentifier
            return platform
        }

        let machineIdentifier = VZGenericMachineIdentifier()
        try FileManager.default.createDirectory(
            at: identifierURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try machineIdentifier.dataRepresentation.write(to: identifierURL, options: [.atomic])
        platform.machineIdentifier = machineIdentifier
        return platform
    }

    private func efiBootLoader(for profile: VMProfile) throws -> VZEFIBootLoader {
        let bootLoader = VZEFIBootLoader()
        let variableStoreURL = try metadataURL(for: profile, pathExtension: "efi")

        if FileManager.default.fileExists(atPath: variableStoreURL.path) {
            bootLoader.variableStore = VZEFIVariableStore(url: variableStoreURL)
            return bootLoader
        }

        try FileManager.default.createDirectory(
            at: variableStoreURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        bootLoader.variableStore = try VZEFIVariableStore(
            creatingVariableStoreAt: variableStoreURL,
            options: []
        )
        return bootLoader
    }

    private func storageDevices(for profile: VMProfile) throws -> [VZStorageDeviceConfiguration] {
        guard let installerMediaPath = profile.installerMediaPath,
              let virtualDiskPath = profile.virtualDiskPath else {
            throw VMRuntimeError.bootPrerequisitesMissing
        }

        let installerAttachment = try VZDiskImageStorageDeviceAttachment(
            url: URL(fileURLWithPath: installerMediaPath),
            readOnly: true
        )
        let diskAttachment = try VZDiskImageStorageDeviceAttachment(
            url: URL(fileURLWithPath: virtualDiskPath),
            readOnly: false
        )

        let installerDevice = VZUSBMassStorageDeviceConfiguration(attachment: installerAttachment)
        let diskDevice = VZVirtioBlockDeviceConfiguration(attachment: diskAttachment)
        diskDevice.blockDeviceIdentifier = VMRuntimeDeviceDefaults.systemDiskIdentifier
        return [installerDevice, diskDevice]
    }

    private func metadataURL(for profile: VMProfile, pathExtension: String) throws -> URL {
        guard let virtualDiskPath = profile.virtualDiskPath else {
            throw VMRuntimeError.bootPrerequisitesMissing
        }

        return URL(fileURLWithPath: virtualDiskPath)
            .deletingPathExtension()
            .appendingPathExtension(pathExtension)
    }

    private func natNetworkDevice() -> VZVirtioNetworkDeviceConfiguration {
        let network = VZVirtioNetworkDeviceConfiguration()
        network.attachment = VZNATNetworkDeviceAttachment()
        return network
    }

    private func graphicsDevice() -> VZVirtioGraphicsDeviceConfiguration {
        let graphics = VZVirtioGraphicsDeviceConfiguration()
        graphics.scanouts = [
            VZVirtioGraphicsScanoutConfiguration(
                widthInPixels: VMRuntimeDeviceDefaults.graphicsWidthInPixels,
                heightInPixels: VMRuntimeDeviceDefaults.graphicsHeightInPixels
            )
        ]
        return graphics
    }

    private func clampedCPUCount(_ requestedCount: Int) -> Int {
        min(
            max(requestedCount, VZVirtualMachineConfiguration.minimumAllowedCPUCount),
            VZVirtualMachineConfiguration.maximumAllowedCPUCount
        )
    }

    private func clampedMemorySize(_ requestedMB: Int) -> UInt64 {
        let requestedBytes = UInt64(max(requestedMB, 1)) * 1_024 * 1_024
        return min(
            max(requestedBytes, VZVirtualMachineConfiguration.minimumAllowedMemorySize),
            VZVirtualMachineConfiguration.maximumAllowedMemorySize
        )
    }

    private static func runtimeState(from state: VZVirtualMachine.State) -> VMRuntimeState? {
        switch state {
        case .stopped:
            .stopped
        case .running:
            .running
        case .paused:
            .suspended
        case .error:
            .failed
        case .starting:
            .starting
        case .pausing, .resuming:
            .suspended
        case .stopping:
            .stopped
        case .saving, .restoring:
            .suspended
        @unknown default:
            .failed
        }
    }
}
