import AppKit
import VeilHostCore

@MainActor
private final class AppRuntimeDockMenuTarget: NSObject {
    static let shared = AppRuntimeDockMenuTarget()

    var activateMainWindowAction: (() -> Void)?
    var bringAllWindowsAppWindowsToFrontAction: (() -> Void)?
    var focusWindowsAppWindowAction: ((String) -> Void)?
    var closeWindowsAppWindowAction: ((String) -> Void)?
    var closeAllWindowsAppWindowsAction: (() -> Void)?
    var restoreWindowsAppWindowsAction: (() -> Void)?
    var launchWindowsAppByIdAction: ((String) -> Void)?
    var fulfillPendingLaunchAction: (() -> Void)?
    var repairGuestAgentForAppLaunchAction: (() -> Void)?
    var recoverRuntimeDisplayAction: (() -> Void)?
    var startVMAction: (() -> Void)?
    var stopVMAction: (() -> Void)?
    var quietWindowsWhenIdleAction: (() -> Void)?

    @objc func openVeil(_ sender: NSMenuItem) {
        activateMainWindowAction?()
    }

    @objc func bringAllWindowsAppsToFront(_ sender: NSMenuItem) {
        bringAllWindowsAppWindowsToFrontAction?()
    }

    @objc func focusWindowsAppWindow(_ sender: NSMenuItem) {
        guard let windowId = sender.representedObject as? String else {
            return
        }

        focusWindowsAppWindowAction?(windowId)
    }

    @objc func closeWindowsAppWindow(_ sender: NSMenuItem) {
        guard let windowId = sender.representedObject as? String else {
            return
        }

        closeWindowsAppWindowAction?(windowId)
    }

    @objc func closeAllWindowsApps(_ sender: NSMenuItem) {
        closeAllWindowsAppWindowsAction?()
    }

    @objc func restoreWindowsApps(_ sender: NSMenuItem) {
        restoreWindowsAppWindowsAction?()
    }

    @objc func launchWindowsApp(_ sender: NSMenuItem) {
        guard let appId = sender.representedObject as? String else {
            return
        }

        launchWindowsAppByIdAction?(appId)
    }

    @objc func fulfillPendingLaunch(_ sender: NSMenuItem) {
        fulfillPendingLaunchAction?()
    }

    @objc func repairGuestAgentForAppLaunch(_ sender: NSMenuItem) {
        repairGuestAgentForAppLaunchAction?()
    }

    @objc func recoverRuntimeDisplay(_ sender: NSMenuItem) {
        recoverRuntimeDisplayAction?()
    }

    @objc func startWindows(_ sender: NSMenuItem) {
        startVMAction?()
    }

    @objc func stopWindows(_ sender: NSMenuItem) {
        stopVMAction?()
    }

    @objc func quietWindowsWhenIdle(_ sender: NSMenuItem) {
        quietWindowsWhenIdleAction?()
    }
}

