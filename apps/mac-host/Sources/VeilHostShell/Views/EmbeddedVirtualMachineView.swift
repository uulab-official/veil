import SwiftUI
import VeilHostCore
import Virtualization

enum RuntimeDisplaySelection: Equatable {
    case appleVirtualMachine
    case capturedSurface
    case placeholder

    static func resolve(
        provider: VMRuntimeProviderKind?,
        state: VMRuntimeState,
        hasAppleVirtualMachine: Bool,
        hasCapturedSurface: Bool
    ) -> Self {
        let canShowRunningDisplay = state == .running || state == .starting

        if provider == .appleVirtualization,
           canShowRunningDisplay,
           hasAppleVirtualMachine {
            return .appleVirtualMachine
        }

        if hasCapturedSurface {
            return .capturedSurface
        }

        return .placeholder
    }
}

struct EmbeddedVirtualMachineView: NSViewRepresentable {
    let virtualMachine: VZVirtualMachine

    func makeNSView(context: Context) -> VZVirtualMachineView {
        let view = VZVirtualMachineView()
        configure(view)
        return view
    }

    func updateNSView(_ view: VZVirtualMachineView, context: Context) {
        configure(view)
    }

    private func configure(_ view: VZVirtualMachineView) {
        if view.virtualMachine !== virtualMachine {
            view.virtualMachine = virtualMachine
        }
        view.capturesSystemKeys = true
        view.automaticallyReconfiguresDisplay = true
    }
}
