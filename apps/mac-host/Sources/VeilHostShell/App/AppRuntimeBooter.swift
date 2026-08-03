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
