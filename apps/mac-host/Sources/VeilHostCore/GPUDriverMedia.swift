import Foundation

/// The disc that carries Triton's GPU driver into Windows (`gpu.driver.install.request`).
///
/// The package comes from the GPU runtime (`RuntimeGPU/guest-driver/viogpu3d`), where
/// `script/bundle_gpu_runtime.sh` put it after checking the release archive against its pinned SHA-256.
/// The agent's elevated script checks the catalog and INF again inside Windows before installing.
public enum GPUDriverMedia {
    public static let fileName = "VeilGPUDriver.iso"
    /// The label the agent looks for (`GpuDriverInstall.VolumeLabel`).
    public static let volumeName = "VEIL_GPU"
    public static let packageFolder = "viogpu3d"
    public static let infFileName = "viogpu3d.inf"

    public static func build(
        packageDirectory: URL,
        mediaURL: URL,
        processRunner: (String, [String]) throws -> Int32 = HdiutilAutomaticInstallMediaBuilder.runProcess
    ) throws {
        let fileManager = FileManager.default
        guard fileManager.fileExists(atPath: packageDirectory.appendingPathComponent(infFileName).path) else {
            throw VMRuntimeError.automaticInstallMediaCreationFailed("The GPU runtime has no \(packageFolder)\\\(infFileName).")
        }
        let buildID = UUID().uuidString
        let parentURL = mediaURL.deletingLastPathComponent()
        try fileManager.createDirectory(at: parentURL, withIntermediateDirectories: true)
        let stagingURL = parentURL.appendingPathComponent(".veil-gpu-driver-\(buildID)", isDirectory: true)
        defer {
            try? fileManager.removeItem(at: stagingURL)
        }
        try fileManager.createDirectory(at: stagingURL, withIntermediateDirectories: true)
        try fileManager.copyItem(at: packageDirectory, to: stagingURL.appendingPathComponent(packageFolder, isDirectory: true))

        let outputURL = parentURL.appendingPathComponent(".veil-gpu-driver-\(buildID).iso")
        defer {
            try? fileManager.removeItem(at: outputURL)
        }
        let exitCode = try processRunner(
            "/usr/bin/hdiutil",
            ["makehybrid", "-iso", "-joliet", "-default-volume-name", volumeName, "-o", outputURL.path, stagingURL.path]
        )
        guard exitCode == 0, fileManager.fileExists(atPath: outputURL.path) else {
            throw VMRuntimeError.automaticInstallMediaCreationFailed("hdiutil could not build the GPU driver disc (exit \(exitCode)).")
        }
        try? fileManager.removeItem(at: mediaURL)
        try fileManager.moveItem(at: outputURL, to: mediaURL)
    }
}

extension QEMUGPURuntime {
    /// Triton's Windows driver package inside the runtime.
    public static let driverPackage = "guest-driver/viogpu3d"

    public var driverPackageDirectory: URL {
        directory.appendingPathComponent(Self.driverPackage, isDirectory: true)
    }

    /// Whether a launch ran on this runtime, so installing the driver cannot take the display away.
    public static func launchUsesGPURuntime(_ record: QEMULaunchRecord) -> Bool {
        record.arguments.contains { $0.hasPrefix("virtio-ramfb-gl,") && $0.contains("neptune=true") }
    }
}

public enum GPUDriverMediaError: Error, LocalizedError, Equatable {
    case notOnGPURuntime
    case runtimeMissing

    public var errorDescription: String? {
        switch self {
        case .notOnGPURuntime:
            "Windows is not running with GPU acceleration. Turn it on in Configuration > Hardware > Graphics, shut Windows down, and start it again before installing the GPU driver."
        case .runtimeMissing:
            "This copy of Veil does not include the GPU runtime or its Windows driver."
        }
    }
}

extension LocalVMRuntimeService {
    /// Builds the GPU driver disc and puts it in the running Windows' removable drive. Refused unless
    /// Windows runs on the GPU runtime: on the software runtime the driver would leave it with no display.
    public func insertGPUDriverMedia() async throws -> VMRemovableMediaStatus {
        try await insertGPUDriverMedia(runtime: QEMUGPURuntime.bundled())
    }

    func insertGPUDriverMedia(runtime: QEMUGPURuntime?) async throws -> VMRemovableMediaStatus {
        guard let record = try await qemuLaunchRecordStore.loadLatest(),
              let pid = record.pid, qemuLaunchProcessIsRunning(pid),
              QEMUGPURuntime.launchUsesGPURuntime(record) else {
            throw GPUDriverMediaError.notOnGPURuntime
        }
        guard let runtime,
              FileManager.default.fileExists(atPath: runtime.driverPackageDirectory.appendingPathComponent(GPUDriverMedia.infFileName).path),
              let profile = try await profileStore.load() else {
            throw GPUDriverMediaError.runtimeMissing
        }
        let mediaURL = URL(fileURLWithPath: profile.sharedFolderPath).appendingPathComponent(GPUDriverMedia.fileName)
        try GPUDriverMedia.build(packageDirectory: runtime.driverPackageDirectory, mediaURL: mediaURL)
        return try await insertRemovableMedia(path: mediaURL.path)
    }

    /// See `RFBDesktopSizeForwarder`: viogpu3d switches only to a size QEMU passed to the device first.
    public func forwardDisplaySizeToGPU(width: Int, height: Int) async -> Bool {
        guard let record = try? await qemuLaunchRecordStore.loadLatest(),
              let pid = record.pid, qemuLaunchProcessIsRunning(pid),
              QEMUGPURuntime.launchUsesGPURuntime(record),
              let socketPath = record.vncSocketPath else {
            return false
        }
        let response = await Task.detached {
            RFBDesktopSizeForwarder.forward(width: width, height: height, unixSocketPath: socketPath)
        }.value
        return response.map { $0.isForwardedToGuest || $0.isSuccess } ?? false
    }
}
