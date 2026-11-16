import AppKit
import SwiftUI
import VeilHostCore

@MainActor
final class OneClickAppWindowPresentationGate {
    private struct LaunchIdentity: Equatable {
        var appId: String
        var windowId: String?
    }

    private var activeLaunch: LaunchIdentity?
    private var suppressedAppIds: Set<String> = []

    var keepsLauncherVisible: Bool {
        activeLaunch != nil || !suppressedAppIds.isEmpty
    }

    @discardableResult
    func begin(requestedAppId: String, pendingAppId: String?) -> Bool {
        guard activeLaunch == nil else {
            return false
        }

        activeLaunch = LaunchIdentity(appId: pendingAppId ?? requestedAppId, windowId: nil)
        return true
    }

    func bindLaunchResult(appId: String, windowId: String) {
        guard activeLaunch != nil else {
            return
        }

        activeLaunch = LaunchIdentity(appId: appId, windowId: windowId)
    }

    func finishBlockedLaunch() {
        if let activeLaunch {
            suppressedAppIds.insert(activeLaunch.appId)
        }
        activeLaunch = nil
    }

    func authorizeLaunchPresentation(
        appId: String,
        windowId: String,
        decision: WindowsAppWindowPresentationDecision
    ) -> Bool {
        guard decision == .ready else {
            return false
        }
        if let activeLaunch,
           activeLaunch != LaunchIdentity(appId: appId, windowId: windowId) {
            return false
        }

        suppressedAppIds.remove(appId)
        activeLaunch = nil
        return true
    }

    func authorizeUserPresentation(
        appId: String,
        windowId: String,
        decision: WindowsAppWindowPresentationDecision
    ) -> Bool {
        guard decision == .ready,
              activeLaunch?.appId != appId else {
            return false
        }

        suppressedAppIds.remove(appId)
        return true
    }

    func allowsEventDrivenPresentation(
        appId: String,
        windowId: String,
        isAlreadyVisible: Bool = false
    ) -> Bool {
        if isAlreadyVisible {
            return true
        }
        guard !suppressedAppIds.contains(appId) else {
            return false
        }
        guard let activeLaunch else {
            return true
        }
        guard appId == activeLaunch.appId else {
            return true
        }

        return false
    }

    func abandonActiveLaunch() {
        activeLaunch = nil
    }
}

@MainActor
final class OneClickAppFrameMutationGate {
    private var launchReserved = false
    private var automaticMaintenanceInFlight = false
    private var manualRecoveryInFlight = false
    private var automaticMaintenanceCompletionWaiters: [CheckedContinuation<Void, Never>] = []

    @discardableResult
    func reserveLaunch() -> Bool {
        guard !launchReserved else {
            return false
        }

        launchReserved = true
        return true
    }

    func abandonLaunchReservation() {
        launchReserved = false
    }

    func runReservedLaunch(_ operation: () async -> Void) async {
        guard launchReserved else {
            return
        }
        defer { launchReserved = false }

        if automaticMaintenanceInFlight || manualRecoveryInFlight {
            await withCheckedContinuation { continuation in
                automaticMaintenanceCompletionWaiters.append(continuation)
            }
        }

        await operation()
    }

    @discardableResult
    func runAutomaticMaintenance(_ operation: () async -> Void) async -> Bool {
        guard !launchReserved,
              !manualRecoveryInFlight,
              !automaticMaintenanceInFlight else {
            return false
        }

        automaticMaintenanceInFlight = true
        await operation()
        automaticMaintenanceInFlight = false

        resumeMaintenanceWaiters()
        return true
    }

    @discardableResult
    func runManualRecovery(_ operation: () async -> Void) async -> Bool {
        guard !Task.isCancelled, !launchReserved,
              !automaticMaintenanceInFlight, !manualRecoveryInFlight else { return false }
        manualRecoveryInFlight = true
        defer {
            manualRecoveryInFlight = false
            resumeMaintenanceWaiters()
        }
        await operation()
        return true
    }

    private func resumeMaintenanceWaiters() {
        let waiters = automaticMaintenanceCompletionWaiters
        automaticMaintenanceCompletionWaiters.removeAll()
        for waiter in waiters {
            waiter.resume()
        }
    }
}

@MainActor
enum OneClickAppLaunchOwnership {
    static func run<Value: Sendable>(
        requestedAppId: String,
        pendingAppId: String?,
        presentationGate: OneClickAppWindowPresentationGate,
        mutationGate: OneClickAppFrameMutationGate,
        operation: () async -> Value,
        finalize: (Value) -> Void
    ) async -> Value? {
        guard presentationGate.begin(
            requestedAppId: requestedAppId,
            pendingAppId: pendingAppId
        ) else {
            return nil
        }
        guard mutationGate.reserveLaunch() else {
            presentationGate.abandonActiveLaunch()
            return nil
        }

        var result: Value?
        await mutationGate.runReservedLaunch {
            let value = await operation()
            finalize(value)
            presentationGate.abandonActiveLaunch()
            result = value
        }
        if result == nil {
            presentationGate.abandonActiveLaunch()
        }
        return result
    }
}
