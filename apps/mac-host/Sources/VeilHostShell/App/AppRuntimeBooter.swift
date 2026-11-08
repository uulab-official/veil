import Foundation
import VeilHostCore

enum AppRuntimeProviderSelection: String, Equatable {
    case qemu
    case appleVirtualization

    static let environmentKey = "VEIL_VM_PROVIDER"

    static func resolve(
        providers: [VMRuntimeProviderSummary],
        environment: [String: String] = ProcessInfo.processInfo.environment
    ) -> Self {
        switch environment[environmentKey]?.lowercased() {
        case "qemu":
            return .qemu
        case "apple", "apple-virtualization", "virtualization":
            return .appleVirtualization
        default:
            break
        }

        let qemuIsActive = providers.contains {
            $0.kind == .qemuHypervisor && $0.status == .active
        }
        return qemuIsActive ? .qemu : .appleVirtualization
    }
}

enum AppRuntimeBooterError: LocalizedError {
    case qemuGuestAutomationUnavailable

    var errorDescription: String? {
        switch self {
        case .qemuGuestAutomationUnavailable:
            "Automatic guest setup requires QEMU control. Continue in the Apple Virtualization Windows console or install QEMU and restart Veil."
        }
    }
}

final class AppRuntimeBooter: VMRuntimeBooting, @unchecked Sendable {
    let provider: AppRuntimeProviderSelection

    private let qemuBooter: QEMUVMRuntimeBooter
    private let virtualizationBooter: VirtualizationVMRuntimeBooter
    @MainActor private var virtualizationConsolePresenter: VMConsoleWindowPresenter?

    init(
        provider: AppRuntimeProviderSelection,
        qemuBooter: QEMUVMRuntimeBooter,
        virtualizationBooter: VirtualizationVMRuntimeBooter
    ) {
        self.provider = provider
        self.qemuBooter = qemuBooter
        self.virtualizationBooter = virtualizationBooter
    }

    static func make(
        environment: [String: String] = ProcessInfo.processInfo.environment,
        providerProbe: VMRuntimeProviderProbe = VMRuntimeProviderProbe()
    ) -> AppRuntimeBooter {
        let providers = providerProbe.localProviders(
            architecture: "arm64",
            minimumOSSupported: true
        )
        let provider = AppRuntimeProviderSelection.resolve(
            providers: providers,
            environment: environment
        )
        let qemuBooter = environment["VEIL_USE_NATIVE_QEMU_DISPLAY"] == "1"
            ? QEMUVMRuntimeBooter.shared
            : QEMUVMRuntimeBooter(frontmostRunner: {}, displayMode: .vncLoopback)

        return AppRuntimeBooter(
            provider: provider,
            qemuBooter: qemuBooter,
            virtualizationBooter: .shared
        )
    }

    var supportsNativeDisplayWindow: Bool {
        switch provider {
        case .qemu:
            qemuBooter.supportsNativeDisplayWindow
        case .appleVirtualization:
            true
        }
    }

    var usesEmbeddedDisplaySurface: Bool {
        switch provider {
        case .qemu:
            !qemuBooter.supportsNativeDisplayWindow
        case .appleVirtualization:
            true
        }
    }

    func runtimeState() async -> VMRuntimeState? {
        switch provider {
        case .qemu:
            await qemuBooter.runtimeState()
        case .appleVirtualization:
            await virtualizationBooter.runtimeState()
        }
    }

    func start(profile: VMProfile) async throws -> VMRuntimeState {
        switch provider {
        case .qemu:
            return try await qemuBooter.start(profile: profile)
        case .appleVirtualization:
            return try await virtualizationBooter.start(profile: profile)
        }
    }

    func stop() async throws -> VMRuntimeState {
        switch provider {
        case .qemu:
            return try await qemuBooter.stop()
        case .appleVirtualization:
            let state = try await virtualizationBooter.stop()
            await closeVirtualizationConsole()
            return state
        }
    }

    func recoverStalledRuntime() async -> QEMURuntimeRecoveryResult {
        switch provider {
        case .qemu:
            await qemuBooter.recoverStalledRuntime()
        case .appleVirtualization:
            .unsupported
        }
    }

    func suspend(profile: VMProfile) async throws -> VMRuntimeState {
        switch provider {
        case .qemu:
            return try await qemuBooter.suspend(profile: profile)
        case .appleVirtualization:
            return try await virtualizationBooter.suspend(profile: profile)
        }
    }

    func resume(profile: VMProfile) async throws -> VMRuntimeState {
        switch provider {
        case .qemu:
            return try await qemuBooter.resume(profile: profile)
        case .appleVirtualization:
            return try await virtualizationBooter.resume(profile: profile)
        }
    }

    @MainActor
    func showConsoleIfRunning() -> Bool {
        switch provider {
        case .qemu:
            qemuBooter.showConsoleIfRunning()
        case .appleVirtualization:
            showVirtualizationConsole()
        }
    }

    func installGuestAgentFromAttachedMedia() async throws -> QEMUKeySendRecord {
        guard provider == .qemu else {
            throw AppRuntimeBooterError.qemuGuestAutomationUnavailable
        }
        return try await qemuBooter.installGuestAgentFromAttachedMedia()
    }

    func updateGuestToolsFromRemovableMedia() async throws -> QEMUKeySendRecord {
        guard provider == .qemu else {
            throw AppRuntimeBooterError.qemuGuestAutomationUnavailable
        }
        return try await qemuBooter.updateGuestToolsFromRemovableMedia()
    }

    func prepareSparsePackageFromAttachedMedia() async throws -> QEMUKeySendRecord {
        guard provider == .qemu else {
            throw AppRuntimeBooterError.qemuGuestAutomationUnavailable
        }
        return try await qemuBooter.prepareSparsePackageFromAttachedMedia()
    }

    @MainActor
    private func showVirtualizationConsole() -> Bool {
        if virtualizationConsolePresenter == nil {
            virtualizationConsolePresenter = VMConsoleWindowPresenter(
                bootRunner: virtualizationBooter
            )
        }
        return virtualizationConsolePresenter?.showConsoleIfAvailable() == true
    }

    @MainActor
    private func closeVirtualizationConsole() {
        virtualizationConsolePresenter?.closeConsole()
        virtualizationConsolePresenter = nil
    }
}

extension AppRuntimeBooter {
    /// Installs or repairs Windows tools with the build this Veil ships. VEIL_AUTO was attached at
    /// boot and can hold an older agent, so the current bundle goes in on the tools update disc;
    /// a Windows started without the removable drive falls back to VEIL_AUTO's V.cmd.
    @MainActor
    func installCurrentGuestTools(vmModel: VMRuntimeModel) async throws -> QEMUKeySendRecord {
        guard await vmModel.insertGuestToolsUpdateMedia() == nil else {
            return try await installGuestAgentFromAttachedMedia()
        }
        let record = try await updateGuestToolsFromRemovableMedia()
        // The repair copies the bundle right after the Windows approval, which can come minutes
        // later; the disc stays until well after the update wait gives up.
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(GuestToolsUpdatePolicy.approvalWaitSeconds + 60))
            await vmModel.ejectRemovableMedia()
        }
        return record
    }
}
