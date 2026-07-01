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
                    Color(red: 0.07, green: 0.09, blue: 0.12),
                    Color(red: 0.03, green: 0.15, blue: 0.22)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )

            VStack(spacing: 0) {
                LinearGradient(
                    colors: [
                        Color.white.opacity(0.08),
                        Color.clear
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )
                .frame(height: 190)

                Spacer()
            }

            HStack(spacing: 0) {
                Rectangle()
                    .fill(Color.cyan.opacity(0.07))
                    .frame(maxWidth: .infinity)
                Rectangle()
                    .fill(Color.green.opacity(0.045))
                    .frame(maxWidth: .infinity)
            }
            .blendMode(.screen)
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
        .background(.ultraThinMaterial)
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(.white.opacity(0.08))
                .frame(height: 1)
        }
        .contentShape(Rectangle())
        .gesture(WindowDragGesture())
    }
}
