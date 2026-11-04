import Foundation

public protocol VMRuntimeService: Sendable {
    func loadSnapshot() async throws -> VMRuntimeSnapshot
    func prepareDefaultVM() async throws -> VMRuntimeSnapshot
    func createDefaultProfile() async throws -> VMRuntimeSnapshot
    func createDefaultVirtualDisk() async throws -> VMRuntimeSnapshot
    func updateProfilePaths(installerMediaPath: String?, driverMediaPath: String?, virtualDiskPath: String?) async throws -> VMRuntimeSnapshot
    func markWindowsInstalled() async throws -> VMRuntimeSnapshot
    func markGuestAgentConnected(agentVersion: String) async throws -> VMRuntimeSnapshot
    func start() async throws -> VMRuntimeSnapshot
    func stop() async throws -> VMRuntimeSnapshot
    func suspend() async throws -> VMRuntimeSnapshot
    func resume() async throws -> VMRuntimeSnapshot
    func suspendedSession() async -> VMSuspensionRecord?
    func sendConsolePointerTap(normalizedX: Double, normalizedY: Double) async throws -> QEMUPointerTapRecord
    func sendConsoleKey(_ key: String) async throws -> QEMUKeySendRecord
    func exportDiagnostics(to directory: URL) async throws -> URL
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

public extension VMRuntimeSnapshot {
    func windowsInstallStatusReport(generatedAt: Date = Date()) -> VMWindowsInstallStatusReport {
        VMWindowsInstallStatusReport(
            generatedAt: generatedAt,
            state: state,
            profileName: profileName,
            bootReady: bootReady,
            windowsInstalled: windowsInstalled,
            installEvidence: installEvidence,
            installerMediaPath: installerMediaPath,
            driverMediaPath: driverMediaPath,
            virtualDiskPath: virtualDiskPath,
            automaticInstallMediaPath: automaticInstallMediaPath,
            automaticInstallMediaStatus: automaticInstallMediaStatusEvidence(),
            latestConsoleScreenshotPath: latestConsoleScreenshotPath,
            displaySurface: displaySurfaceEvidence(),
            latestConsoleLaunch: latestConsoleLaunch,
            runningQEMUProcess: runningQEMUProcess,
            nextActions: windowsInstallNextActions()
        )
    }

    private func windowsInstallNextActions() -> [String] {
        let mediaRecoveryActions = automaticInstallMediaRecoveryActions()
        if !bootReady {
            var actions = runningRecoveryActions()
            let blockers = preflightChecks
                .filter { $0.state == .failed }
                .map { "\($0.title): \($0.detail)" }
            if !blockers.isEmpty {
                actions.append(contentsOf: blockers)
                if let prepareCommand = windowsInstallPrepareCommand() {
                    actions.append("Re-register the selected installer with `\(prepareCommand)`.")
                }
                return actions
            }

            let blockedSteps = installationSteps
                .filter { $0.state == .blocked }
                .map { "\($0.title): \($0.detail)" }
            if !blockedSteps.isEmpty {
                actions.append(contentsOf: blockedSteps)
                if let prepareCommand = windowsInstallPrepareCommand() {
                    actions.append("Re-register the selected installer with `\(prepareCommand)`.")
                }
                return actions
            }

            if let prepareCommand = windowsInstallPrepareCommand() {
                actions.append("Re-register the selected installer with `\(prepareCommand)`.")
            }
            actions.append("Run `veil-vmctl qemu-doctor --json` to identify the missing Windows install prerequisite.")
            return actions
        }

        if state == .running {
            var actions = runningRecoveryActions()
            if latestConsoleLaunch?.displaySurface.isLiveCapable == true {
                actions.append("Validate the embedded console with `veil-vmctl qemu-display-smoke --json`.")
            }
            if latestConsoleLaunch?.monitorSocketPath.isEmpty == false {
                actions.append("Refresh install evidence with `veil-vmctl qemu-capture --json` before changing recovery steps.")
            }
            actions.append(contentsOf: mediaRecoveryActions)
            if !windowsInstalled {
                actions.append("Continue Windows Setup in the console; use `veil-vmctl qemu-oobe-bypass --json` only when OOBE network setup blocks local account creation.")
            } else if installEvidence.kind != .guestAgent {
                actions.append("Install the guest agent with `veil-vmctl qemu-install-agent --json` once the Windows desktop is visible.")
            } else {
                actions.append("Check the app runtime bridge with `veil-vmctl app-runtime-status --json`.")
            }
            return actions
        }

        if windowsInstalled, installEvidence.kind != .guestAgent {
            if !mediaRecoveryActions.isEmpty {
                return mediaRecoveryActions
            }
            return [
                "Start the installed Windows disk with `veil-vmctl qemu-start --wait-seconds 15`.",
                "Install the guest agent with `veil-vmctl qemu-install-agent --json` once the Windows desktop is visible."
            ]
        }

        if windowsInstalled {
            return ["Start Windows and verify the app runtime bridge with `veil-vmctl app-runtime-status --json`."]
        }

        return ["Start the visible install with `veil-vmctl qemu-start --wait-seconds 15`."]
    }

