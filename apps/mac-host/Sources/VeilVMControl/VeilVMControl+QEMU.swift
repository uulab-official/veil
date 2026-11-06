import Foundation
import Darwin
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers
import Vision
import VeilHostCore

extension VeilVMControl {
    static func printQEMUDoctor(json: Bool) async throws {
        let profile = try await JSONVMProfileStore().load()
        let plan = try? profile.map(makeQEMUPlan(for:))
        let report = QEMUWindowsReadinessDoctor().makeReport(
            profile: profile,
            plan: plan
        )

        if json {
            let data = try JSONEncoder.veilDiagnostics.encode(report)
            print(String(decoding: data, as: UTF8.self))
            return
        }

        print("QEMU/HVF readiness: \(report.overallState.rawValue)")
        for check in report.checks {
            print("\(check.title): \(check.state.rawValue)")
            print("  \(check.detail)")
        }
        print("Next actions:")
        for action in report.nextActions {
            print("  - \(action)")
        }
    }

    static func printQEMUInstallStatus(json: Bool) async throws {
        let snapshot = try await LocalVMRuntimeService().loadSnapshot()
        let report = snapshot.windowsInstallStatusReport()

        if json {
            let data = try JSONEncoder.veilDiagnostics.encode(report)
            print(String(decoding: data, as: UTF8.self))
            return
        }

        print("Windows install status: \(report.installEvidence.title)")
        print("State: \(report.state.rawValue)")
        print("Profile: \(report.profileName ?? "Not configured")")
        print("Boot ready: \(report.bootReady ? "yes" : "no")")
        print("Windows installed: \(report.windowsInstalled ? "yes" : "no")")
        print("Installer: \(report.installerMediaPath ?? "Not selected")")
        print("Drivers: \(report.driverMediaPath ?? "Not selected")")
        print("Virtual disk: \(report.virtualDiskPath ?? "Not selected")")
        print("Guest tools media: \(report.automaticInstallMediaStatus.state.rawValue)")
        print("Guest tools media detail: \(report.automaticInstallMediaStatus.detail)")
        if let rebuildCommand = report.automaticInstallMediaStatus.rebuildCommand,
           report.automaticInstallMediaStatus.recommendedAction != "none" {
            print("Guest tools media rebuild: \(rebuildCommand)")
        }
        print("Console screenshot: \(report.latestConsoleScreenshotPath ?? "Not captured")")
        print("Display surface: \(report.displaySurface.kind.rawValue)")
        print("Display size: \(report.displaySurface.plannedWidthInPixels)x\(report.displaySurface.plannedHeightInPixels)")
        print("Display scaling: \(report.displaySurface.scalingMode)")
        print("Dynamic resolution: \(report.displaySurface.dynamicResolution)")
        print("Retina scaling: \(report.displaySurface.retinaScaling)")
        if let endpoint = report.displaySurface.endpoint {
            print("Display endpoint: \(endpoint)")
        }
        if let validationCommand = report.displaySurface.validationCommand {
            print("Display validation: \(validationCommand)")
        }
        if let launch = report.latestConsoleLaunch {
            print("Latest QEMU PID: \(launch.pid.map(String.init) ?? "unknown")")
        }
        print("Detail: \(report.installEvidence.detail)")
        print("Next actions:")
        for action in report.nextActions {
            print("  - \(action)")
        }
    }

