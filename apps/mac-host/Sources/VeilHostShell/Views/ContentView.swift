import AppKit
import SwiftUI
import VeilHostCore

/// The main window, laid out like Parallels Desktop: the Control Center sidebar lists the Windows
/// machine and its apps, the detail area is the machine itself (Installation Assistant, the stopped
/// machine, or the live Windows display), and the toolbar carries power, view, and configuration.
struct ContentView: View {
    @Environment(ShellNavigation.self) private var navigation
    @Environment(\.appRuntimeProvider) private var appRuntimeProvider
    @Bindable var model: HostDashboardModel
    @Bindable var vmModel: VMRuntimeModel
    var startVMAction: () -> Void
    var stopVMAction: () -> Void
    var suspendVMAction: () -> Void
    var markWindowsInstalledAction: () -> Void
    var installGuestAgentAction: () -> Void
    var prepareSparsePackageAction: () -> Void
    var waitForGuestAgentAction: () -> Void
    var repairGuestAgentForAppLaunchAction: () -> Void
    var recoverRuntimeDisplayAction: () -> Void
    var showWindowsDisplayAction: () -> Void
    var launchWindowsAppAction: () -> Void
    var launchWindowsAppByIdAction: (String) -> Void
    var fulfillPendingLaunchAction: () -> Void
    var restoreWindowsAppWindowsAction: () -> Void
    var closeAllWindowsAppWindowsAction: () -> Void
    var restartStaleFrameStreamsAction: () -> Void
    var requestNotificationConsentAction: () -> Void
    var runNotificationProofAction: () -> Void
    var runRecommendedProofAction: () -> Void
    var runMultiAppProofAction: () -> Void
    var quietWindowsWhenIdleAction: () -> Void
    var displayMessage: String?
    @State private var columnVisibility = NavigationSplitViewVisibility.all
    @State private var showsStopConfirmation = false

    var body: some View {
        NavigationSplitView(columnVisibility: $columnVisibility) {
            ControlCenterSidebar(
                snapshot: vmModel.snapshot,
                status: machineStatus,
                apps: model.apps,
                selectedAppId: $model.selectedAppId,
                mirrorSessions: model.mirrorSessions,
                windowsInstalled: windowsInstalled,
                canOpenApps: canOpenApps,
                isLaunching: model.phase == .launching,
                openAppAction: launchWindowsAppByIdAction,
                configureAction: { navigation.openConfiguration() }
            )
            .navigationSplitViewColumnWidth(min: 210, ideal: 240, max: 320)
        } detail: {
            DetailView(
                model: model,
                vmModel: vmModel,
                startVMAction: startVMAction,
                stopVMAction: stopVMAction,
                markWindowsInstalledAction: markWindowsInstalledAction,
                installGuestAgentAction: installGuestAgentAction,
                prepareSparsePackageAction: prepareSparsePackageAction,
                waitForGuestAgentAction: waitForGuestAgentAction,
                repairGuestAgentForAppLaunchAction: repairGuestAgentForAppLaunchAction,
                recoverRuntimeDisplayAction: recoverRuntimeDisplayAction,
                showWindowsDisplayAction: showWindowsDisplayAction,
                launchWindowsAppAction: launchWindowsAppAction,
                fulfillPendingLaunchAction: fulfillPendingLaunchAction,
                restoreWindowsAppWindowsAction: restoreWindowsAppWindowsAction,
                closeAllWindowsAppWindowsAction: closeAllWindowsAppWindowsAction,
                restartStaleFrameStreamsAction: restartStaleFrameStreamsAction,
                requestNotificationConsentAction: requestNotificationConsentAction,
                runNotificationProofAction: runNotificationProofAction,
                runRecommendedProofAction: runRecommendedProofAction,
                runMultiAppProofAction: runMultiAppProofAction,
                quietWindowsWhenIdleAction: quietWindowsWhenIdleAction,
                displayMessage: displayMessage
            )
            .background(Color(red: 0.055, green: 0.061, blue: 0.071))
        }
        .navigationTitle(vmModel.snapshot?.profileName ?? "Windows 11")
        .navigationSubtitle(machineStatus.title)
        .toolbar { machineToolbar }
        .confirmationDialog(
            "Shut down Windows?",
            isPresented: $showsStopConfirmation,
            titleVisibility: .visible
        ) {
            Button("Shut Down", role: .destructive, action: stopVMAction)
            Button("Cancel", role: .cancel) {}
        } message: {
            Text(WindowsRuntimeStopConfirmation.message(
                hasMirroredWindowsApp: !model.mirrorSessions.isEmpty,
                hasQueuedLaunch: model.pendingLaunchStatus().isQueued
            ))
        }
        .preferredColorScheme(.dark)
    }