    private func automaticInstallMediaRecoveryActions() -> [String] {
        let status = automaticInstallMediaStatusEvidence()
        guard status.state == .stale || status.state == .missing else {
            return []
        }

        let command = status.rebuildCommand ?? "veil-vmctl prepare --installer /path/to/Windows.iso"
        if state == .running {
            return [
                "Power down Windows with `veil-vmctl qemu-powerdown --json`, rebuild guest tools media with `\(command)`, then restart Windows so QEMU attaches the refreshed `VeilAutoInstall.iso`."
            ]
        }

        return [
            "Rebuild guest tools media with `\(command)` before starting Windows so attached recovery scripts match the local guest-agent bundle."
        ]
    }

    private func windowsInstallPrepareCommand() -> String? {
        guard let installerMediaPath, !installerMediaPath.isEmpty else {
            return nil
        }

        var command = "veil-vmctl prepare --installer \(shellQuotedArgument(installerMediaPath))"
        if let driverMediaPath, !driverMediaPath.isEmpty {
            command += " --drivers \(shellQuotedArgument(driverMediaPath))"
        }
        return command
    }

    private func shellQuotedArgument(_ value: String) -> String {
        guard value.rangeOfCharacter(from: .whitespacesAndNewlines) != nil else {
            return value
        }

        return "'\(value.replacingOccurrences(of: "'", with: "'\\''"))'"
    }

    private func runningRecoveryActions() -> [String] {
        guard state == .running else {
            return []
        }

        if latestConsoleLaunch == nil, let runningQEMUProcess {
            return [
                "Close existing QEMU/Windows PID \(runningQEMUProcess.pid) before preparing or relaunching; Veil detected the configured disk is already attached but has no current launch record."
            ]
        }

        if latestConsoleLaunch == nil {
            return [
                "Close the existing QEMU/Windows process before preparing or relaunching; Veil detected the configured disk is already attached but has no current launch record."
            ]
        }

        return [
            "Capture the current console before changing setup state, then shut down with `veil-vmctl qemu-powerdown --json` if you need to reselect media or relaunch."
        ]
    }

    private func automaticInstallMediaStatusEvidence() -> VMAutomaticInstallMediaStatus {
        let mediaURL = automaticInstallMediaPath.map(URL.init(fileURLWithPath:))
        let sourceURL = automaticInstallSourceDirectoryURL()
        let mediaDate = mediaURL.flatMap { modificationDate(at: $0) }
        let sourceDate = latestAutomaticInstallSourceModificationDate()
        let rebuildCommand = windowsInstallPrepareCommand()

        guard let mediaPath = automaticInstallMediaPath,
              !mediaPath.isEmpty else {
            return VMAutomaticInstallMediaStatus(
                state: .missing,
                isCurrent: false,
                mediaPath: nil,
                sourcePath: sourceURL?.path,
                mediaModifiedAt: nil,
                sourceModifiedAt: sourceDate,
                recommendedAction: "prepare-media",
                rebuildCommand: rebuildCommand,
                requiresRelaunch: state == .running,
                detail: "VeilAutoInstall.iso is missing; prepare Windows before starting or repairing the guest agent."
            )
        }

        guard let mediaDate else {
            return VMAutomaticInstallMediaStatus(
                state: .missing,
                isCurrent: false,
                mediaPath: mediaPath,
                sourcePath: sourceURL?.path,
                mediaModifiedAt: nil,
                sourceModifiedAt: sourceDate,
                recommendedAction: "prepare-media",
                rebuildCommand: rebuildCommand,
                requiresRelaunch: state == .running,
                detail: "VeilAutoInstall.iso is not present at the configured path; rebuild the automatic install media before using guest-agent repair."
            )
        }

        guard let sourceDate else {
            return VMAutomaticInstallMediaStatus(
                state: .unavailable,
                isCurrent: false,
                mediaPath: mediaPath,
                sourcePath: sourceURL?.path,
                mediaModifiedAt: mediaDate,
                sourceModifiedAt: nil,
                recommendedAction: "inspect-media",
                rebuildCommand: rebuildCommand,
                requiresRelaunch: false,
                detail: "Veil cannot compare VeilAutoInstall.iso with the staged Autounattend or guest-agent bundle because source timestamps are unavailable."
            )
        }

        let isCurrent = mediaDate >= sourceDate
        return VMAutomaticInstallMediaStatus(
            state: isCurrent ? .current : .stale,
            isCurrent: isCurrent,
            mediaPath: mediaPath,
            sourcePath: sourceURL?.path,
            mediaModifiedAt: mediaDate,
            sourceModifiedAt: sourceDate,
            recommendedAction: isCurrent ? "none" : "rebuild-media-and-relaunch",
            rebuildCommand: rebuildCommand,
            requiresRelaunch: !isCurrent && state == .running,
            detail: isCurrent
                ? "VeilAutoInstall.iso is current with the staged Autounattend and guest-agent bundle."
                : "VeilAutoInstall.iso is older than the staged Autounattend or guest-agent bundle; rebuild it and relaunch Windows before relying on attached-media guest-agent repair."
        )
    }

