import SwiftUI
import VeilHostCore

struct ContentView: View {
    @Bindable var model: HostDashboardModel
    @SceneStorage("selectedSection") private var selectedSection: ShellSection = .apps

    var body: some View {
        NavigationSplitView {
            List(selection: $selectedSection) {
                Label("Windows Apps", systemImage: "square.grid.2x2")
                    .tag(ShellSection.apps)
                Label("Agent", systemImage: "network")
                    .tag(ShellSection.agent)
                Label("Last Launch", systemImage: "macwindow.on.rectangle")
                    .tag(ShellSection.launch)
            }
            .navigationSplitViewColumnWidth(min: 180, ideal: 220)
        } detail: {
            DetailView(model: model, selectedSection: selectedSection)
        }
        .toolbar {
            ToolbarItemGroup {
                Button {
                    Task {
                        await model.load()
                    }
                } label: {
                    Label("Refresh", systemImage: "arrow.clockwise")
                }
                .help("Refresh Windows agent status")
                .disabled(model.phase == .loading || model.phase == .launching)

                Button {
                    Task {
                        await model.launchNotepad()
                    }
                } label: {
                    Label("Launch Notepad", systemImage: "play.fill")
                }
                .help("Launch Notepad through the guest agent")
                .disabled(model.phase == .loading || model.phase == .launching)
            }
        }
    }
}

enum ShellSection: String, Hashable {
    case apps
    case agent
    case launch
}
