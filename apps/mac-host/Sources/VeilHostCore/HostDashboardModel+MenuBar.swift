import CoreGraphics
import Foundation
import Observation

extension HostDashboardModel {
    func dockBadgeLabel(pendingLaunch: WindowsAppRuntimePendingLaunchStatus) -> String? {
        if !mirrorSessions.isEmpty {
            return "\(mirrorSessions.count)"
        }

        if pendingLaunch.isQueued {
            return "..."
        }

        if restorableWindowCount > 0 {
            return restorableWindowCount == 1 ? "R" : "R\(restorableWindowCount)"
        }

        return nil
    }

    func menuBarIntegrationStatus(
        localRuntime: WindowsAppRuntimeLocalRuntimeStatus,
        launchPlan: WindowsAppRuntimeLaunchPlanStatus,
        pendingLaunch: WindowsAppRuntimePendingLaunchStatus,
        dailyUseReadiness: WindowsAppRuntimeDailyUseReadinessStatus
    ) -> WindowsAppRuntimeMenuBarIntegrationStatus {
        let primaryAction = menuBarPrimaryAction(
            localRuntime: localRuntime,
            launchPlan: launchPlan,
            pendingLaunch: pendingLaunch,
            dailyUseReadiness: dailyUseReadiness
        )

        return WindowsAppRuntimeMenuBarIntegrationStatus(
            isEnabled: true,
            statusTitle: menuBarStatusTitle(
                localRuntime: localRuntime,
                pendingLaunch: pendingLaunch,
                dailyUseReadiness: dailyUseReadiness
            ),
            symbolName: menuBarSymbolName(
                localRuntime: localRuntime,
                pendingLaunch: pendingLaunch,
                dailyUseReadiness: dailyUseReadiness
            ),
            primaryActionId: primaryAction.id,
            primaryActionTitle: primaryAction.title,
            primaryActionAvailable: primaryAction.isAvailable,
            canOpenMainWindow: true,
            canBringWindowsAppsForward: !mirrorSessions.isEmpty,
            canRestorePreviousApps: canRestoreMirrorSessions,
            canReconnectPreviousApps: canReconnectRestoreMirrorSessions,
            canLaunchSelectedApp: canRequestSelectedAppLaunch,
            canFulfillPendingLaunch: pendingLaunch.isQueued && canFulfillPendingLaunch
        )
    }

    private func menuBarStatusTitle(
        localRuntime: WindowsAppRuntimeLocalRuntimeStatus,
        pendingLaunch: WindowsAppRuntimePendingLaunchStatus,
        dailyUseReadiness: WindowsAppRuntimeDailyUseReadinessStatus
    ) -> String {
        if !mirrorSessions.isEmpty {
            return mirrorSessions.count == 1 ? "1 Windows App Open" : "\(mirrorSessions.count) Windows Apps Open"
        }

        if pendingLaunch.isQueued {
            guard let appName = self.appName(for: pendingLaunch.appId) else {
                return "App Waiting to Open"
            }

            return suffixedMenuItemTitle(prefix: "", title: appName, suffix: "Waiting")
                .trimmingCharacters(in: .whitespacesAndNewlines)
        }

        if canRestoreMirrorSessions || canReconnectRestoreMirrorSessions {
            return previousAppsStatusTitle()
        }

        if canRequestWindowsNotificationConsent(dailyUseReadiness: dailyUseReadiness) {
            return "Notifications Need Access"
        }

        if dailyUseReadiness.notificationBridgeRecommendedAction == "run-notification-proof" {
            return "Notifications Check Needed"
        }

        if dailyUseReadiness.recommendedAction == "prepare-sparse-package" {
            return "App Identity Needed"
        }

        if dailyUseReadiness.recommendedAction == "verify-window-capture" {
            return "App Screen Check Needed"
        }

        if dailyUseReadiness.recommendedAction == "verify-daily-use-integrations" {
            return "App Check Needed"
        }

        if hasLiveAgentConnection {
            return "Apps Ready"
        }

        switch localRuntime.state {
        case .running:
            return "Preparing Apps"
        case .starting:
            return "Opening Windows"
        case .suspended:
            return "Windows Paused"
        case .failed, .unsupported:
            return "Needs Attention"
        case .notConfigured:
            return "Set Up Windows"
        case .stopped, nil:
            return localRuntime.windowsInstalled ? "Ready to Open Apps" : "Set Up Windows"
        }
    }