    private func automaticInstallSourceDirectoryURL() -> URL? {
        if let automaticInstallAnswerFilePath, !automaticInstallAnswerFilePath.isEmpty {
            return URL(fileURLWithPath: automaticInstallAnswerFilePath).deletingLastPathComponent()
        }

        if let automaticInstallMediaPath, !automaticInstallMediaPath.isEmpty {
            return URL(fileURLWithPath: automaticInstallMediaPath).deletingLastPathComponent()
        }

        return nil
    }

    private func latestAutomaticInstallSourceModificationDate() -> Date? {
        guard let sourceURL = automaticInstallSourceDirectoryURL() else {
            return nil
        }

        let answerDate = modificationDate(at: sourceURL.appendingPathComponent("Autounattend.xml"))
        let agentBundleDate = latestModificationDate(in: sourceURL.appendingPathComponent("Veil Guest Agent", isDirectory: true))

        switch (answerDate, agentBundleDate) {
        case let (answerDate?, agentBundleDate?):
            return max(answerDate, agentBundleDate)
        case let (answerDate?, nil):
            return answerDate
        case let (nil, agentBundleDate?):
            return agentBundleDate
        case (nil, nil):
            return nil
        }
    }

    private func modificationDate(at url: URL) -> Date? {
        try? FileManager.default.attributesOfItem(atPath: url.path)[.modificationDate] as? Date
    }

    private func latestModificationDate(in url: URL) -> Date? {
        let fileManager = FileManager.default
        guard fileManager.fileExists(atPath: url.path) else {
            return nil
        }

        var latest = modificationDate(at: url) ?? Date.distantPast
        guard let enumerator = fileManager.enumerator(
            at: url,
            includingPropertiesForKeys: [.contentModificationDateKey]
        ) else {
            return latest
        }

        for case let fileURL as URL in enumerator {
            guard let modificationDate = try? fileURL
                .resourceValues(forKeys: [.contentModificationDateKey])
                .contentModificationDate else {
                continue
            }
            latest = max(latest, modificationDate)
        }
        return latest
    }

