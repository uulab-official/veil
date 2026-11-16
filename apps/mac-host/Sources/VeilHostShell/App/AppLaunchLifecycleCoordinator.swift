import VeilHostCore

enum AppLaunchLifecycleStep: Equatable {
    case requestLaunch
    case fulfillQueuedLaunch
    case startOrResumeWindows
    case waitForGuestAgent
    case recoverStalledRuntime
    case repairGuestAgent
    case blockedGuestAgentEndpoint
    case blockedRuntimeSetup
    case blockedGuestAgentRecovery
}

struct AppLaunchLifecycleContext: Equatable, Sendable {
    var hasQueuedLaunch: Bool
    var canFulfillQueuedLaunch: Bool
    var hasLiveAgentConnection: Bool
    var runtimeState: VMRuntimeState?
    var canStartOrResume: Bool
    var guestAgentEndpointAvailable: Bool
    var agentWaitTimedOut: Bool
    var repairAttemptCount: Int
    var canRecoverStalledRuntime = false
    var hasAttemptedRuntimeRecovery = false
    /// A recent blank embedded console is evidence that Windows is still leaving the boot manager.
    /// Keep waiting for the guest agent in that state instead of reinstalling a healthy agent.
    var isConsoleStillBooting = false
}

enum AppLaunchLifecycleFailure: Error, Equatable, Sendable {
    case guestAgentEndpointUnavailable
    case runtimeSetupIncomplete
    case runtimeStartFailed
    case guestAgentRecoveryExhausted
    case launchRejected
    case transitionBudgetExceeded
    case captureUnavailable
    case firstFrameRecoveryFailed
    case firstFrameRecoveryExhausted
    case cancelled

    var userMessage: String {
        switch self {
        case .guestAgentEndpointUnavailable:
            return String(localized: "This Windows runtime has no available app connection. Open Windows Settings to choose the supported QEMU/HVF runtime.")
        case .runtimeSetupIncomplete:
            return String(localized: "Finish Windows setup before opening this app.")
        case .runtimeStartFailed:
            return String(localized: "Windows could not start or resume. Open the recovery display for the exact boot error.")
        case .guestAgentRecoveryExhausted:
            return String(localized: "Windows is running, but the app connection did not recover after two attempts. Open recovery to repair Veil Agent.")
        case .launchRejected:
            return String(localized: "Windows connected, but the selected app did not open. Refresh the app list and try once more.")
        case .transitionBudgetExceeded:
            return String(localized: "Veil stopped the app launch because its state did not settle. Refresh Windows status before retrying.")
        case .captureUnavailable:
            return String(localized: "Windows opened the app, but app screen sharing is unavailable. Open recovery to check the Windows app connection.")
        case .firstFrameRecoveryFailed:
            return String(localized: "Windows opened the app, but Veil could not restart its screen. Use Refresh App Screen and try again.")
        case .firstFrameRecoveryExhausted:
            return String(localized: "Windows opened the app, but its screen did not arrive after one recovery attempt. Open recovery for the next safe action.")
        case .cancelled:
            return String(localized: "App opening was cancelled. You can open the app again when you are ready.")
        }
    }
}

struct AppLaunchLifecycleCoordinator {
    static let maximumRepairAttempts = 2

    static func nextStep(context: AppLaunchLifecycleContext) -> AppLaunchLifecycleStep {
        if context.canFulfillQueuedLaunch {
            return .fulfillQueuedLaunch
        }

        guard context.hasQueuedLaunch else {
            return .requestLaunch
        }

        guard context.guestAgentEndpointAvailable else {
            return .blockedGuestAgentEndpoint
        }

        if context.hasLiveAgentConnection {
            return .fulfillQueuedLaunch
        }

        switch context.runtimeState {
        case .running, .starting:
            if context.agentWaitTimedOut {
                if context.isConsoleStillBooting {
                    return .waitForGuestAgent
                }
                if context.canRecoverStalledRuntime && !context.hasAttemptedRuntimeRecovery {
                    return .recoverStalledRuntime
                }
                return context.repairAttemptCount < maximumRepairAttempts
                    ? .repairGuestAgent
                    : .blockedGuestAgentRecovery
            }
            return .waitForGuestAgent
        case .stopped, .suspended:
            return context.canStartOrResume ? .startOrResumeWindows : .blockedRuntimeSetup
        default:
            return context.canStartOrResume ? .startOrResumeWindows : .blockedRuntimeSetup
        }
    }

    static func nextStep(
        hasQueuedLaunch: Bool,
        canFulfillQueuedLaunch: Bool,
        hasLiveAgentConnection: Bool,
        runtimeState: VMRuntimeState?,
        canStartOrResume: Bool,
        guestAgentEndpointAvailable: Bool
    ) -> AppLaunchLifecycleStep {
        nextStep(
            context: AppLaunchLifecycleContext(
                hasQueuedLaunch: hasQueuedLaunch,
                canFulfillQueuedLaunch: canFulfillQueuedLaunch,
                hasLiveAgentConnection: hasLiveAgentConnection,
                runtimeState: runtimeState,
                canStartOrResume: canStartOrResume,
                guestAgentEndpointAvailable: guestAgentEndpointAvailable,
                agentWaitTimedOut: false,
                repairAttemptCount: 0
            )
        )
    }
}