    static func printExportDiagnostics(json: Bool, outputPath: String?) async throws {
        let generatedURL = try await LocalVMRuntimeService().exportDiagnostics(to: diagnosticsDirectory())

        var finalURL = generatedURL
        if let outputPath {
            let destinationURL = URL(fileURLWithPath: outputPath)
            try FileManager.default.createDirectory(
                at: destinationURL.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            let data = try Data(contentsOf: generatedURL)
            try data.write(to: destinationURL, options: [.atomic])
            finalURL = destinationURL
        }

        let data = try Data(contentsOf: finalURL)
        if json {
            print(String(decoding: data, as: UTF8.self))
            return
        }

        let bundle = try JSONDecoder.veilDiagnostics.decode(VMRuntimeDiagnosticBundle.self, from: data)
        print("Diagnostics generated at: \(ISO8601DateFormatter().string(from: bundle.generatedAt))")
        print("Saved to: \(finalURL.path)")
        print("Host: \(bundle.host.architecture), \(bundle.host.processorCount) CPUs, \(bundle.host.physicalMemoryBytes / 1_024 / 1_024) MB RAM, \(bundle.host.operatingSystemVersion)")
        print("Profile: \(bundle.profile?.name ?? "Not configured")")
        print("Runtime state: \(bundle.snapshot.state.rawValue)")
        if let lastBootReport = bundle.lastBootReport {
            print("Last boot result: \(lastBootReport.result.rawValue)")
        } else {
            print("Last boot result: none recorded")
        }
    }

    static func printQEMUSmoke(json: Bool, seconds: Int) async throws {
        guard let profile = try await JSONVMProfileStore().load() else {
            throw VMControlError.missingProfileForQEMUPlan
        }

        let boundedSeconds = min(max(seconds, 5), 120)
        let plan = try makeQEMUPlan(for: profile)
        let logDirectory = diagnosticsDirectory()
            .appendingPathComponent("QEMU Smoke", isDirectory: true)
        try FileManager.default.createDirectory(
            at: logDirectory,
            withIntermediateDirectories: true
        )
        let stamp = ISO8601DateFormatter()
            .string(from: Date())
            .replacingOccurrences(of: ":", with: "-")
        let serialLogURL = logDirectory.appendingPathComponent("qemu-smoke-\(stamp).serial.log")
        let processLogURL = logDirectory.appendingPathComponent("qemu-smoke-\(stamp).process.log")
        let consoleScreenshotURL = logDirectory.appendingPathComponent("qemu-smoke-\(stamp).console.png")
        let monitorSocketURL = URL(fileURLWithPath: "/tmp")
            .appendingPathComponent("veil-qemu-smoke-\(UUID().uuidString.prefix(8)).sock")
        let qmpSocketURL = URL(fileURLWithPath: "/tmp")
            .appendingPathComponent("veil-qemu-smoke-\(UUID().uuidString.prefix(8)).qmp.sock")
        let arguments = QEMUWindowsBootSmokePlanner().makeArguments(
            from: plan,
            serialLogPath: serialLogURL.path,
            monitorSocketPath: monitorSocketURL.path,
            qmpSocketPath: qmpSocketURL.path
        )
        try QEMUVMRuntimeBooter.startTPMEmulatorIfNeeded(plan: plan)

        let processOutput = try runBoundedQEMU(
            executablePath: plan.executablePath,
            arguments: arguments,
            seconds: boundedSeconds,
            processLogURL: processLogURL,
            monitorSocketURL: monitorSocketURL,
            consoleScreenshotURL: consoleScreenshotURL
        )
        try? FileManager.default.removeItem(at: monitorSocketURL)
        try? FileManager.default.removeItem(at: qmpSocketURL)
        let serialOutput = (try? String(contentsOf: serialLogURL, encoding: .utf8)) ?? ""
        let report = QEMUWindowsBootSmokeAnalyzer.makeReport(
            durationSeconds: boundedSeconds,
            processOutput: processOutput.output,
            serialOutput: serialOutput,
            didRemainRunningUntilTimeout: processOutput.didRemainRunningUntilTimeout,
            serialLogPath: serialLogURL.path,
            processLogPath: processLogURL.path,
            consoleScreenshotPath: consoleScreenshotURL.path,
            runEvidence: processOutput.bootPromptKeySendCount > 0 ? ["boot-prompt-key-sent"] : []
        )

        if json {
            let data = try JSONEncoder.veilDiagnostics.encode(report)
            print(String(decoding: data, as: UTF8.self))
            return
        }

        print("QEMU/HVF smoke: \(report.outcome.rawValue)")
        print(report.detail)
        print("Evidence: \(report.evidence.joined(separator: ", "))")
        print("Serial log: \(report.serialLogPath)")
        print("Process log: \(report.processLogPath)")
        print("Console screenshot: \(report.consoleScreenshotPath)")
        print("Next actions:")
        for action in report.nextActions {
            print("  - \(action)")
        }
    }

    static func startQEMU(
        json: Bool,
        waitSeconds: Int,
        displayMode: VMControlArguments.QEMUStartDisplayMode
    ) async throws {
        guard let profile = try await JSONVMProfileStore().load() else {
            throw VMControlError.missingProfileForQEMUPlan
        }
        try rejectDuplicateQEMULaunchIfNeeded(for: profile)

        let plan = try makeQEMUPlan(for: profile)
        let readiness = QEMUWindowsReadinessDoctor().makeReport(
            profile: profile,
            plan: plan
        )
        guard readiness.overallState == .ready else {
            throw VMControlError.qemuNotReady(readiness.nextActions)
        }
        if displayMode == .nativeCocoa {
            let availableBackends = QEMUDisplayBackendProbe.availableBackends(
                executablePath: plan.executablePath
            )
            guard availableBackends.contains("cocoa") else {
                throw VMControlError.qemuDisplayBackendUnavailable(
                    requested: "Cocoa",
                    executablePath: plan.executablePath,
                    availableBackends: availableBackends
                )
            }
        }
        let shouldSendInstallerBootKey = QEMUWindowsInstallerBootPolicy.shouldSendBootKey(
            profile: profile,
            virtualDiskAllocatedBytes: QEMUWindowsInstallerBootPolicy.allocatedFileSize(path: profile.virtualDiskPath)
        )

        let logDirectory = diagnosticsDirectory()
            .appendingPathComponent("QEMU Launch", isDirectory: true)
        try FileManager.default.createDirectory(
            at: logDirectory,
            withIntermediateDirectories: true
        )
        let stamp = ISO8601DateFormatter()
            .string(from: Date())
            .replacingOccurrences(of: ":", with: "-")
        let processLogURL = logDirectory.appendingPathComponent("qemu-launch-\(stamp).log")
        let serialLogURL = logDirectory.appendingPathComponent("qemu-launch-\(stamp).serial.log")
        let consoleScreenshotURL = logDirectory.appendingPathComponent("qemu-console-\(stamp).png")
        let qemuPIDURL = logDirectory.appendingPathComponent("qemu-launch-\(stamp).pid")
        let monitorSocketURL = URL(fileURLWithPath: "/tmp")
            .appendingPathComponent("vq-\(UUID().uuidString.prefix(8)).sock")
        let qmpSocketURL = URL(fileURLWithPath: "/tmp")
            .appendingPathComponent("vq-\(UUID().uuidString.prefix(8)).qmp.sock")
        let bootDisplayMode: QEMUWindowsBootDisplayMode = displayMode == .embedded
            ? .vncLoopback
            : .nativeCocoa
        let vncPort = displayMode == .embedded ? QEMUVMRuntimeBooter.allocateLoopbackVNCPort() : nil
        if displayMode == .embedded, vncPort == nil {
            throw VMControlError.qemuDisplayPortUnavailable
        }
        let vncDisplay = vncPort.map { max($0 - 5_900, 0) }
        FileManager.default.createFile(atPath: processLogURL.path, contents: nil)
        let logHandle = try FileHandle(forWritingTo: processLogURL)
        let launchArguments = QEMUWindowsBootLaunchPlanner().makeArguments(
            from: plan,
            serialLogPath: serialLogURL.path,
            monitorSocketPath: monitorSocketURL.path,
            qmpSocketPath: qmpSocketURL.path,
            bootDiskFirst: !shouldSendInstallerBootKey,
            displayMode: bootDisplayMode,
            vncDisplay: vncDisplay
        )

        try? FileManager.default.removeItem(at: qemuPIDURL)
        let process = Process()
        // UTM's QEMU launcher intentionally watches its parent and exits when that parent exits. The
        // CLI must return after handing the VM to the host display, so keep a tiny shell supervisor as
        // QEMU's parent instead of making the short-lived veil-vmctl process the watched parent.
        process.executableURL = URL(fileURLWithPath: "/bin/sh")
        process.arguments = [
            "-c",
            qemuLaunchSupervisorCommand(
                executablePath: plan.executablePath,
                arguments: launchArguments,
                qemuPIDPath: qemuPIDURL.path
            )
        ]
        process.standardOutput = logHandle
        process.standardError = logHandle
        try QEMUVMRuntimeBooter.startTPMEmulatorIfNeeded(plan: plan)
        try process.run()
        if bootDisplayMode == .nativeCocoa {
            bringQEMUToFrontIfAllowed()
        }
        driveInitialQEMULaunch(
            process: process,
            waitSeconds: waitSeconds,
            shouldSendInstallerBootKey: shouldSendInstallerBootKey,
            monitorSocketURL: monitorSocketURL
        )
        guard isProcessRunning(pid: process.processIdentifier),
              let qemuPID = await waitForQEMUPID(
                  at: qemuPIDURL,
                  timeoutSeconds: 5
              ),
              isProcessRunning(pid: qemuPID) else {
            throw VMControlError.qemuLaunchExited(
                pid: process.processIdentifier,
                terminationStatus: process.terminationStatus,
                processLogPath: processLogURL.path
            )
        }

        let record = QEMULaunchRecord(
            provider: plan.provider,
            pid: qemuPID,
            executablePath: plan.executablePath,
            arguments: launchArguments,
            displayMode: bootDisplayMode,
            processLogPath: processLogURL.path,
            monitorSocketPath: monitorSocketURL.path,
            qmpSocketPath: qmpSocketURL.path,
            vncHost: vncPort == nil ? nil : "127.0.0.1",
            vncPort: vncPort,
            consoleScreenshotPath: consoleScreenshotURL.path,
            startedAt: Date()
        )
        try writeQEMULaunchRecord(record, directory: logDirectory, stamp: stamp)

        if json {
            let data = try JSONEncoder.veilDiagnostics.encode(record)
            print(String(decoding: data, as: UTF8.self))
            return
        }

        print("QEMU/HVF Windows VM launched")
        print("PID: \(record.pid.map(String.init) ?? "unknown")")
        print("Executable: \(record.executablePath)")
        print("Process log: \(record.processLogPath)")
        print("Serial log: \(serialLogURL.path)")
        print("Monitor socket: \(record.monitorSocketPath)")
        print("QMP socket: \(record.qmpSocketPath ?? "not attached")")
        print("Display mode: \(record.displayMode?.rawValue ?? "unknown")")
        if let vncHost = record.vncHost, let vncPort = record.vncPort {
            print("VNC display: \(vncHost):\(vncPort)")
        }
        print("Console screenshot: \(record.consoleScreenshotPath ?? "pending")")
    }

    private static func writeQEMULaunchRecord(
        _ record: QEMULaunchRecord,
        directory: URL,
        stamp: String
    ) throws {
        let data = try JSONEncoder.veilDiagnostics.encode(record)
        try data.write(to: directory.appendingPathComponent("qemu-launch-\(stamp).json"), options: .atomic)
        try data.write(to: directory.appendingPathComponent("qemu-launch-latest.json"), options: .atomic)
    }

    static func smokeQEMUDisplay(json: Bool, waitSeconds: Int) async throws {
        let launchRecord = try latestQEMULaunchRecord()
        guard let host = launchRecord.vncHost?.trimmingCharacters(in: .whitespacesAndNewlines),
              !host.isEmpty,
              let port = launchRecord.vncPort else {
            throw VMControlError.missingQEMUDisplayEndpoint
        }

        let boundedWaitSeconds = min(max(waitSeconds, 1), 30)
        let deadline = Date().addingTimeInterval(TimeInterval(boundedWaitSeconds))
        var attempt = 0
        var snapshot: QEMUConsoleVisualSnapshot?
        var lastError: Error?

        // VNC can expose a valid framebuffer before the guest has painted its first
        // usable frame. Keep sampling blank/transiently unavailable observations for
        // the requested bound so boot timing does not become a false display failure.
        repeat {
            attempt += 1
            do {
                let candidate = try qemuConsoleVisualSnapshot(
                    phase: "display-smoke",
                    attempt: attempt,
                    referenceFrame: nil
                )
                snapshot = candidate
                if candidate.observation.state != .blank {
                    break
                }
            } catch {
                lastError = error
            }

            let remainingSeconds = min(1, deadline.timeIntervalSinceNow)
            if remainingSeconds > 0 {
                let remainingNanoseconds = UInt64(remainingSeconds * 1_000_000_000)
                try? await Task.sleep(nanoseconds: remainingNanoseconds)
            }
        } while Date() < deadline

        guard let snapshot else {
            throw lastError ?? VMControlError.missingQEMUDisplayEndpoint
        }
        let frame = snapshot.frame
        guard let metrics = snapshot.observation.metrics else {
            throw VMControlError.qemuScreenshotCaptureFailed(
                snapshot.observation.screenshotPath ?? "QEMU VNC frame"
            )
        }

        let record = QEMUDisplaySmokeRecord(
            pid: launchRecord.pid,
            endpoint: "\(host):\(port)",
            width: frame.width,
            height: frame.height,
            frameSequence: frame.sequence,
            pixelByteCount: frame.rgbaPixels.count,
            visualState: snapshot.observation.state,
            frameMetrics: metrics,
            recognizedText: snapshot.observation.recognizedText,
            screenshotPath: snapshot.observation.screenshotPath,
            waitedSeconds: boundedWaitSeconds,
            capturedAt: Date()
        )

        // Keep the latest launch record aligned with the live display observation. Without this,
        // VMRuntimeModel sees only the existence of a recently written PNG and reports `fresh` even
        // when VNC returned a completely blank graphics head.
        var observedLaunchRecord = launchRecord
        observedLaunchRecord.consoleScreenshotPath = snapshot.observation.screenshotPath
        observedLaunchRecord.consoleScreenshotRefreshedAt = snapshot.observation.capturedAt
        observedLaunchRecord.consoleVisualState = snapshot.observation.state
        observedLaunchRecord.consoleVisualStateAt = snapshot.observation.capturedAt
        let launchDirectory = diagnosticsDirectory()
            .appendingPathComponent("QEMU Launch", isDirectory: true)
        let latestLaunchURL = launchDirectory.appendingPathComponent("qemu-launch-latest.json")
        let launchData = try JSONEncoder.veilDiagnostics.encode(observedLaunchRecord)
        try launchData.write(to: latestLaunchURL, options: .atomic)

        if json {
            let data = try JSONEncoder.veilDiagnostics.encode(record)
            print(String(decoding: data, as: UTF8.self))
            return
        }

        print("QEMU embedded display smoke passed")
        print("PID: \(record.pid.map(String.init) ?? "unknown")")
        print("Endpoint: \(record.endpoint)")
        print("Frame: \(record.width)x\(record.height) #\(record.frameSequence)")
        print("RGBA bytes: \(record.pixelByteCount)")
        print("Visual state: \(record.visualState.rawValue)")
        print("Screenshot: \(record.screenshotPath ?? "not captured")")
    }

    static func captureQEMUConsole(json: Bool, outputPath: String?) async throws {
        let captureRecord = try captureLatestQEMUConsole(outputPath: outputPath)
        if json {
            let captureData = try JSONEncoder.veilDiagnostics.encode(captureRecord)
            print(String(decoding: captureData, as: UTF8.self))
            return
        }

        print("QEMU console screenshot captured")
        print("Monitor socket: \(captureRecord.monitorSocketPath)")
        print("Console screenshot: \(captureRecord.consoleScreenshotPath)")
    }

    static func captureLatestQEMUConsole(outputPath: String? = nil) throws -> QEMUConsoleCaptureRecord {
        let directory = diagnosticsDirectory()
            .appendingPathComponent("QEMU Launch", isDirectory: true)
        let latestURL = directory.appendingPathComponent("qemu-launch-latest.json")
        guard FileManager.default.fileExists(atPath: latestURL.path) else {
            throw VMControlError.missingQEMULaunchRecord
        }

        let data = try Data(contentsOf: latestURL)
        var launchRecord = try JSONDecoder.veilDiagnostics.decode(QEMULaunchRecord.self, from: data)
        guard FileManager.default.fileExists(atPath: launchRecord.monitorSocketPath) else {
            throw VMControlError.qemuMonitorUnavailable(launchRecord.monitorSocketPath)
        }

        let screenshotURL: URL
        if let outputPath,
           !outputPath.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            screenshotURL = URL(fileURLWithPath: outputPath)
        } else if let path = launchRecord.consoleScreenshotPath,
                  !path.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            screenshotURL = URL(fileURLWithPath: path)
        } else {
            let stamp = ISO8601DateFormatter()
                .string(from: Date())
                .replacingOccurrences(of: ":", with: "-")
            screenshotURL = directory.appendingPathComponent("qemu-console-\(stamp).png")
        }

