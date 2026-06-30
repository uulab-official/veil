import SwiftUI
import VeilHostCore

struct ContentView: View {
    @Bindable var model: HostDashboardModel
    @Bindable var vmModel: VMRuntimeModel
    var startVMAction: () -> Void
    var stopVMAction: () -> Void
    @SceneStorage("selectedSection") private var selectedSection: ShellSection = .vm

    var body: some View {
        NavigationSplitView {
            List(ShellSection.sidebarOrder, id: \.self, selection: $selectedSection) { section in
                Label(section.title, systemImage: section.symbolName)
                    .tag(section)
            }
            .listStyle(.sidebar)
            .navigationTitle("Veil")
            .navigationSplitViewColumnWidth(min: 180, ideal: 220)
        } detail: {
            DetailView(
                model: model,
                vmModel: vmModel,
                selectedSection: selectedSection,
                startVMAction: startVMAction,
                stopVMAction: stopVMAction
            )
        }
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
                .help("Refresh host and Control Center status")
                .disabled(isRefreshing)

                switch selectedSection {
                case .vm:
                    if vmModel.canStop {
                        Button(action: stopVMAction) {
                            Label("Stop VM", systemImage: "stop.fill")
                        }
                        .help("Stop the running Windows 11 Arm VM")
                        .disabled(vmModel.phase == .loading)
                    } else {
                        Button(action: startVMAction) {
                            Label("Start VM", systemImage: "power")
                        }
                        .help("Start the configured Windows 11 Arm VM")
                        .disabled(!vmModel.canStart || vmModel.phase == .loading)
                    }
                case .apps:
                    Button {
                        Task {
                            await model.launchSelectedApp()
                        }
                    } label: {
                        Label("Launch App", systemImage: "play.fill")
                    }
                    .help("Launch the selected Windows app")
                    .disabled(!model.canLaunchSelectedApp)
                case .agent, .launch:
                    EmptyView()
                }
            }
        }
    }

    private var isRefreshing: Bool {
        model.phase == .loading || model.phase == .launching || vmModel.phase == .loading
    }
}
