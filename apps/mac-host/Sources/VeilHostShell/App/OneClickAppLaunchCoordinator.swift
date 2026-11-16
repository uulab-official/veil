import VeilHostCore

enum OneClickAppFrameReadiness: Equatable, Sendable {
    case ready
    case waiting
    case unavailable
}

enum OneClickAppLaunchStage: Equatable, Sendable {
    case preparingApp
    case startingOrResumingWindows
    case connectingAppBridge
    case recoveringRuntime
    case repairingAppBridge(attempt: Int)
    case openingApp
    case waitingForFirstFrame
    case restartingFrameStream
    case ready
}

@MainActor
struct OneClickAppLaunchDriver<LaunchResult: Sendable> {
    var context: () -> AppLaunchLifecycleContext
    var requestLaunch: (String) async -> LaunchResult?
    var startOrResumeWindows: () async -> Bool
    var waitForGuestAgent: (Int) async -> Bool
    /// Refreshes persisted VM/console evidence after a failed health wait so the next state
    /// decision never relies on a launch snapshot from before the timeout.
    var refreshRuntimeEvidence: () async -> Void = {}
    var recoverStalledRuntime: () async -> Bool = { false }
    var repairGuestAgent: () async throws -> Void
    var fulfillLaunch: () async -> LaunchResult?
    var frameReadiness: (LaunchResult) -> OneClickAppFrameReadiness
    var waitForFirstFrame: (LaunchResult, Int) async -> OneClickAppFrameReadiness
    var restartFrameStream: (LaunchResult) async -> Bool
    var reportStage: (OneClickAppLaunchStage) -> Void
}

enum OneClickAppLaunchOutcome<LaunchResult: Sendable>: Sendable {
    case opened(LaunchResult)
    case blocked(AppLaunchLifecycleFailure)
}

@MainActor
final class OneClickAppLaunchTaskGate<Value: Sendable> {
    private var task: Task<Value, Never>?

    func cancel() {
        task?.cancel()
    }

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
    // Windows on Apple Silicon can take several minutes to move from the boot manager to the
    // interactive desktop, especially after an update or the first boot from a repaired disk.
    // Keep the one-click path in a waiting state long enough to avoid reinstalling a healthy agent
    // just because the desktop has not appeared during a short probe window.
    static let agentWaitSeconds = 90
    static let firstFrameWaitSeconds = 8

    func run<LaunchResult: Sendable>(
        appId: String,
        driver: OneClickAppLaunchDriver<LaunchResult>
    ) async -> OneClickAppLaunchOutcome<LaunchResult> {
        guard !Task.isCancelled else { return .blocked(.cancelled) }
        var repairAttemptCount = 0
        var agentWaitTimedOut = false
        var hasAttemptedRuntimeRecovery = false
        driver.reportStage(.preparingApp)

        for _ in 0..<Self.maximumTransitions {
            guard !Task.isCancelled else { return .blocked(.cancelled) }
            var context = driver.context()
            context.repairAttemptCount = repairAttemptCount
            context.agentWaitTimedOut = agentWaitTimedOut
            context.hasAttemptedRuntimeRecovery = hasAttemptedRuntimeRecovery

            switch AppLaunchLifecycleCoordinator.nextStep(context: context) {
            case .requestLaunch:
                driver.reportStage(.openingApp)
                if let immediateResult = await driver.requestLaunch(appId) {
                    return await finish(immediateResult, driver: driver)
                }
            case .startOrResumeWindows:
                driver.reportStage(.startingOrResumingWindows)
                guard await driver.startOrResumeWindows() else {
                    return .blocked(.runtimeStartFailed)
                }
                agentWaitTimedOut = false
            case .waitForGuestAgent:
                driver.reportStage(.connectingAppBridge)
                let connected = await driver.waitForGuestAgent(Self.agentWaitSeconds)
                if !connected {
                    await driver.refreshRuntimeEvidence()
                }
                agentWaitTimedOut = !connected
            case .recoverStalledRuntime:
                driver.reportStage(.recoveringRuntime)
                hasAttemptedRuntimeRecovery = true
                agentWaitTimedOut = !(await driver.recoverStalledRuntime())
            case .repairGuestAgent:
                driver.reportStage(.repairingAppBridge(attempt: repairAttemptCount + 1))
                do {
                    try await driver.repairGuestAgent()
                    repairAttemptCount += 1
                    agentWaitTimedOut = false
                } catch {
                    repairAttemptCount += 1
                    agentWaitTimedOut = true
                }
            case .fulfillQueuedLaunch:
                driver.reportStage(.openingApp)
                guard let result = await driver.fulfillLaunch() else {
                    return .blocked(.launchRejected)
                }
                return await finish(result, driver: driver)
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

    private func finish<LaunchResult: Sendable>(
        _ result: LaunchResult,
        driver: OneClickAppLaunchDriver<LaunchResult>
    ) async -> OneClickAppLaunchOutcome<LaunchResult> {
        guard !Task.isCancelled else { return .blocked(.cancelled) }
        driver.reportStage(.waitingForFirstFrame)
        let initialReadiness = await driver.waitForFirstFrame(result, Self.firstFrameWaitSeconds)
        guard !Task.isCancelled else { return .blocked(.cancelled) }
        switch initialReadiness {
        case .ready:
            driver.reportStage(.ready)
            return .opened(result)
        case .unavailable:
            return .blocked(.captureUnavailable)
        case .waiting:
            break
        }

        switch driver.frameReadiness(result) {
        case .ready:
            driver.reportStage(.ready)
            return .opened(result)
        case .unavailable:
            return .blocked(.captureUnavailable)
        case .waiting:
            break
        }

        driver.reportStage(.restartingFrameStream)
        guard !Task.isCancelled else { return .blocked(.cancelled) }
        let restarted = await driver.restartFrameStream(result)
        guard !Task.isCancelled else { return .blocked(.cancelled) }
        guard restarted else {
            return .blocked(.firstFrameRecoveryFailed)
        }

        driver.reportStage(.waitingForFirstFrame)
        let recoveredReadiness = await driver.waitForFirstFrame(result, Self.firstFrameWaitSeconds)
        guard !Task.isCancelled else { return .blocked(.cancelled) }
        switch recoveredReadiness {
        case .ready:
            driver.reportStage(.ready)
            return .opened(result)
        case .unavailable:
            return .blocked(.captureUnavailable)
        case .waiting:
            return .blocked(.firstFrameRecoveryExhausted)
        }
    }
}
