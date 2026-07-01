import SwiftUI
import VeilHostCore

struct ContentView: View {
    @Bindable var model: HostDashboardModel
    @Bindable var vmModel: VMRuntimeModel
    var startVMAction: () -> Void
    var stopVMAction: () -> Void
    var showVMConsoleAction: () -> Void
    var launchWindowsAppAction: () -> Void
    var consoleMessage: String?

    var body: some View {
        VStack(spacing: 0) {
            VeilWindowHeader(
                statusTitle: runtimeTitle,
                statusSymbol: runtimeSymbol,
                statusTint: runtimeTint,
                isRefreshing: isRefreshing,
                refreshAction: refreshAll
            )

            Divider()

            DetailView(
                model: model,
                vmModel: vmModel,
                selectedSection: .vm,
                startVMAction: startVMAction,
                stopVMAction: stopVMAction,
                showVMConsoleAction: showVMConsoleAction,
                launchWindowsAppAction: launchWindowsAppAction,
                consoleMessage: consoleMessage
            )
        }
    }

    private var isRefreshing: Bool {
        model.phase == .loading || model.phase == .launching || vmModel.phase == .loading
    }

    private func refreshAll() {
        Task {
            async let hostLoad: Void = model.load()
            async let vmLoad: Void = vmModel.load()
            _ = await (hostLoad, vmLoad)
        }
    }

    private var runtimeTitle: String {
        switch vmModel.snapshot?.state {
        case .running:
            "Running"
        case .starting:
            "Starting"
        case .stopped:
            vmModel.snapshot?.bootReady == true ? "Ready" : "Prepare"
        case .failed:
            "Attention"
        case .unsupported:
            "Unsupported"
        case .notConfigured:
            "Setup"
        case .suspended:
            "Paused"
        case nil:
            "Loading"
        }
    }

    private var runtimeSymbol: String {
        switch vmModel.snapshot?.state {
        case .running:
            "display"
        case .starting:
            "arrow.triangle.2.circlepath"
        case .stopped where vmModel.snapshot?.bootReady == true:
            "checkmark.circle.fill"
        case .failed, .unsupported:
            "exclamationmark.triangle"
        default:
            "circle"
        }
    }

    private var runtimeTint: Color {
        switch vmModel.snapshot?.state {
        case .running:
            .green
        case .starting:
            .blue
        case .stopped:
            vmModel.snapshot?.bootReady == true ? .green : .orange
        case .failed, .unsupported:
            .orange
        default:
            .secondary
        }
    }
}

private struct VeilWindowHeader: View {
    var statusTitle: String
    var statusSymbol: String
    var statusTint: Color
    var isRefreshing: Bool
    var refreshAction: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Spacer()
                .frame(width: 70)

            VeilAppMark(size: 28)

            VStack(alignment: .leading, spacing: 1) {
                Text("Veil")
                    .font(.callout.weight(.semibold))
                Text("Windows 11 on Mac")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }

            StatusPill(title: statusTitle, symbolName: statusSymbol, tint: statusTint)
                .padding(.leading, 4)

            Spacer()

            Button(action: refreshAction) {
                Label("Refresh", systemImage: "arrow.clockwise")
                    .labelStyle(.iconOnly)
            }
            .buttonStyle(.borderless)
            .disabled(isRefreshing)
            .help("Refresh")
        }
        .padding(.trailing, 14)
        .frame(height: 52)
        .background(.thinMaterial)
        .contentShape(Rectangle())
        .gesture(WindowDragGesture())
    }
}
