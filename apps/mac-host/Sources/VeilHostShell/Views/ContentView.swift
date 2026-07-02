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
        ZStack {
            VeilWindowBackdrop()
                .ignoresSafeArea()

            VStack(spacing: 0) {
                VeilWindowHeader(
                    isRefreshing: isRefreshing,
                    refreshAction: refreshAll
                )

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

private struct VeilWindowBackdrop: View {
    var body: some View {
        ZStack {
            Color(red: 0.055, green: 0.061, blue: 0.071)

            LinearGradient(
                colors: [
                    Color(red: 0.024, green: 0.130, blue: 0.240).opacity(0.52),
                    Color.clear
                ],
                startPoint: .topLeading,
                endPoint: .center
            )
        }
    }
}

private struct VeilWindowHeader: View {
    var isRefreshing: Bool
    var refreshAction: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            Spacer()
                .frame(width: 76)

            VeilAppMark(size: 28)

            VStack(alignment: .leading, spacing: 1) {
                Text("Veil")
                    .font(.system(size: 14, weight: .semibold))
                Text("Windows Runtime")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Button(action: refreshAction) {
                Label("Refresh", systemImage: "arrow.clockwise")
                    .labelStyle(.iconOnly)
            }
            .buttonStyle(.plain)
            .frame(width: 30, height: 30)
            .background(.white.opacity(0.075), in: Circle())
            .disabled(isRefreshing)
            .help("Refresh")
        }
        .padding(.trailing, 16)
        .frame(height: 50)
        .background(
            Rectangle()
                .fill(Color(red: 0.070, green: 0.076, blue: 0.088).opacity(0.96))
        )
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(.white.opacity(0.055))
                .frame(height: 1)
        }
        .contentShape(Rectangle())
        .gesture(WindowDragGesture())
    }
}
