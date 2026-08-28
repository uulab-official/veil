import VeilHostCore

@MainActor
struct OneClickAppLaunchDriver<LaunchResult: Sendable> {
    var context: () -> AppLaunchLifecycleContext
    var requestLaunch: (String) async -> LaunchResult?
    var startOrResumeWindows: () async -> Bool
    var waitForGuestAgent: (Int) async -> Bool
    var recoverStalledRuntime: () async -> Bool = { false }
    var repairGuestAgent: () async throws -> Void
    var fulfillLaunch: () async -> LaunchResult?
}

enum OneClickAppLaunchOutcome<LaunchResult: Sendable>: Sendable {
    case opened(LaunchResult)
    case blocked(AppLaunchLifecycleFailure)
}

@MainActor
final class OneClickAppLaunchTaskGate<Value: Sendable> {
    private var task: Task<Value, Never>?

    func run(_ operation: @escaping @MainActor () async -> Value) async -> Value {
        if let task {
            return await task.value
        }

        let newTask = Task { @MainActor in
            await operation()
        }
        task = newTask
        let value = await newTask.value
        task = nil
        return value
    }
}

@MainActor
struct OneClickAppLaunchCoordinator {
    static let maximumTransitions = 12
    static let agentWaitSeconds = 30

    func run<LaunchResult: Sendable>(
        appId: String,
        driver: OneClickAppLaunchDriver<LaunchResult>
    ) async -> OneClickAppLaunchOutcome<LaunchResult> {
        var repairAttemptCount = 0
        var agentWaitTimedOut = false
        var hasAttemptedRuntimeRecovery = false

        for _ in 0..<Self.maximumTransitions {
            var context = driver.context()
            context.repairAttemptCount = repairAttemptCount
            context.agentWaitTimedOut = agentWaitTimedOut
            context.hasAttemptedRuntimeRecovery = hasAttemptedRuntimeRecovery

            switch AppLaunchLifecycleCoordinator.nextStep(context: context) {
            case .requestLaunch:
                if let immediateResult = await driver.requestLaunch(appId) {
                    return .opened(immediateResult)
                }
            case .startOrResumeWindows:
                guard await driver.startOrResumeWindows() else {
                    return .blocked(.runtimeStartFailed)
                }
                agentWaitTimedOut = false
            case .waitForGuestAgent:
                agentWaitTimedOut = !(await driver.waitForGuestAgent(Self.agentWaitSeconds))
            case .recoverStalledRuntime:
                hasAttemptedRuntimeRecovery = true
                agentWaitTimedOut = !(await driver.recoverStalledRuntime())
            case .repairGuestAgent:
                do {
                    try await driver.repairGuestAgent()
                    repairAttemptCount += 1
                    agentWaitTimedOut = false
                } catch {
                    repairAttemptCount += 1
                    agentWaitTimedOut = true
                }
            case .fulfillQueuedLaunch:
                guard let result = await driver.fulfillLaunch() else {
                    return .blocked(.launchRejected)
                }
                return .opened(result)
            case .blockedGuestAgentEndpoint:
                return .blocked(.guestAgentEndpointUnavailable)
            case .blockedRuntimeSetup:
                return .blocked(.runtimeSetupIncomplete)
            case .blockedGuestAgentRecovery:
                return .blocked(.guestAgentRecoveryExhausted)
            }
        }

        return .blocked(.transitionBudgetExceeded)
    }
}