    @ToolbarContentBuilder
    private var machineToolbar: some ToolbarContent {
        ToolbarItemGroup(placement: .primaryAction) {
            if powerControls.showsStart {
                Button(action: startVMAction) {
                    Label(powerControls.startTitle, systemImage: "play.fill")
                }
                .disabled(!(vmModel.canStart || vmModel.canResume) || isBusy || !engineCanRunWindows)
                .help(engineCanRunWindows
                    ? (vmModel.canResume ? "Resume Windows" : "Start Windows")
                    : "Install QEMU to run Windows on this Mac")
            }

            if powerControls.showsSuspend {
                Button(action: suspendVMAction) {
                    Label("Suspend", systemImage: "pause.fill")
                }
                .disabled(isBusy)
                .help("Suspend Windows and keep open apps")
            }

            if powerControls.showsShutDown {
                Button(action: requestShutDown) {
                    Label("Shut Down", systemImage: "power")
                }
                .disabled(isBusy)
                .help("Shut down Windows")
            }
        }

        ToolbarItem(placement: .primaryAction) {
            @Bindable var navigation = navigation
            Picker("View", selection: $navigation.viewMode) {
                ForEach(MachineViewMode.allCases) { mode in
                    Label(mode.title, systemImage: mode.symbolName)
                        .tag(mode)
                }
            }
            .pickerStyle(.segmented)
            .labelStyle(.iconOnly)
            .disabled(!windowsInstalled || !isLive)
            .help("Choose between Windows apps as Mac windows and the full Windows desktop")
        }

        ToolbarItem(placement: .primaryAction) {
            Menu {
                if model.apps.isEmpty {
                    Text("No Windows apps yet")
                }
                ForEach(model.apps) { app in
                    Button(app.name) {
                        model.selectedAppId = app.id
                        launchWindowsAppByIdAction(app.id)
                    }
                }
                Divider()
                Button("Bring All Windows App Windows to Front", action: restoreWindowsAppWindowsAction)
                    .disabled(model.mirrorSessions.isEmpty)
                Button("Close All Windows App Windows", action: closeAllWindowsAppWindowsAction)
                    .disabled(model.mirrorSessions.isEmpty)
            } label: {
                Label("Windows Apps", systemImage: "square.grid.2x2")
            }
            .disabled(!windowsInstalled)
            .help("Open a Windows app as a Mac window")
        }

        ToolbarItem(placement: .primaryAction) {
            Button {
                navigation.openConfiguration()
            } label: {
                Label("Configure", systemImage: "gearshape")
            }
            .disabled(vmModel.snapshot == nil)
            .help("Configure Windows")
        }
    }

    private func requestShutDown() {
        if WindowsRuntimeStopConfirmation.needsConfirmation(
            hasMirroredWindowsApp: !model.mirrorSessions.isEmpty,
            hasQueuedLaunch: model.pendingLaunchStatus().isQueued
        ) {
            showsStopConfirmation = true
        } else {
            stopVMAction()
        }
    }

    private var machineStatus: MachineStatusPresentation {
        MachineStatusPresentation.resolve(
            state: vmModel.snapshot?.state,
            windowsInstalled: windowsInstalled,
            appConnectionNeedsRepair: appConnectionUnavailable
        )
    }

    private var powerControls: MachinePowerControls {
        MachinePowerControls.resolve(
            state: vmModel.snapshot?.state,
            canStart: vmModel.canStart,
            canStop: vmModel.canStop,
            canSuspend: vmModel.canSuspend,
            canResume: vmModel.canResume
        )
    }

    private var engineCanRunWindows: Bool {
        AppWindowEngineStatus.resolve(
            bootProvider: appRuntimeProvider,
            providers: vmModel.snapshot?.runtimeProviders ?? []
        ).canRunWindows
    }

    private var isBusy: Bool {
        vmModel.phase == .loading
    }

    private var isLive: Bool {
        vmModel.snapshot?.state == .running || vmModel.snapshot?.state == .starting
    }

    /// One-click launch starts or resumes Windows and reconnects the guest agent itself, so an
    /// installed machine is enough; only an in-flight launch blocks another.
    private var canOpenApps: Bool {
        windowsInstalled
    }

    private var appConnectionUnavailable: Bool {
        WindowsShellCopy.appConnectionNeedsRepair(
            hasLiveAppConnection: model.hasLiveAgentConnection,
            agentUnavailable: model.agentDiagnostic?.status == .unavailable,
            windowsInstalled: windowsInstalled,
            runtimeState: vmModel.snapshot?.state
        )
    }

    private var windowsInstalled: Bool {
        vmModel.snapshot?.installEvidence.isInstalled == true
    }
}