@MainActor
enum AppRuntimeDockMenuFactory {
    static func makeMenu(
        model: HostDashboardModel,
        vmModel: VMRuntimeModel,
        activateMainWindowAction: @escaping () -> Void,
        bringAllWindowsAppWindowsToFrontAction: @escaping () -> Void,
        focusWindowsAppWindowAction: @escaping (String) -> Void,
        closeWindowsAppWindowAction: @escaping (String) -> Void,
        closeAllWindowsAppWindowsAction: @escaping () -> Void,
        restoreWindowsAppWindowsAction: @escaping () -> Void,
        launchWindowsAppByIdAction: @escaping (String) -> Void,
        fulfillPendingLaunchAction: @escaping () -> Void,
        repairGuestAgentForAppLaunchAction: @escaping () -> Void,
        recoverRuntimeDisplayAction: @escaping () -> Void,
        startVMAction: @escaping () -> Void,
        stopVMAction: @escaping () -> Void,
        quietWindowsWhenIdleAction: @escaping () -> Void
    ) -> NSMenu {
        let target = AppRuntimeDockMenuTarget.shared
        target.activateMainWindowAction = activateMainWindowAction
        target.bringAllWindowsAppWindowsToFrontAction = bringAllWindowsAppWindowsToFrontAction
        target.focusWindowsAppWindowAction = focusWindowsAppWindowAction
        target.closeWindowsAppWindowAction = closeWindowsAppWindowAction
        target.closeAllWindowsAppWindowsAction = closeAllWindowsAppWindowsAction
        target.restoreWindowsAppWindowsAction = restoreWindowsAppWindowsAction
        target.launchWindowsAppByIdAction = launchWindowsAppByIdAction
        target.fulfillPendingLaunchAction = fulfillPendingLaunchAction
        target.repairGuestAgentForAppLaunchAction = repairGuestAgentForAppLaunchAction
        target.recoverRuntimeDisplayAction = recoverRuntimeDisplayAction
        target.startVMAction = startVMAction
        target.stopVMAction = stopVMAction
        target.quietWindowsWhenIdleAction = quietWindowsWhenIdleAction

        let menu = NSMenu(title: "Veil")
        menu.addItem(statusItem(statusTitle(model: model, vmModel: vmModel)))
        menu.addItem(.separator())

        if !model.mirrorSessions.isEmpty {
            menu.addItem(
                item(
                    WindowsShellCopy.bringWindowsAppsForwardTitle(
                        openAppWindowCount: model.mirrorSessions.count
                    ),
                    action: #selector(AppRuntimeDockMenuTarget.bringAllWindowsAppsToFront(_:)),
                    target: target
                )
            )
            menu.addItem(item("Open Veil", action: #selector(AppRuntimeDockMenuTarget.openVeil(_:)), target: target))
            menu.addItem(.separator())

            for session in model.mirrorSessions {
                menu.addItem(
                    item(
                        "Focus \(shortTitle(session.window.title))",
                        action: #selector(AppRuntimeDockMenuTarget.focusWindowsAppWindow(_:)),
                        target: target,
                        representedObject: session.id,
                        isEnabled: model.canFocusMirrorSession(windowId: session.id)
                    )
                )
            }

            for session in model.mirrorSessions {
                menu.addItem(
                    item(
                        "Close \(shortTitle(session.window.title))",
                        action: #selector(AppRuntimeDockMenuTarget.closeWindowsAppWindow(_:)),
                        target: target,
                        representedObject: session.id,
                        isEnabled: model.canCloseMirrorSession(windowId: session.id)
                    )
                )
            }

            menu.addItem(
                item(
                    "Close All Windows Apps",
                    action: #selector(AppRuntimeDockMenuTarget.closeAllWindowsApps(_:)),
                    target: target,
                    isEnabled: model.canCloseAllMirrorSessions
                )
            )
        } else {
            menu.addItem(item("Open Veil", action: #selector(AppRuntimeDockMenuTarget.openVeil(_:)), target: target))
        }

        if !model.restorableAppIds.isEmpty {
            menu.addItem(.separator())
            menu.addItem(
                item(
                    model.canRestoreMirrorSessions ? "Restore Previous Apps" : "Reconnect Previous Apps",
                    action: #selector(AppRuntimeDockMenuTarget.restoreWindowsApps(_:)),
                    target: target,
                    isEnabled: model.canReconnectRestoreMirrorSessions
                )
            )
        }

        if let pendingAppId = model.pendingLaunchAppId {
            let pendingAction = AppQueuedLaunchMenuState.make(
                appName: appName(for: pendingAppId, model: model),
                canRecoverRuntimeDisplay: canRecoverRuntimeDisplay(vmModel: vmModel),
                canFulfillPendingLaunch: model.canFulfillPendingLaunch,
                canRepairQueuedAppLaunch: canRepairQueuedAppLaunch(model: model, vmModel: vmModel),
                canStartWindows: vmModel.canStart,
                runtimeIsLoading: vmModel.phase == .loading
            )
            menu.addItem(.separator())
            menu.addItem(
                item(
                    pendingAction.title,
                    action: selector(for: pendingAction.kind),
                    target: target,
                    isEnabled: pendingAction.isEnabled
                )
            )
        }

        if !model.apps.isEmpty {
            menu.addItem(.separator())
            for app in model.apps.prefix(5) {
                menu.addItem(
                    item(
                        "Open \(shortTitle(app.name))",
                        action: #selector(AppRuntimeDockMenuTarget.launchWindowsApp(_:)),
                        target: target,
                        representedObject: app.id,
                        isEnabled: model.canRequestAppLaunch(appId: app.id)
                    )
                )
            }
        }

        if model.canQuietRuntimeWhenIdle {
            menu.addItem(.separator())
            menu.addItem(
                item(
                    "Quiet Windows",
                    action: #selector(AppRuntimeDockMenuTarget.quietWindowsWhenIdle(_:)),
                    target: target,
                    isEnabled: vmModel.canStop && vmModel.phase != .loading
                )
            )
        }

        menu.addItem(.separator())
        menu.addItem(
            item(
                WindowsShellCopy.openWindowsActionTitle(
                    windowsInstalled: vmModel.snapshot?.windowsInstalled == true
                ),
                action: #selector(AppRuntimeDockMenuTarget.startWindows(_:)),
                target: target,
                isEnabled: vmModel.canStart && vmModel.phase != .loading
            )
        )
        menu.addItem(
            item(
                WindowsShellCopy.closeWindowsActionTitle,
                action: #selector(AppRuntimeDockMenuTarget.stopWindows(_:)),
                target: target,
                isEnabled: vmModel.canStop && vmModel.phase != .loading
            )
        )

        return menu
    }

    private static func statusTitle(model: HostDashboardModel, vmModel: VMRuntimeModel) -> String {
        WindowsShellCopy.menuStatusTitle(
            runtimeState: vmModel.snapshot?.state,
            windowsInstalled: vmModel.snapshot?.windowsInstalled == true,
            hasLiveAppConnection: model.hasLiveAgentConnection,
            hasQueuedApp: model.pendingLaunchStatus().isQueued,
            openAppWindowCount: model.mirrorSessions.count
        )
    }

    private static func statusItem(_ title: String) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        item.isEnabled = false
        return item
    }

    private static func item(
        _ title: String,
        action: Selector,
        target: AppRuntimeDockMenuTarget,
        representedObject: Any? = nil,
        isEnabled: Bool = true
    ) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: "")
        item.target = target
        item.representedObject = representedObject
        item.isEnabled = isEnabled
        return item
    }

    private static func shortTitle(_ title: String) -> String {
        guard title.count > 26 else {
            return title
        }

        return "\(title.prefix(25))..."
    }

    private static func selector(for kind: AppQueuedLaunchMenuState.Kind) -> Selector {
        switch kind {
        case .recoverRuntimeDisplay:
            return #selector(AppRuntimeDockMenuTarget.recoverRuntimeDisplay(_:))
        case .fulfillPendingLaunch:
            return #selector(AppRuntimeDockMenuTarget.fulfillPendingLaunch(_:))
        case .repairGuestAgentForAppLaunch:
            return #selector(AppRuntimeDockMenuTarget.repairGuestAgentForAppLaunch(_:))
        case .startWindows:
            return #selector(AppRuntimeDockMenuTarget.startWindows(_:))
        }
    }

    private static func canRecoverRuntimeDisplay(vmModel: VMRuntimeModel) -> Bool {
        guard vmModel.snapshot?.state == .running || vmModel.snapshot?.state == .starting else {
            return false
        }

        return vmModel.snapshot?.latestConsoleLaunch?.previewStatus == .stale
            || vmModel.snapshot?.latestConsoleLaunch?.previewStatus == .unavailable
    }

    private static func canRepairQueuedAppLaunch(model: HostDashboardModel, vmModel: VMRuntimeModel) -> Bool {
        model.pendingLaunchStatus().willLaunchOnAgentReconnect
            && (vmModel.snapshot?.state == .running || vmModel.snapshot?.state == .starting)
            && !model.canFulfillPendingLaunch
    }

    private static func appName(for appId: String, model: HostDashboardModel) -> String {
        model.apps.first { $0.id == appId }?.name ?? "Windows App"
    }
}

struct AppQueuedLaunchMenuState: Equatable {
    enum Kind: Equatable {
        case recoverRuntimeDisplay
        case fulfillPendingLaunch
        case repairGuestAgentForAppLaunch
        case startWindows
    }

