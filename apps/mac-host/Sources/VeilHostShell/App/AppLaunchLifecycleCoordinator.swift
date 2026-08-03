import VeilHostCore

enum AppLaunchLifecycleStep: Equatable {
    case requestLaunch
    case fulfillQueuedLaunch
    case startOrResumeWindows
    case waitForGuestAgent
    case blockedGuestAgentEndpoint
    case blockedRuntimeSetup
}

struct AppLaunchLifecycleCoordinator {
    static func nextStep(
        hasQueuedLaunch: Bool,
        canFulfillQueuedLaunch: Bool,
        hasLiveAgentConnection: Bool,
        runtimeState: VMRuntimeState?,
        canStartOrResume: Bool,
        guestAgentEndpointAvailable: Bool
    ) -> AppLaunchLifecycleStep {
        if canFulfillQueuedLaunch {
            return .fulfillQueuedLaunch
        }

        guard hasQueuedLaunch else {
            return .requestLaunch
        }

        guard guestAgentEndpointAvailable else {
            return .blockedGuestAgentEndpoint
        }

        if hasLiveAgentConnection {
            return .fulfillQueuedLaunch
        }

        switch runtimeState {
        case .running, .starting:
            return .waitForGuestAgent
        case .stopped, .suspended:
            return canStartOrResume ? .startOrResumeWindows : .blockedRuntimeSetup
        default:
            return canStartOrResume ? .startOrResumeWindows : .blockedRuntimeSetup
        }
    }
}