    private func displaySurfaceEvidence() -> VMConsoleDisplaySurface {
        if let surface = latestConsoleLaunch?.displaySurface,
           surface.kind != .unavailable {
            return surface
        }

        guard let latestConsoleScreenshotPath else {
            return .unavailable
        }

        return VMConsoleDisplaySurface(
            kind: .screenshot,
            endpoint: nil,
            screenshotPath: latestConsoleScreenshotPath,
            isLiveCapable: false
        )
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
    public private(set) var diagnosticsURL: URL?

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

    public var canStop: Bool {
        guard let snapshot else {
            return false
        }

        return snapshot.state == .running || snapshot.state == .suspended
    }

    /// Suspend is offered only for a running machine. A `.suspended` VM is already persisted, and a
    /// `.starting` one has no consistent guest state to stream yet.
    public var canSuspend: Bool {
        guard let snapshot, snapshot.state == .running else {
            return false
        }

        return VMSessionActionReportFactory.persistenceSummary(snapshot: snapshot).isSupported
    }

    /// Resume is offered only when a saved memory-state file is actually on disk, so the button can
    /// never promise a session Veil cannot restore.
    public var canResume: Bool {
        guard let snapshot else {
            return false
        }

        return snapshot.state == .suspended && snapshot.suspendedSession != nil
    }

    public var capabilitySummary: String {
        guard let snapshot else {
            return "VM runtime capabilities not loaded"
        }

        if let runtimeProvider = snapshot.runtimeProvider {
            let availability = snapshot.virtualizationAvailable ? "available" : "unavailable"
            return "\(runtimeProvider.displayName) local provider \(availability) on \(snapshot.architecture)"
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

    public func refreshRuntimeEvidence() async {
        do {
            snapshot = try await service.loadSnapshot()
            errorMessage = nil
            if phase == .idle || phase == .failed {
                phase = .loaded
            }
        } catch {
            errorMessage = userMessage(for: error)
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

    public func prepareDefaultVM() async {
        phase = .loading
        errorMessage = nil

        do {
            snapshot = try await service.prepareDefaultVM()
            phase = .loaded
        } catch {
            errorMessage = userMessage(for: error)
            phase = .failed
        }
    }

    public func createDefaultVirtualDisk() async {
        phase = .loading
        errorMessage = nil

        do {
            snapshot = try await service.createDefaultVirtualDisk()
            phase = .loaded
        } catch {
            errorMessage = userMessage(for: error)
            phase = .failed
        }
    }

    public func updateProfilePaths(installerMediaPath: String?, driverMediaPath: String?, virtualDiskPath: String?) async {
        phase = .loading
        errorMessage = nil

        do {
            snapshot = try await service.updateProfilePaths(
                installerMediaPath: installerMediaPath,
                driverMediaPath: driverMediaPath,
                virtualDiskPath: virtualDiskPath
            )
            phase = .loaded
        } catch {
            errorMessage = userMessage(for: error)
            phase = .failed
        }
    }

    /// Stores the user-selected installer and prepares every local resource needed
    /// for the first Windows boot. The caller starts the VM only when this returns
    /// true, so invalid media or missing host prerequisites remain visible instead
    /// of launching a VM that cannot reach Windows Setup.
    @discardableResult
    public func prepareWindowsInstallation(
        installerMediaPath: String,
        driverMediaPath: String?,
        virtualDiskPath: String?
    ) async -> Bool {
        await updateProfilePaths(
            installerMediaPath: installerMediaPath,
            driverMediaPath: driverMediaPath,
            virtualDiskPath: virtualDiskPath
        )

        guard phase == .loaded else {
            return false
        }

        await prepareDefaultVM()
        return phase == .loaded && canStart
    }

    public func markGuestAgentConnected(agentVersion: String) async {
        phase = .loading
        errorMessage = nil

        do {
            snapshot = try await service.markGuestAgentConnected(agentVersion: agentVersion)
            phase = .loaded
        } catch {
            errorMessage = userMessage(for: error)
            phase = .failed
        }
    }

    public func markWindowsInstalled() async {
        phase = .loading
        errorMessage = nil

        do {
            snapshot = try await service.markWindowsInstalled()
            phase = .loaded
        } catch {
            errorMessage = userMessage(for: error)
            phase = .failed
        }
    }

    public func start() async {
        phase = .loading
        errorMessage = nil

        if canStart, var startingSnapshot = snapshot {
            startingSnapshot.state = .starting
            startingSnapshot.detail = "Starting Windows setup. Veil keeps runtime status and setup evidence in the main window."
            snapshot = startingSnapshot
        }

        do {
            snapshot = try await service.start()
            phase = .loaded
        } catch {
            let message = userMessage(for: error)
            if var failedSnapshot = snapshot {
                failedSnapshot.state = .failed
                failedSnapshot.detail = message
                snapshot = failedSnapshot
            }
            errorMessage = message
            phase = .failed
        }
    }

    public func stop() async {
        phase = .loading
        errorMessage = nil

        do {
            snapshot = try await service.stop()
            phase = .loaded
        } catch {
            errorMessage = userMessage(for: error)
            phase = .failed
        }
    }

    public func suspend() async {
        phase = .loading
        errorMessage = nil

        do {
            snapshot = try await service.suspend()
            phase = .loaded
        } catch {
            // The guest is left paused when a memory-state save fails partway, so the surfaced state
            // must not claim the machine is stopped.
            errorMessage = userMessage(for: error)
            phase = .failed
        }
    }

    public func resume() async {
        phase = .loading
        errorMessage = nil

        if canResume, var resumingSnapshot = snapshot {
            resumingSnapshot.state = .starting
            resumingSnapshot.detail = "Resuming the suspended Windows session."
            snapshot = resumingSnapshot
        }

        do {
            snapshot = try await service.resume()
            phase = .loaded
        } catch {
            let message = userMessage(for: error)
            // Resume failures keep the saved state file, so report the VM as still suspended rather
            // than failed -- the user can retry or stop it.
            if var failedSnapshot = snapshot {
                failedSnapshot.state = failedSnapshot.suspendedSession == nil ? .failed : .suspended
                failedSnapshot.detail = message
                snapshot = failedSnapshot
            }
            errorMessage = message
            phase = .failed
        }
    }

    public func sendConsolePointerTap(normalizedX: Double, normalizedY: Double) async {
        do {
            _ = try await service.sendConsolePointerTap(
                normalizedX: normalizedX,
                normalizedY: normalizedY
            )
            errorMessage = nil
        } catch {
            errorMessage = userMessage(for: error)
        }
    }

    public func sendConsoleKey(_ key: String) async {
        do {
            _ = try await service.sendConsoleKey(key)
            errorMessage = nil
        } catch {
            errorMessage = userMessage(for: error)
        }
    }

    public func exportDiagnostics(to directory: URL) async {
        phase = .loading
        errorMessage = nil

        do {
            diagnosticsURL = try await service.exportDiagnostics(to: directory)
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