    func menuBarSymbolName(
        localRuntime: WindowsAppRuntimeLocalRuntimeStatus,
        pendingLaunch: WindowsAppRuntimePendingLaunchStatus,
        dailyUseReadiness: WindowsAppRuntimeDailyUseReadinessStatus
    ) -> String {
        if !mirrorSessions.isEmpty {
            return "rectangle.stack.fill"
        }

        if pendingLaunch.isQueued {
            return "clock.fill"
        }

        if canRestoreMirrorSessions || canReconnectRestoreMirrorSessions {
            return "arrow.counterclockwise.circle.fill"
        }

        if canRequestWindowsNotificationConsent(dailyUseReadiness: dailyUseReadiness) {
            return "bell.badge"
        }

        if dailyUseReadiness.notificationBridgeRecommendedAction == "run-notification-proof" {
            return "bell.badge.fill"
        }

        if dailyUseReadiness.recommendedAction == "prepare-sparse-package" {
            return "shippingbox"
        }

        if dailyUseReadiness.recommendedAction == "verify-window-capture" {
            return "rectangle.dashed"
        }

        if dailyUseReadiness.recommendedAction == "verify-daily-use-integrations" {
            return "checkmark.seal"
        }

        switch localRuntime.state {
        case .running:
            return "display"
        case .starting:
            return "arrow.triangle.2.circlepath"
        case .failed, .unsupported:
            return "exclamationmark.triangle"
        default:
            return "play.rectangle"
        }
    }

    private func menuBarPrimaryAction(
        localRuntime: WindowsAppRuntimeLocalRuntimeStatus,
        launchPlan: WindowsAppRuntimeLaunchPlanStatus,
        pendingLaunch: WindowsAppRuntimePendingLaunchStatus,
        dailyUseReadiness: WindowsAppRuntimeDailyUseReadinessStatus
    ) -> (id: String, title: String, isAvailable: Bool) {
        if !mirrorSessions.isEmpty {
            if hasReopenEscalatedFrameStream() {
                return (
                    "windowsApps.reopenWindow",
                    "Reopen App Window",
                    true
                )
            }

            if hasEscalatedFrameStreamRecovery() {
                return (
                    "windowsApps.recoverWindowCapture",
                    "Recover App Screen",
                    true
                )
            }

            return (
                "dock.bringWindowsAppsForward",
                bringWindowsAppsForwardTitle(),
                true
            )
        }

        if pendingLaunch.isQueued {
            let appName = self.appName(for: pendingLaunch.appId) ?? "Windows App"
            if localRuntime.recommendedPowerDownCommand != nil {
                return ("runtime.stopWhenIdle", "Stop Windows", true)
            }
            if localRuntime.recommendedRecoveryCommand != nil {
                return ("runtime.recoverDisplay", "Refresh Display", true)
            }
            if canFulfillPendingLaunch {
                return ("runtime.fulfillPendingLaunch", prefixedMenuItemTitle(prefix: "Open Queued", title: appName), true)
            }
            if launchPlan.recommendedRepairCommand != nil {
                return ("runtime.repairGuestAgentForApp", prefixedMenuItemTitle(prefix: "Continue", title: appName), true)
            }
            if launchPlan.recommendedStartCommand != nil {
                return (
                    "runtime.startWindowsForApp",
                    prefixedMenuItemTitle(prefix: "Open Windows for", title: appName),
                    true
                )
            }

            return ("runtime.waitAgent", "Check App Connection", !hasLiveAgentConnection)
        }

        if canRestoreMirrorSessions || canReconnectRestoreMirrorSessions {
            return (
                canRestoreMirrorSessions ? "windowsApps.restorePrevious" : "windowsApps.reconnectRestore",
                previousAppsRestoreTitle(),
                canReconnectRestoreMirrorSessions
            )
        }

        if dailyUseReadiness.recommendedAction == "prepare-sparse-package",
           dailyUseReadiness.recommendedCommand != nil {
            return ("runtime.prepareSparsePackage", "Prepare Identity", true)
        }

        if dailyUseReadiness.recommendedAction == "verify-window-capture",
           dailyUseReadiness.recommendedCommand != nil {
            return ("dailyUse.verifyWindowCapture", "Check App Screen", true)
        }

        if canRequestWindowsNotificationConsent(dailyUseReadiness: dailyUseReadiness) {
            return ("dailyUse.requestNotificationConsent", "Allow Notifications", true)
        }

        if dailyUseReadiness.notificationBridgeRecommendedAction == "run-notification-proof" {
            return ("dailyUse.verifyNotifications", "Check Notifications", true)
        }

        if dailyUseReadiness.recommendedAction == "verify-daily-use-integrations",
           dailyUseReadiness.recommendedCommand != nil {
            return ("dailyUse.verifyIntegrations", "Verify Daily Use", true)
        }

        if canRequestSelectedAppLaunch {
            return (
                "windowsApps.launchSelected",
                prefixedMenuItemTitle(prefix: "Open", title: selectedAppDisplayName()),
                true
            )
        }

        if !hasLiveAgentConnection {
            return ("runtime.waitAgent", "Check App Connection", true)
        }

        return ("dock.openMainWindow", "Open Veil", true)
    }

