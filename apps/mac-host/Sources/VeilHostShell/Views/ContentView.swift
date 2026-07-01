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

}

private struct VeilWindowHeader: View {
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
