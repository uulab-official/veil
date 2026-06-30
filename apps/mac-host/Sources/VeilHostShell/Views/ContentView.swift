import SwiftUI
import VeilHostCore

struct ContentView: View {
    @Bindable var model: HostDashboardModel
    @Bindable var vmModel: VMRuntimeModel
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
            DetailView(model: model, vmModel: vmModel, selectedSection: selectedSection)
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
                .help("Refresh Windows agent status")
                .disabled(model.phase == .loading || model.phase == .launching)

                Button {
                    Task {
                        await model.launchSelectedApp()
                    }
                } label: {
                    Label("Launch", systemImage: "play.fill")
                }
                .help("Launch the selected Windows app")
                .disabled(!model.canLaunchSelectedApp)
            }
        }
    }
}