    var title: String
    var kind: Kind
    var isEnabled: Bool

    var symbolName: String {
        switch kind {
        case .recoverRuntimeDisplay:
            return "display.trianglebadge.exclamationmark"
        case .fulfillPendingLaunch:
            return "arrow.up.forward.app"
        case .repairGuestAgentForAppLaunch:
            return "bolt.horizontal.circle"
        case .startWindows:
            return "play.fill"
        }
    }

    static func make(
        appName: String,
        canRecoverRuntimeDisplay: Bool,
        canFulfillPendingLaunch: Bool,
        canRepairQueuedAppLaunch: Bool,
        canStartWindows: Bool,
        runtimeIsLoading: Bool
    ) -> AppQueuedLaunchMenuState {
        if canRecoverRuntimeDisplay {
            return AppQueuedLaunchMenuState(
                title: "Refresh Display",
                kind: .recoverRuntimeDisplay,
                isEnabled: true
            )
        }

        if canFulfillPendingLaunch {
            return AppQueuedLaunchMenuState(
                title: title(prefix: "Open Queued", appName: appName),
                kind: .fulfillPendingLaunch,
                isEnabled: true
            )
        }

        if canRepairQueuedAppLaunch {
            return AppQueuedLaunchMenuState(
                title: title(prefix: "Continue", appName: appName),
                kind: .repairGuestAgentForAppLaunch,
                isEnabled: true
            )
        }

        return AppQueuedLaunchMenuState(
            title: title(prefix: "Open Windows for", appName: appName),
            kind: .startWindows,
            isEnabled: canStartWindows && !runtimeIsLoading
        )
    }

    private static func title(prefix: String, appName: String) -> String {
        let maxMenuItemLength = 30
        let appNameLimit = max(1, maxMenuItemLength - prefix.count - 1)
        return "\(prefix) \(shortTitle(appName, maxCount: appNameLimit))"
    }

    private static func shortTitle(_ title: String, maxCount: Int) -> String {
        guard title.count > maxCount else {
            return title
        }

        let prefixCount = max(1, maxCount - 3)
        let trimmedPrefix = String(title.prefix(prefixCount))
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return "\(trimmedPrefix)..."
    }
}