        try FileManager.default.createDirectory(
            at: screenshotURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        QEMUVMRuntimeBooter.captureConsoleScreenshot(
            monitorSocketURL: URL(fileURLWithPath: launchRecord.monitorSocketPath),
            imageURL: screenshotURL
        )
        guard FileManager.default.fileExists(atPath: screenshotURL.path) else {
            throw VMControlError.qemuScreenshotCaptureFailed(screenshotURL.path)
        }

        let capturedAt = Date()
        launchRecord.consoleScreenshotPath = screenshotURL.path
        launchRecord.consoleScreenshotRefreshedAt = capturedAt
        let launchData = try JSONEncoder.veilDiagnostics.encode(launchRecord)
        try launchData.write(to: latestURL, options: .atomic)

        let captureRecord = QEMUConsoleCaptureRecord(
            monitorSocketPath: launchRecord.monitorSocketPath,
            consoleScreenshotPath: screenshotURL.path,
            capturedAt: capturedAt
        )
        return captureRecord
    }

    static func qemuConsoleVisualSnapshot(
        phase: String,
        attempt: Int,
        referenceFrame: RFBRenderedFrame?,
        recognizeText: Bool = true
    ) throws -> QEMUConsoleVisualSnapshot {
        let launchRecord = try latestQEMULaunchRecord()
        guard let host = launchRecord.vncHost?.trimmingCharacters(in: .whitespacesAndNewlines),
              !host.isEmpty,
              let port = launchRecord.vncPort else {
            throw VMControlError.missingQEMUDisplayEndpoint
        }

        let socket = try RFBLoopbackSocket(host: host, port: port, timeoutSeconds: 3)
        defer { socket.close() }
        let client = RFBFrameStreamClient(stream: socket)
        let serverInit = try client.startSharedSession()
        let renderer = try RFBFramebufferRenderer(serverInit: serverInit)
        try client.requestFramebufferUpdate(incremental: false)
        var update = try client.readUpdateEvent()
        // A server that supports dynamic resolution answers the first full refresh
        // with an ExtendedDesktopSize rectangle; keep reading for the pixel data.
        if case .desktopSize = update {
            update = try client.readUpdateEvent()
        }
        guard case .framebuffer(let framebufferUpdate) = update else {
            throw VMControlError.missingQEMUDisplayEndpoint
        }
        let frame = try renderer.apply(framebufferUpdate)
        let metrics = try QEMUConsoleFrameAnalyzer.analyze(
            width: frame.width,
            height: frame.height,
            rgbaPixels: frame.rgbaPixels
        )
        let recognizedText = metrics.isBlank || !recognizeText
            ? []
            : qemuConsoleRecognizedText(frame: frame)
        let state = QEMUConsoleVisualStateClassifier.classify(
            metrics: metrics,
            recognizedText: recognizedText
        )
        let difference = try referenceFrame.map {
            try QEMUConsoleFrameAnalyzer.difference(from: $0, to: frame)
        }
        let screenshotURL = diagnosticsDirectory()
            .appendingPathComponent("QEMU Launch", isDirectory: true)
            .appendingPathComponent("qemu-readiness-\(qemuSafePhaseName(phase))-latest.png")
        try writeQEMUConsolePNG(frame: frame, to: screenshotURL)

        return QEMUConsoleVisualSnapshot(
            frame: frame,
            observation: QEMUConsoleVisualObservation(
                phase: phase,
                attempt: attempt,
                capturedAt: Date(),
                source: "vnc",
                screenshotPath: screenshotURL.path,
                state: state,
                recognizedText: Array(recognizedText.prefix(24)),
                metrics: metrics,
                differenceFromReference: difference,
                wakeKeySent: false,
                errorMessage: nil
            )
        )
    }

