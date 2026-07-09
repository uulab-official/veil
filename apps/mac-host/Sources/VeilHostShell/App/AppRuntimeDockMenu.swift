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
        target.startVMAction = startVMAction
        target.stopVMAction = stopVMAction
        target.quietWindowsWhenIdleAction = quietWindowsWhenIdleAction

        let menu = NSMenu(title: "Veil")
        menu.addItem(item("Open Veil", action: #selector(AppRuntimeDockMenuTarget.openVeil(_:)), target: target))

        if !model.mirrorSessions.isEmpty {
            menu.addItem(.separator())
            menu.addItem(
                item(
                    model.mirrorSessions.count == 1 ? "Bring Windows App Forward" : "Bring Windows Apps Forward",
                    action: #selector(AppRuntimeDockMenuTarget.bringAllWindowsAppsToFront(_:)),
                    target: target
                )
            )

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
            menu.addItem(.separator())
            menu.addItem(
                item(
                    "Open Queued \(shortTitle(appName(for: pendingAppId, model: model)))",
                    action: #selector(AppRuntimeDockMenuTarget.fulfillPendingLaunch(_:)),
                    target: target,
                    isEnabled: model.canFulfillPendingLaunch
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
                "Start Windows",
                action: #selector(AppRuntimeDockMenuTarget.startWindows(_:)),
                target: target,
                isEnabled: vmModel.canStart && vmModel.phase != .loading
            )
        )
        menu.addItem(
            item(
                "Stop Windows",
                action: #selector(AppRuntimeDockMenuTarget.stopWindows(_:)),
                target: target,
                isEnabled: vmModel.canStop && vmModel.phase != .loading
            )
        )

        return menu
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

    private static func appName(for appId: String, model: HostDashboardModel) -> String {
        model.apps.first { $0.id == appId }?.name ?? "Windows App"
    }
}
