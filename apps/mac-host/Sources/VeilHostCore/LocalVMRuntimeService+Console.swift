import Foundation

extension LocalVMRuntimeService {
    static func automaticInstallAnswerFilePathIfExists(for profile: VMProfile) -> String? {
        let url = automaticInstallAnswerFileURL(for: profile)
        guard FileManager.default.fileExists(atPath: url.path) else {
            return nil
        }

        return url.path
    }

    static func automaticInstallMediaPathIfExists(for profile: VMProfile) -> String? {
        let url = automaticInstallMediaURL(for: profile)
        guard FileManager.default.fileExists(atPath: url.path) else {
            return nil
        }

        return url.path
    }

    private static func existingConsoleScreenshotPath(from launchRecord: QEMULaunchRecord?) -> String? {
        guard let path = launchRecord?.consoleScreenshotPath,
              !path.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              !protectedPathNeedsFilePicker(path, bookmarkData: nil),
              FileManager.default.fileExists(atPath: path) else {
            return nil
        }

        return path
    }

    static func qemuLaunchRuntimeState(
        from launchRecord: QEMULaunchRecord?,
        profile: VMProfile,
        processIsRunning: @Sendable (Int32) -> Bool
    ) -> VMRuntimeState? {
        guard let pid = launchRecord?.pid,
              let virtualDiskPath = profile.virtualDiskPath,
              launchRecord?.arguments.contains(where: { $0.contains(virtualDiskPath) }) == true,
              processIsRunning(pid) else {
            return nil
        }

        return .running
    }

    public static func processIsRunning(pid: Int32) -> Bool {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/ps")
        process.arguments = ["-p", String(pid)]
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice

        do {
            try process.run()
            process.waitUntilExit()
            return process.terminationStatus == 0
        } catch {
            return false
        }
    }

    public static func terminateProcess(pid: Int32) -> Bool {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/kill")
        process.arguments = ["-TERM", String(pid)]
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice

        do {
            try process.run()
            process.waitUntilExit()
            return process.terminationStatus == 0
        } catch {
            return false
        }
    }

    static func stopQEMULaunchIfRunning(
        _ launchRecord: QEMULaunchRecord?,
        profile: VMProfile,
        processIsRunning: @Sendable (Int32) -> Bool,
        processTerminator: @Sendable (Int32) -> Bool
    ) {
        guard let pid = launchRecord?.pid,
              let virtualDiskPath = profile.virtualDiskPath,
              launchRecord?.arguments.contains(where: { $0.contains(virtualDiskPath) }) == true,
              processIsRunning(pid) else {
            return
        }

        _ = processTerminator(pid)
    }

    struct ConsoleScreenshotRefresh {
        var path: String?
        var refreshedAt: Date?
    }

    struct ConsoleScreenshotFileEvidence: Equatable {
        var modifiedAt: Date?
        var byteCount: Int?
        var digest: UInt64?
    }

    func refreshedConsoleScreenshot(from launchRecord: QEMULaunchRecord?) -> ConsoleScreenshotRefresh {
        let existingPath = Self.existingConsoleScreenshotPath(from: launchRecord)
        if launchRecord?.vncHost?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false,
           launchRecord?.vncPort != nil {
            // VNC is the authoritative live surface. A monitor screendump is unclassified and can
            // overwrite a verified frame with black pixels while leaving the old visual state in
            // place, so only the VNC validation path may refresh this evidence.
            return ConsoleScreenshotRefresh(
                path: existingPath,
                refreshedAt: launchRecord?.consoleScreenshotRefreshedAt
            )
        }

        guard let path = existingPath,
              let monitorSocketPath = launchRecord?.monitorSocketPath,
              FileManager.default.fileExists(atPath: monitorSocketPath) else {
            return ConsoleScreenshotRefresh(
                path: existingPath,
                refreshedAt: nil
            )
        }

        let beforeEvidence = Self.consoleScreenshotFileEvidence(atPath: path)
        consoleScreenshotRefresher(
            URL(fileURLWithPath: monitorSocketPath),
            URL(fileURLWithPath: path)
        )
        let refreshedPath = Self.existingConsoleScreenshotPath(from: launchRecord) ?? path
        let afterEvidence = Self.consoleScreenshotFileEvidence(atPath: refreshedPath)
        let refreshedAt = Self.consoleScreenshotDidRefresh(
            before: beforeEvidence,
            after: afterEvidence
        ) ? diagnosticDate() : launchRecord?.consoleScreenshotRefreshedAt
        return ConsoleScreenshotRefresh(path: refreshedPath, refreshedAt: refreshedAt)
    }