    private func bringWindowsAppsForwardTitle() -> String {
        guard mirrorSessions.count == 1,
              let session = mirrorSessions.first else {
            return "Bring Windows Apps Forward"
        }

        return suffixedMenuItemTitle(
            prefix: "Bring",
            title: appName(for: session.window.appId) ?? session.window.title,
            suffix: "Forward"
        )
    }

    private func previousAppsStatusTitle() -> String {
        if restorableWindowCount > 1, let appName = singleRestorableAppName() {
            return "\(appName) Windows \(canRestoreMirrorSessions ? "Ready" : "Can Reconnect")"
        }

        guard let appName = singleRestorableAppName() else {
            return canRestoreMirrorSessions ? "Previous Apps Ready" : "Previous Apps Can Reconnect"
        }

        return suffixedMenuItemTitle(
            prefix: "",
            title: appName,
            suffix: canRestoreMirrorSessions ? "Ready" : "Can Reconnect"
        ).trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func previousAppsRestoreTitle() -> String {
        let prefix = canRestoreMirrorSessions ? "Restore" : "Reconnect"
        if restorableWindowCount > 1, let appName = singleRestorableAppName() {
            return "\(prefix) \(restorableWindowCount) \(menuItemTitle(appName)) Windows"
        }

        guard let appName = singleRestorableAppName() else {
            return canRestoreMirrorSessions ? "Restore Previous Apps" : "Reconnect Previous Apps"
        }

        return prefixedMenuItemTitle(prefix: prefix, title: appName)
    }

    private func selectedAppDisplayName() -> String {
        appName(for: selectedAppId) ?? "Windows App"
    }

    private func singleRestorableAppName() -> String? {
        guard restorableAppIds.count == 1,
              let appId = restorableAppIds.first else {
            return nil
        }

        return appName(for: appId)
    }

    func appName(for appId: String?) -> String? {
        guard let appId else {
            return nil
        }

        return apps.first { $0.id == appId }?.name
    }

    private func menuItemTitle(_ title: String, maxCount: Int = 30) -> String {
        let trimmedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedTitle.isEmpty else {
            return "Windows App"
        }

        guard trimmedTitle.count > maxCount else {
            return trimmedTitle
        }

        let prefixCount = max(1, maxCount - 3)
        let prefix = String(trimmedTitle.prefix(prefixCount))
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return "\(prefix)..."
    }

    func prefixedMenuItemTitle(prefix: String, title: String, maxCount: Int = 30) -> String {
        let itemTitleLimit = max(1, maxCount - prefix.count - 1)
        return "\(prefix) \(menuItemTitle(title, maxCount: itemTitleLimit))"
    }

    private func suffixedMenuItemTitle(
        prefix: String,
        title: String,
        suffix: String,
        maxCount: Int = 30
    ) -> String {
        let itemTitleLimit = max(1, maxCount - prefix.count - suffix.count - 2)
        return "\(prefix) \(menuItemTitle(title, maxCount: itemTitleLimit)) \(suffix)"
    }
}