    static func waitForQEMUConsoleReadiness(
        phase: String,
        timeoutSeconds: Int,
        referenceFrame: RFBRenderedFrame?,
        expectedStates: [QEMUConsoleVisualState],
        acceptMeaningfulChange: Bool,
        wakeWhenBlank: Bool,
        recognizeText: Bool = true
    ) async -> (report: QEMUConsoleReadinessReport, snapshot: QEMUConsoleVisualSnapshot?) {
        let boundedTimeout = min(max(timeoutSeconds, 1), 30)
        let deadline = Date().addingTimeInterval(TimeInterval(boundedTimeout))
        var observations: [QEMUConsoleVisualObservation] = []
        var latestSnapshot: QEMUConsoleVisualSnapshot?
        var attempt = 0
        var didSendWakeKey = false

        repeat {
            attempt += 1
            do {
                var snapshot = try qemuConsoleVisualSnapshot(
                    phase: phase,
                    attempt: attempt,
                    referenceFrame: referenceFrame,
                    recognizeText: recognizeText
                )
                let isExpectedState = expectedStates.contains(snapshot.observation.state)
                let hasAcceptedChange = acceptMeaningfulChange
                    && snapshot.observation.differenceFromReference?.hasMeaningfulChange == true
                    && snapshot.observation.state != .blank
                if isExpectedState || hasAcceptedChange {
                    observations.append(snapshot.observation)
                    return (
                        QEMUConsoleReadinessReport(
                            phase: phase,
                            status: .ready,
                            expectedStates: expectedStates,
                            timeoutSeconds: boundedTimeout,
                            attempts: attempt,
                            observations: observations
                        ),
                        snapshot
                    )
                }

                if wakeWhenBlank,
                   snapshot.observation.state == .blank,
                   !didSendWakeKey {
                    _ = try? await qemuKeySendRecord(steps: [
                        QEMUKeySequenceStep(key: "esc", delayAfterSend: 0.2),
                        QEMUKeySequenceStep(key: "shift", delayAfterSend: 0.2)
                    ])
                    snapshot.observation.wakeKeySent = true
                    didSendWakeKey = true
                }
                observations.append(snapshot.observation)
                latestSnapshot = snapshot
            } catch {
                observations.append(QEMUConsoleVisualObservation(
                    phase: phase,
                    attempt: attempt,
                    capturedAt: Date(),
                    source: "vnc",
                    screenshotPath: nil,
                    state: .unknown,
                    recognizedText: [],
                    metrics: nil,
                    differenceFromReference: nil,
                    wakeKeySent: false,
                    errorMessage: error.localizedDescription
                ))
            }

            if Date() < deadline {
                try? await Task.sleep(nanoseconds: 1_000_000_000)
            }
        } while Date() < deadline

        let status: QEMUConsoleReadinessStatus = observations.allSatisfy { $0.errorMessage != nil }
            ? .unavailable
            : .timedOut
        return (
            QEMUConsoleReadinessReport(
                phase: phase,
                status: status,
                expectedStates: expectedStates,
                timeoutSeconds: boundedTimeout,
                attempts: attempt,
                observations: observations
            ),
            latestSnapshot
        )
    }