    private static func consoleScreenshotFileEvidence(atPath path: String) -> ConsoleScreenshotFileEvidence? {
        let url = URL(fileURLWithPath: path)
        guard FileManager.default.fileExists(atPath: path) else {
            return nil
        }

        let values = try? url.resourceValues(forKeys: [.contentModificationDateKey, .fileSizeKey])
        let data = try? Data(contentsOf: url)
        return ConsoleScreenshotFileEvidence(
            modifiedAt: values?.contentModificationDate,
            byteCount: values?.fileSize ?? data?.count,
            digest: data.map(stableDigest)
        )
    }

    private static func consoleScreenshotDidRefresh(
        before: ConsoleScreenshotFileEvidence?,
        after: ConsoleScreenshotFileEvidence?
    ) -> Bool {
        guard let after else {
            return false
        }
        guard let before else {
            return true
        }
        return before != after
    }

    private static func stableDigest(for data: Data) -> UInt64 {
        data.reduce(0xcbf2_9ce4_8422_2325) { hash, byte in
            (hash ^ UInt64(byte)).multipliedReportingOverflow(by: 0x0000_0100_0000_01b3).partialValue
        }
    }

    static func consoleLaunchEvidence(
        from launchRecord: QEMULaunchRecord?,
        consoleScreenshotPath: String? = nil,
        consoleScreenshotRefreshedAt: Date? = nil
    ) -> VMConsoleLaunchEvidence? {
        guard let launchRecord else {
            return nil
        }

        return VMConsoleLaunchEvidence(
            provider: launchRecord.provider,
            pid: launchRecord.pid,
            processLogPath: launchRecord.processLogPath,
            monitorSocketPath: launchRecord.monitorSocketPath,
            qmpSocketPath: launchRecord.qmpSocketPath,
            vncHost: launchRecord.vncHost,
            vncPort: launchRecord.vncPort,
            consoleScreenshotPath: consoleScreenshotPath ?? existingConsoleScreenshotPath(from: launchRecord),
            consoleScreenshotRefreshedAt: consoleScreenshotRefreshedAt ?? launchRecord.consoleScreenshotRefreshedAt,
            consoleVisualState: launchRecord.consoleVisualState,
            consoleVisualStateAt: launchRecord.consoleVisualStateAt,
            previewStatus: consolePreviewStatus(
                consoleVisualState: launchRecord.consoleVisualState,
                consoleVisualStateAt: launchRecord.consoleVisualStateAt,
                consoleScreenshotPath: consoleScreenshotPath ?? existingConsoleScreenshotPath(from: launchRecord),
                consoleScreenshotRefreshedAt: consoleScreenshotRefreshedAt ?? launchRecord.consoleScreenshotRefreshedAt
            ),
            startedAt: launchRecord.startedAt
        )
    }

    private static func consolePreviewStatus(
        consoleVisualState: QEMUConsoleVisualState? = nil,
        consoleVisualStateAt: Date? = nil,
        consoleScreenshotPath: String?,
        consoleScreenshotRefreshedAt: Date?
    ) -> VMConsolePreviewStatus {
        guard consoleScreenshotPath != nil else {
            return .unavailable
        }

        // A live display smoke can successfully capture a frame while the guest has switched to a
        // blank graphics head. Treat that observation as stale so launch/recovery surfaces do not
        // tell the user that the console is healthy merely because a PNG exists on disk.
        if consoleVisualState == .blank {
            return .stale
        }

        // A monitor screendump can replace the PNG without classifying the new frame. Never pair
        // that newer image with an older successful VNC observation: the old state says nothing
        // about the pixels currently shown to the user.
        if let consoleVisualStateAt,
           let consoleScreenshotRefreshedAt,
           consoleVisualStateAt < consoleScreenshotRefreshedAt {
            return .stale
        }

        return consoleScreenshotRefreshedAt == nil ? .stale : .fresh
    }
}
