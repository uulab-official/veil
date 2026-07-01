import SwiftUI
import VeilHostCore

struct ContentView: View {
    @Bindable var model: HostDashboardModel
    @Bindable var vmModel: VMRuntimeModel
    var startVMAction: () -> Void
    var stopVMAction: () -> Void
    var showVMConsoleAction: () -> Void
    var consoleMessage: String?

    var body: some View {
        DetailView(
            model: model,
            vmModel: vmModel,
            selectedSection: .vm,
            startVMAction: startVMAction,
            stopVMAction: stopVMAction,
            showVMConsoleAction: showVMConsoleAction,
            consoleMessage: consoleMessage
        )
        .toolbar {
            ToolbarItemGroup {
                Button {
                    Task {
                        async let hostLoad: Void = model.load()
                        async let vmLoad: Void = vmModel.load()
                        _ = await (hostLoad, vmLoad)
                    }
                } label: {
                    Label("Refresh", systemImage: "arrow.clockwise")
                }
                .help("Refresh")
                .disabled(isRefreshing)
            }
        }
    }

    private var isRefreshing: Bool {
        model.phase == .loading || model.phase == .launching || vmModel.phase == .loading
    }

}