    static func mergeQEMUConsoleReadinessReports(
        _ first: (report: QEMUConsoleReadinessReport, snapshot: QEMUConsoleVisualSnapshot?),
        _ second: (report: QEMUConsoleReadinessReport, snapshot: QEMUConsoleVisualSnapshot?)
    ) -> (report: QEMUConsoleReadinessReport, snapshot: QEMUConsoleVisualSnapshot?) {
        let status = second.report.status == .ready ? .ready : second.report.status
        return (
            QEMUConsoleReadinessReport(
                phase: first.report.phase,
                status: status,
                expectedStates: first.report.expectedStates,
                timeoutSeconds: first.report.timeoutSeconds + second.report.timeoutSeconds,
                attempts: first.report.attempts + second.report.attempts,
                observations: first.report.observations + second.report.observations
            ),
            second.snapshot ?? first.snapshot
        )
    }

    static func qemuSkippedConsoleReadinessReport(phase: String) -> QEMUConsoleReadinessReport {
        QEMUConsoleReadinessReport(
            phase: phase,
            status: .skipped,
            expectedStates: [],
            timeoutSeconds: 0,
            attempts: 0,
            observations: []
        )
    }

    static func mergedQEMUKeySendRecord(
        _ records: [QEMUKeySendRecord]
    ) async throws -> QEMUKeySendRecord {
        guard let first = records.first else {
            return try await qemuKeySendRecord(steps: [])
        }
        return QEMUKeySendRecord(
            monitorSocketPath: first.monitorSocketPath,
            keys: records.flatMap(\.keys),
            results: records.flatMap(\.results),
            sentAt: records.last?.sentAt ?? first.sentAt
        )
    }

