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
            LinearGradient(
                colors: [
                    Color(nsColor: .windowBackgroundColor),
                    Color(red: 0.105, green: 0.118, blue: 0.135),
                    Color(red: 0.070, green: 0.074, blue: 0.084)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )

            VStack(spacing: 0) {
                LinearGradient(
                    colors: [
                        Color.white.opacity(0.060),
                        Color.clear
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )
                .frame(height: 190)

                Spacer()
            }
        }
    }
}

private struct VeilWindowHeader: View {
    var isRefreshing: Bool
    var refreshAction: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Spacer()
                .frame(width: 84)

            VeilAppMark(size: 30)

            VStack(alignment: .leading, spacing: 1) {
                Text("Veil")
                    .font(.system(size: 14, weight: .semibold))
                Text("Windows on Mac")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Button(action: refreshAction) {
                Label("Refresh", systemImage: "arrow.clockwise")
                    .labelStyle(.iconOnly)
            }
            .buttonStyle(.plain)
            .padding(8)
            .background(.thinMaterial, in: Circle())
            .disabled(isRefreshing)
            .help("Refresh")
        }
        .padding(.leading, 0)
        .padding(.trailing, 16)
        .frame(height: 62)
        .background(
            Rectangle()
                .fill(.ultraThinMaterial)
                .overlay(Color.black.opacity(0.18))
        )
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(.white.opacity(0.065))
                .frame(height: 1)
        }
        .contentShape(Rectangle())
        .gesture(WindowDragGesture())
    }
}
