import SwiftUI
import VeilHostCore

struct ContentView: View {
    @Bindable var model: HostDashboardModel
    @Bindable var vmModel: VMRuntimeModel
    var startVMAction: () -> Void
    var stopVMAction: () -> Void
    var showVMConsoleAction: () -> Void
    @SceneStorage("selectedSection") private var selectedSection: ShellSection = .vm

    var body: some View {
        NavigationSplitView {
            VStack(alignment: .leading, spacing: 0) {
                SidebarBrandHeader()
                    .padding(.horizontal, 12)
                    .padding(.top, 10)
                    .padding(.bottom, 8)

                List(ShellSection.sidebarOrder, id: \.self, selection: $selectedSection) { section in
                    Label(section.title, systemImage: section.symbolName)
                        .tag(section)
                }
                .listStyle(.sidebar)
            }
            .navigationTitle("Veil")
            .navigationSplitViewColumnWidth(min: 180, ideal: 220)
        } detail: {
            DetailView(
                model: model,
                vmModel: vmModel,
                selectedSection: selectedSection,
                startVMAction: startVMAction,
                stopVMAction: stopVMAction,
                showVMConsoleAction: showVMConsoleAction
            )
        }
        .toolbar {
            ToolbarItem(placement: .principal) {
                TopAppBarTitle(
                    section: selectedSection,
                    runtimeState: vmModel.snapshot?.state,
                    isRefreshing: isRefreshing
                )
            }

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
                    if canShowVMConsole {
                        Button(action: showVMConsoleAction) {
                            Label("Show Console", systemImage: "display")
                        }
                        .help("Open the Windows VM console")
                        .disabled(vmModel.phase == .loading)
                    }

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

    private var canShowVMConsole: Bool {
        vmModel.snapshot?.state == .running || vmModel.snapshot?.state == .starting
    }
}

private struct SidebarBrandHeader: View {
    var body: some View {
        HStack(spacing: 10) {
            VeilAppMark(size: 32)

            VStack(alignment: .leading, spacing: 1) {
                Text("Veil")
                    .font(.headline.weight(.semibold))
                Text("Windows App Runtime")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct TopAppBarTitle: View {
    var section: ShellSection
    var runtimeState: VMRuntimeState?
    var isRefreshing: Bool

    var body: some View {
        HStack(spacing: 10) {
            VeilAppMark(size: 26)

            VStack(alignment: .leading, spacing: 0) {
                Text(section.title)
                    .font(.headline.weight(.semibold))
                    .lineLimit(1)
                Text(statusText)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
        .frame(minWidth: 240, alignment: .leading)
        .accessibilityElement(children: .combine)
    }

    private var statusText: String {
        if isRefreshing {
            return "Refreshing local runtime"
        }

        guard section == .vm, let runtimeState else {
            return section.subtitle
        }

        switch runtimeState {
        case .unsupported:
            return "Host virtualization unsupported"
        case .notConfigured:
            return "Create or prepare a Windows profile"
        case .stopped:
            return "Ready for local runtime checks"
        case .starting:
            return "Starting Windows runtime"
        case .running:
            return "Windows runtime is running"
        case .suspended:
            return "Windows runtime is suspended"
        case .failed:
            return "Runtime needs attention"
        }
    }
}