    private static func qemuConsoleRecognizedText(frame: RFBRenderedFrame) -> [String] {
        guard let image = qemuConsoleCGImage(frame: frame) else {
            return []
        }
        let request = VNRecognizeTextRequest()
        // The fast recognizer only reads Latin script: on a Korean Windows it turned the UAC prompt
        // into noise plus "Windows PowerShell", so the prompt was never approved and timed out.
        request.recognitionLevel = .accurate
        request.usesLanguageCorrection = false
        request.recognitionLanguages = ["ko-KR", "en-US"]
        do {
            try VNImageRequestHandler(cgImage: image, orientation: .up).perform([request])
            return (request.results ?? []).compactMap {
                $0.topCandidates(1).first?.string.trimmingCharacters(in: .whitespacesAndNewlines)
            }.filter { !$0.isEmpty }
        } catch {
            return []
        }
    }

    private static func writeQEMUConsolePNG(frame: RFBRenderedFrame, to url: URL) throws {
        guard let image = qemuConsoleCGImage(frame: frame) else {
            throw VMControlError.qemuScreenshotCaptureFailed(url.path)
        }
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        guard let destination = CGImageDestinationCreateWithURL(
            url as CFURL,
            UTType.png.identifier as CFString,
            1,
            nil
        ) else {
            throw VMControlError.qemuScreenshotCaptureFailed(url.path)
        }
        CGImageDestinationAddImage(destination, image, nil)
        guard CGImageDestinationFinalize(destination) else {
            throw VMControlError.qemuScreenshotCaptureFailed(url.path)
        }
    }

    private static func qemuConsoleCGImage(frame: RFBRenderedFrame) -> CGImage? {
        guard frame.width > 0,
              frame.height > 0,
              frame.rgbaPixels.count >= frame.width * frame.height * 4,
              let provider = CGDataProvider(data: frame.rgbaPixels as CFData),
              let colorSpace = CGColorSpace(name: CGColorSpace.sRGB) else {
            return nil
        }
        return CGImage(
            width: frame.width,
            height: frame.height,
            bitsPerComponent: 8,
            bitsPerPixel: 32,
            bytesPerRow: frame.width * 4,
            space: colorSpace,
            bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.last.rawValue),
            provider: provider,
            decode: nil,
            shouldInterpolate: false,
            intent: .defaultIntent
        )
    }
}
