import Foundation

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
    /// The running Windows' removable CD drive, as QEMU last reported it.
    public private(set) var removableMedia: VMRemovableMediaStatus?

    private let service: any VMRuntimeService
    /// Runtime mutations are surfaced as button actions, but each action crosses an async
    /// service boundary. Keep the model itself single-flight so a double click or a stale
    /// callback cannot let a later operation overwrite the snapshot produced by an earlier one.
    private var operationInFlight = false
    @ObservationIgnored private var recordedVirtioGPUDriverInstalled: Bool?
    /// Monotonically identifies the latest state read/write. Background refreshes capture this
    /// value and discard their result if a newer mutation or refresh started while they awaited
    /// the service, preventing an old snapshot from landing after a successful operation.
    private var stateRevision = 0

    public init(service: any VMRuntimeService) {
        self.service = service
    }

    /// Disk and snapshot management, when the runtime provides it.
    public var diskManager: (any VMDiskManaging)? {
        service as? any VMDiskManaging
    }

    /// The service behind this model, for panels with their own state such as the USB device menu.
    public var runtimeService: any VMRuntimeService {
        service
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

    /// A boot-ready failed VM can be started again: the previous failure has already
    /// unwound the launch attempt, so retrying is safe and keeps the primary action
    /// aligned with the recovery banner instead of sending the user back through setup.
    public var canStart: Bool {
        guard let snapshot else {
            return false
        }

        return snapshot.virtualizationAvailable &&
            snapshot.minimumOSSupported &&
            snapshot.profileName != nil &&
            snapshot.bootReady &&
            (snapshot.state == .stopped || snapshot.state == .suspended || snapshot.state == .failed)
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
        guard beginOperation() else {
            return
        }

        do {
            snapshot = try await service.loadSnapshot()
            phase = .loaded
        } catch {
            errorMessage = userMessage(for: error)
            phase = .failed
        }
        operationInFlight = false
    }

    public func refreshRuntimeEvidence() async {
        guard !operationInFlight else {
            return
        }

        stateRevision += 1
        let refreshRevision = stateRevision

        do {
            let refreshedSnapshot = try await service.loadSnapshot()
            guard refreshRevision == stateRevision else {
                return
            }

            snapshot = refreshedSnapshot
            errorMessage = nil
            if phase == .idle || phase == .failed {
                phase = .loaded
            }
        } catch {
            guard refreshRevision == stateRevision else {
                return
            }

            errorMessage = userMessage(for: error)
        }
    }

    public func createDefaultProfile() async {
        guard beginOperation() else {
            return
        }

        do {
            snapshot = try await service.createDefaultProfile()
            phase = .loaded
        } catch {
            errorMessage = userMessage(for: error)
            phase = .failed
        }
        operationInFlight = false
    }

    public func prepareDefaultVM() async {
        guard beginOperation() else {
            return
        }

        do {
            snapshot = try await service.prepareDefaultVM()
            phase = .loaded
        } catch {
            errorMessage = userMessage(for: error)
            phase = .failed
        }
        operationInFlight = false
    }

    /// Saves Windows' CPU and memory for its next start.
    public func updateHardware(cpuCount: Int, memoryMB: Int) async {
        guard beginOperation() else {
            return
        }

        do {
            snapshot = try await service.updateHardware(cpuCount: cpuCount, memoryMB: memoryMB)
            phase = .loaded
        } catch {
            errorMessage = userMessage(for: error)
            phase = .failed
        }
        operationInFlight = false
    }

    /// Saves what Veil does with Windows when it opens and quits. Like the account name it runs between
    /// other operations, so a running Windows can be configured too.
    public func updateStartupBehavior(autoStart: Bool, suspendOnQuit: Bool) async {
        do {
            snapshot = try await service.updateStartupBehavior(autoStart: autoStart, suspendOnQuit: suspendOnQuit)
        } catch {
            errorMessage = userMessage(for: error)
        }
    }

    /// Saves what Command becomes in the Windows desktop. Runs beside other operations like the
    /// startup behavior, since it changes no VM hardware.
    public func updateCommandKeyMapping(_ mapping: VMCommandKeyMapping) async {
        do {
            snapshot = try await service.updateCommandKeyMapping(mapping)
        } catch {
            errorMessage = userMessage(for: error)
        }
    }

    /// Saves the user port forwards for the next start. Returns the refusal for the editor to show.
    @discardableResult
    public func updatePortForwards(_ rules: [VMPortForwardRule]) async -> String? {
        do {
            snapshot = try await service.updatePortForwards(rules)
            return nil
        } catch {
            return userMessage(for: error)
        }
    }

    public func refreshRemovableMedia() async {
        removableMedia = await service.removableMediaStatus()
    }

    /// Inserts an ISO into the running Windows. Returns the refusal for the panel to show.
    @discardableResult
    public func insertRemovableMedia(path: String) async -> String? {
        do {
            removableMedia = try await service.insertRemovableMedia(path: path)
            return nil
        } catch {
            return userMessage(for: error)
        }
    }

    @discardableResult
    public func ejectRemovableMedia() async -> String? {
        do {
            removableMedia = try await service.ejectRemovableMedia()
            return nil
        } catch {
            return userMessage(for: error)
        }
    }

    /// Saves the local Windows account name before the answer file is built. It runs between other
    /// operations' turns, so it never blocks starting the download that follows it.
    public func updateWindowsAccountName(_ name: String?) async {
        do {
            snapshot = try await service.updateWindowsAccountName(name)
        } catch {
            errorMessage = userMessage(for: error)
        }
    }

    /// Erases an unfinished Windows installation (disk, UEFI variables, TPM) so Setup starts over.
    @discardableResult
    public func restartWindowsInstallation() async -> Bool {
        guard beginOperation() else {
            return false
        }

        defer {
            operationInFlight = false
        }
        do {
            snapshot = try await service.restartWindowsInstallation()
            phase = .loaded
            return true
        } catch {
            errorMessage = userMessage(for: error)
            phase = .failed
            return false
        }
    }

    public func createDefaultVirtualDisk() async {
        guard beginOperation() else {
            return
        }

        do {
            snapshot = try await service.createDefaultVirtualDisk()
            phase = .loaded
        } catch {
            errorMessage = userMessage(for: error)
            phase = .failed
        }
        operationInFlight = false
    }

    public func updateProfilePaths(installerMediaPath: String?, driverMediaPath: String?, virtualDiskPath: String?) async {
        guard beginOperation() else {
            return
        }

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
        operationInFlight = false
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
        guard beginOperation() else {
            return
        }

        do {
            snapshot = try await service.markGuestAgentConnected(agentVersion: agentVersion)
            phase = .loaded
        } catch {
            errorMessage = userMessage(for: error)
            phase = .failed
        }
        operationInFlight = false
    }

    /// Stores the agent's `capabilities.virtioGpuDisplay` report, which decides the display devices of
    /// the next cold start. Health is polled, so only a changed value reaches the profile store, and a
    /// failed write is retried on the next report rather than shown: the VM keeps working on ramfb.
    public func recordVirtioGPUDriverInstalled(_ installed: Bool) async {
        guard recordedVirtioGPUDriverInstalled != installed else {
            return
        }

        do {
            try await service.recordVirtioGPUDriverInstalled(installed)
            recordedVirtioGPUDriverInstalled = installed
        } catch {
            recordedVirtioGPUDriverInstalled = nil
        }
    }

    public func markWindowsInstalled() async {
        guard beginOperation() else {
            return
        }

        do {
            snapshot = try await service.markWindowsInstalled()
            phase = .loaded
        } catch {
            errorMessage = userMessage(for: error)
            phase = .failed
        }
        operationInFlight = false
    }

    public func start() async {
        guard beginOperation() else {
            return
        }

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
        operationInFlight = false
    }

    public func stop() async {
        guard beginOperation() else {
            return
        }

        do {
            snapshot = try await service.stop()
            phase = .loaded
        } catch {
            errorMessage = userMessage(for: error)
            phase = .failed
        }
        operationInFlight = false
    }

    public func suspend() async {
        guard beginOperation() else {
            return
        }

        do {
            snapshot = try await service.suspend()
            phase = .loaded
        } catch {
            // The guest is left paused when a memory-state save fails partway, so the surfaced state
            // must not claim the machine is stopped.
            errorMessage = userMessage(for: error)
            phase = .failed
        }
        operationInFlight = false
    }

    public func resume() async {
        guard beginOperation() else {
            return
        }

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
        operationInFlight = false
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
        guard beginOperation() else {
            return
        }

        do {
            diagnosticsURL = try await service.exportDiagnostics(to: directory)
            phase = .loaded
        } catch {
            errorMessage = userMessage(for: error)
            phase = .failed
        }
        operationInFlight = false
    }

    @discardableResult
    private func beginOperation() -> Bool {
        guard !operationInFlight else {
            return false
        }

        operationInFlight = true
        stateRevision += 1
        phase = .loading
        errorMessage = nil
        return true
    }

    private func userMessage(for error: any Error) -> String {
        if let localized = error as? LocalizedError,
           let description = localized.errorDescription {
            return description
        }

        return String(describing: error)
    }
}

