import Foundation
import Testing

@testable import VeilHostCore

@Suite("Host dashboard model")
struct HostDashboardModelTests {
    @Test("loads agent overview into dashboard state")
    @MainActor
    func loadsAgentOverview() async throws {
        let service = FakeDashboardService()
        let model = HostDashboardModel(service: service)

        await model.load()

        #expect(model.phase == .connected)
        #expect(model.health?.agentVersion == "0.1.0")
        #expect(model.apps.map(\.id) == ["winapp_notepad"])
        #expect(model.selectedAppId == "winapp_notepad")
        #expect(model.selectedApp?.name == "Notepad")
        #expect(model.canLaunchSelectedApp)
        #expect(model.statusText == "Connected to Windows agent 0.1.0")
        #expect(model.connectionMode == .agent)
        #expect(model.hasLiveAgentConnection)
        #expect(model.guestAgentInstallEvidence?.kind == .guestAgent)
        #expect(model.guestAgentInstallEvidence?.isInstalled == true)
        #expect(model.errorMessage == nil)
    }

    @Test("one-screen hero readiness follows supported primary action ids")
    @MainActor
    func oneScreenHeroReadinessFollowsSupportedPrimaryActionIds() {
        let model = HostDashboardModel(service: FakeDashboardService())
        let launcherVisibility = WindowsAppRuntimeLauncherVisibilityStatus(
            isEnabled: true,
            canOpenMainWindow: true,
            shouldHideMainWindow: false,
            keepsDockMenuAvailable: true,
            recommendedAction: "show-launcher",
            reason: "Launcher visible."
        )
        let visibleSurfacePolicy = WindowsAppRuntimeVisibleSurfacePolicyStatus(
            isEnabled: true,
            primarySurface: "launcher",
            expectedVisibleSurfaceCount: 1,
            shouldHideLauncher: false,
            keepsRecoveryDisplayManual: true,
            reason: "Launcher surface."
        )
        let macWindowIntegration = WindowsAppRuntimeMacWindowIntegrationStatus(
            isEnabled: true,
            acceptsGuestWindowEvents: false,
            opensMacWindowsAutomatically: true,
            hidesLauncherWhenMirroring: false,
            mirroredWindowCount: 0,
            foregroundableWindowCount: 0,
            pendingFrameWindowCount: 0,
            streamingWindowCount: 0,
            freshFrameWindowCount: 0,
            delayedFrameWindowCount: 0,
            staleFrameWindowCount: 0,
            reason: "Waiting."
        )
        let menuBarIntegration = WindowsAppRuntimeMenuBarIntegrationStatus(
            isEnabled: true,
            statusTitle: "Ready",
            symbolName: "play.rectangle",
            primaryActionId: "windowsApps.launchSelected",
            primaryActionTitle: "Open App",
            primaryActionAvailable: true,
            canOpenMainWindow: true,
            canBringWindowsAppsForward: false,
            canRestorePreviousApps: false,
            canReconnectPreviousApps: false,
            canLaunchSelectedApp: true,
            canFulfillPendingLaunch: false
        )

        let supported = model.oneScreenUXStatus(
            launcherVisibility: launcherVisibility,
            visibleSurfacePolicy: visibleSurfacePolicy,
            macWindowIntegration: macWindowIntegration,
            menuBarIntegration: menuBarIntegration,
            primaryNextAction: WindowsAppRuntimePrimaryNextActionStatus(
                id: "closeOrRestore",
                title: "Close Apps",
                source: "releaseGate",
                isAvailable: true,
                runsInApp: true,
                actionId: "windowsApps.closeAll",
                command: "veil-vmctl app-runtime-action --json --action close-all",
                reason: "Close all app windows."
            )
        )
        let unsupported = model.oneScreenUXStatus(
            launcherVisibility: launcherVisibility,
            visibleSurfacePolicy: visibleSurfacePolicy,
            macWindowIntegration: macWindowIntegration,
            menuBarIntegration: menuBarIntegration,
            primaryNextAction: WindowsAppRuntimePrimaryNextActionStatus(
                id: "futureAction",
                title: "Future Action",
                source: "releaseGate",
                isAvailable: true,
                runsInApp: true,
                actionId: "runtime.futureAction",
                command: "veil-vmctl app-runtime-action --json --action future",
                reason: "Future app action."
            )
        )

        #expect(supported.heroRunsPrimaryAction)
        #expect(unsupported.heroRunsPrimaryAction == false)

        let packageIdentitySupported = model.oneScreenUXStatus(
            launcherVisibility: launcherVisibility,
            visibleSurfacePolicy: visibleSurfacePolicy,
            macWindowIntegration: macWindowIntegration,
            menuBarIntegration: menuBarIntegration,
            primaryNextAction: WindowsAppRuntimePrimaryNextActionStatus(
                id: "openWindowsApp",
                title: "Prepare Identity",
                source: "releaseGate",
                isAvailable: true,
                runsInApp: true,
                actionId: "runtime.prepareSparsePackage",
                command: "veil-vmctl app-runtime-action --json --action prepare-sparse-package --wait-seconds 120",
                reason: "Prepare package identity before Daily Use checks."
            )
        )

        #expect(packageIdentitySupported.heroRunsPrimaryAction)

        let releaseGate = WindowsAppRuntimeReleaseGateStatus(
            requiredStepCount: 1,
            passingStepCount: 0,
            isPassing: false,
            recommendedAction: "closeOrRestore",
            steps: [],
            screenshotSlots: [],
            reason: "One app-flow step remains."
        )
        let supportedPrimaryNextAction = WindowsAppRuntimePrimaryNextActionStatus(
            id: "closeOrRestore",
            title: "Close Apps",
            source: "releaseGate",
            isAvailable: true,
            runsInApp: true,
            actionId: "windowsApps.closeAll",
            command: "veil-vmctl app-runtime-action --json --action close-all",
            reason: "Close all app windows."
        )
        let supportedOnboarding = model.launchOnboardingStatus(
            releaseGate: releaseGate,
            primaryNextAction: supportedPrimaryNextAction,
            oneScreenUX: supported
        )
        let unsupportedOnboarding = model.launchOnboardingStatus(
            releaseGate: releaseGate,
            primaryNextAction: WindowsAppRuntimePrimaryNextActionStatus(
                id: "futureAction",
                title: "Future Action",
                source: "releaseGate",
                isAvailable: true,
                runsInApp: true,
                actionId: "runtime.futureAction",
                command: "veil-vmctl app-runtime-action --json --action future",
                reason: "Future app action."
            ),
            oneScreenUX: unsupported
        )

        #expect(supportedOnboarding.state == "continue-in-app")
        #expect(supportedOnboarding.canContinueInApp)
        #expect(supportedOnboarding.primaryActionId == "windowsApps.closeAll")

        let packageIdentityOnboarding = model.launchOnboardingStatus(
            releaseGate: releaseGate,
            primaryNextAction: WindowsAppRuntimePrimaryNextActionStatus(
                id: "openWindowsApp",
                title: "Prepare Identity",
                source: "releaseGate",
                isAvailable: true,
                runsInApp: true,
                actionId: "runtime.prepareSparsePackage",
                command: "veil-vmctl app-runtime-action --json --action prepare-sparse-package --wait-seconds 120",
                reason: "Prepare package identity before Daily Use checks."
            ),
            oneScreenUX: packageIdentitySupported
        )
        #expect(packageIdentityOnboarding.state == "continue-in-app")
        #expect(packageIdentityOnboarding.canContinueInApp)
        #expect(packageIdentityOnboarding.currentStepDetail == "Prepare Windows app identity, then continue Daily Use checks from Veil.")

        #expect(unsupportedOnboarding.state == "external-check")
        #expect(unsupportedOnboarding.canContinueInApp == false)
    }

    @Test("marks phase failed and keeps recovery diagnostics when waiting for the live agent times out")
    @MainActor
    func waitForLiveAgentConnectionMarksPhaseFailedWhenUnavailable() async throws {
        let service = FakeDashboardService()
        let model = HostDashboardModel(service: service)

        let report = await model.waitForLiveAgentConnection(timeoutSeconds: 1)

        #expect(report.status == .unavailable)
        #expect(model.latestAgentWait == report)
        #expect(model.phase == .failed)
        #expect(model.errorMessage != nil)
        #expect(model.agentDiagnostic?.status == .unavailable)
    }

    @Test("reloads overview after waiting for a live agent connection")
    @MainActor
    func waitForLiveAgentConnectionReloadsOverviewAfterConnection() async throws {
        let service = FakeDashboardService(
            agentWaitReport: AgentConnectionWaitReport(
                endpoint: "ws://127.0.0.1:18444",
                status: .connected,
                waitedSeconds: 1,
                attempts: 2,
                connectedAt: Date(timeIntervalSince1970: 1_000),
                diagnostic: .connected(endpoint: "ws://127.0.0.1:18444", health: .fixture),
                nextActions: [
                    "Run `veil-vmctl app-runtime-status --json` to inspect app launch readiness."
                ]
            )
        )
        let model = HostDashboardModel(service: service)

        let report = await model.waitForLiveAgentConnection(endpoint: "ws://127.0.0.1:18444", timeoutSeconds: 5)

        #expect(report.status == .connected)
        #expect(model.latestAgentWait == report)
        #expect(model.agentDiagnostic == nil)
        #expect(model.hasLiveAgentConnection)
        #expect(service.loadCount == 1)
    }

    @Test("stores Notepad launch result")
    @MainActor
    func storesNotepadLaunchResult() async throws {
        let service = FakeDashboardService()
        let model = HostDashboardModel(service: service)

        await model.launchNotepad()

        #expect(model.phase == .connected)
        #expect(model.lastLaunch?.launch.processId == 4912)
        #expect(model.lastLaunch?.window.windowId == "hwnd:0003029A")
        #expect(model.activeWindows.map(\.windowId) == ["hwnd:0003029A"])
        #expect(model.mirrorSessions.map(\.id) == ["hwnd:0003029A"])
        #expect(model.mirrorSessions.first?.captureState == .unavailable)
        #expect(model.selectedAppId == "winapp_notepad")
        #expect(model.canLaunchSelectedApp)
        #expect(model.statusText == "Launched Untitled - Notepad")
    }

    @Test("stores a pending capture mirror session when the live agent supports capture")
    @MainActor
    func storesPendingCaptureMirrorSessionWhenAgentSupportsCapture() async throws {
        let service = FakeDashboardService(health: .captureReady)
        let model = HostDashboardModel(service: service)

        await model.launchNotepad()

        let session = try #require(model.mirrorSessions.first)
        #expect(session.id == "hwnd:0003029A")
        #expect(session.window.title == "Untitled - Notepad")
        #expect(session.connectionMode == .agent)
        #expect(session.captureState == .pending)
        #expect(service.frameSubscriptions == ["hwnd:0003029A"])
    }

    @Test("stores the latest frame on the matching mirror session")
    @MainActor
    func storesLatestFrameOnMatchingMirrorSession() async throws {
        let service = FakeDashboardService(health: .captureReady)
        let model = HostDashboardModel(service: service)

        await model.launchNotepad()
        model.receiveWindowFrame(.notepadFirstFrame)

        let session = try #require(model.mirrorSessions.first)
        #expect(session.captureState == .streaming)
        #expect(session.latestFrame?.windowId == "hwnd:0003029A")
        #expect(session.latestFrame?.frameId == "frame_000001")
        #expect(session.latestFrame?.sequence == 1)
        #expect(session.latestFrame?.format == "png")
        #expect(session.latestFrame?.encodedData.hasPrefix("iVBOR") == true)
        #expect(session.frameTiming?.receivedFrameCount == 1)
        #expect(session.frameTiming?.latestFrameIntervalMilliseconds == nil)
    }

    @Test("records frame timing and cadence for mirrored windows")
    @MainActor
    func recordsFrameTimingAndCadenceForMirroredWindows() async throws {
        let service = FakeDashboardService(health: .captureReady)
        let model = HostDashboardModel(service: service)
        let firstFrameAt = Date(timeIntervalSince1970: 1_000)
        let secondFrameAt = Date(timeIntervalSince1970: 1_000.125)

        await model.launchNotepad()
        model.receiveWindowFrame(.notepadFirstFrame, receivedAt: firstFrameAt)
        model.receiveWindowFrame(.notepadSecondFrame, receivedAt: secondFrameAt)

        let session = try #require(model.mirrorSessions.first)
        #expect(session.latestFrame?.frameId == "frame_000002")
        #expect(session.frameTiming?.firstFrameReceivedAt == firstFrameAt)
        #expect(session.frameTiming?.latestFrameReceivedAt == secondFrameAt)
        #expect(session.frameTiming?.latestFrameIntervalMilliseconds == 125)
        #expect(session.frameTiming?.receivedFrameCount == 2)

        let report = model.runtimeStatusReport(generatedAt: Date(timeIntervalSince1970: 1_000.625))
        let windowStatus = try #require(report.mirrorSessions.first)
        #expect(windowStatus.frameStreamStatus == .fresh)
        #expect(windowStatus.latestFrameReceivedAt == secondFrameAt)
        #expect(windowStatus.latestFrameAgeMilliseconds == 500)
        #expect(windowStatus.latestFrameIntervalMilliseconds == 125)
        #expect(windowStatus.receivedFrameCount == 2)
        #expect(windowStatus.frameStreamRecommendedAction == "none")
        #expect(windowStatus.frameStreamRestartCount == 0)
        #expect(windowStatus.latestFrameStreamRestartedAt == nil)
        #expect(windowStatus.frameStreamRecoveryEscalated == false)
        #expect(windowStatus.frameStreamReopenEscalated == false)
        #expect(report.macWindowIntegration.freshFrameWindowCount == 1)
        #expect(report.macWindowIntegration.delayedFrameWindowCount == 0)
        #expect(report.macWindowIntegration.staleFrameWindowCount == 0)
    }

    @Test("reports stale frame streams and exposes restart action")
    @MainActor
    func reportsStaleFrameStreamsAndRestartAction() async throws {
        let service = FakeDashboardService(health: .captureReady)
        let model = HostDashboardModel(service: service)
        let frameAt = Date(timeIntervalSince1970: 1_000)

        await model.launchNotepad()
        model.receiveWindowFrame(.notepadFirstFrame, receivedAt: frameAt)

        let report = model.runtimeStatusReport(generatedAt: Date(timeIntervalSince1970: 1_006.250))
        let windowStatus = try #require(report.mirrorSessions.first)
        let restartAction = try #require(report.actions.first { $0.id == "windowsApps.restartFrameStream" })

        #expect(windowStatus.frameStreamStatus == .stale)
        #expect(windowStatus.latestFrameAgeMilliseconds == 6_250)
        #expect(windowStatus.frameStreamRecommendedAction == "restart-frame-subscription")
        #expect(windowStatus.frameStreamRestartCount == 0)
        #expect(windowStatus.frameStreamRecoveryEscalated == false)
        #expect(windowStatus.frameStreamReopenEscalated == false)
        #expect(report.macWindowIntegration.staleFrameWindowCount == 1)
        #expect(restartAction.title == "Restart App Screen")
        #expect(restartAction.isAvailable)
    }

    @Test("restarts frame subscription for a mirrored window")
    @MainActor
    func restartsFrameSubscriptionForMirroredWindow() async throws {
        let service = FakeDashboardService(health: .captureReady)
        let model = HostDashboardModel(service: service)

        await model.launchNotepad()
        model.receiveWindowFrame(.notepadFirstFrame, receivedAt: Date(timeIntervalSince1970: 1_000))

        let restartedAt = Date(timeIntervalSince1970: 1_001)
        let didRestart = await model.restartFrameSubscription(
            windowId: "hwnd:0003029A",
            restartedAt: restartedAt
        )
        let session = try #require(model.mirrorSessions.first)

        #expect(didRestart)
        #expect(service.frameUnsubscriptions == ["hwnd:0003029A"])
        #expect(service.frameSubscriptions == ["hwnd:0003029A", "hwnd:0003029A"])
        #expect(session.captureState == .pending)
        #expect(session.latestFrame == nil)
        #expect(session.frameTiming == nil)
        #expect(session.frameStreamRestartCount == 1)
        #expect(session.latestFrameStreamRestartedAt == restartedAt)
    }

    @Test("restarts all stale frame subscriptions")
    @MainActor
    func restartsAllStaleFrameSubscriptions() async throws {
        let service = FakeDashboardService(health: .captureReady)
        let model = HostDashboardModel(service: service)

        await model.launchNotepad()
        model.receiveWindowFrame(.notepadFirstFrame, receivedAt: Date(timeIntervalSince1970: 1_000))

        let restartedWindowIds = await model.restartStaleFrameSubscriptions(
            generatedAt: Date(timeIntervalSince1970: 1_006)
        )

        #expect(restartedWindowIds == ["hwnd:0003029A"])
        #expect(service.frameUnsubscriptions == ["hwnd:0003029A"])
        #expect(service.frameSubscriptions == ["hwnd:0003029A", "hwnd:0003029A"])
        #expect(model.mirrorSessions.first?.captureState == .pending)
        #expect(model.mirrorSessions.first?.frameStreamRestartCount == 1)
        #expect(model.mirrorSessions.first?.latestFrameStreamRestartedAt == Date(timeIntervalSince1970: 1_006))
    }

    @Test("escalates frame stream recovery after repeated stale restarts")
    @MainActor
    func escalatesFrameStreamRecoveryAfterRepeatedStaleRestarts() async throws {
        let service = FakeDashboardService(health: .captureReady)
        let model = HostDashboardModel(service: service)

        await model.launchNotepad()
        model.receiveWindowFrame(.notepadFirstFrame, receivedAt: Date(timeIntervalSince1970: 1_000))
        await model.restartFrameSubscription(
            windowId: "hwnd:0003029A",
            restartedAt: Date(timeIntervalSince1970: 1_001)
        )
        model.receiveWindowFrame(.notepadSecondFrame, receivedAt: Date(timeIntervalSince1970: 1_002))
        await model.restartFrameSubscription(
            windowId: "hwnd:0003029A",
            restartedAt: Date(timeIntervalSince1970: 1_003)
        )
        model.receiveWindowFrame(.notepadFirstFrame, receivedAt: Date(timeIntervalSince1970: 1_004))

        let report = model.runtimeStatusReport(generatedAt: Date(timeIntervalSince1970: 1_010))
        let windowStatus = try #require(report.mirrorSessions.first)
        let recoverAction = try #require(report.actions.first { $0.id == "windowsApps.recoverWindowCapture" })

        #expect(windowStatus.frameStreamStatus == .stale)
        #expect(windowStatus.frameStreamRecommendedAction == "recover-window-capture")
        #expect(windowStatus.frameStreamRestartCount == 2)
        #expect(windowStatus.latestFrameStreamRestartedAt == Date(timeIntervalSince1970: 1_003))
        #expect(windowStatus.frameStreamRecoveryEscalated)
        #expect(windowStatus.frameStreamReopenEscalated == false)
        #expect(recoverAction.title == "Recover App Screen")
        #expect(recoverAction.isAvailable)
    }

    @Test("recovers escalated frame capture with focus and resubscribe")
    @MainActor
    func recoversEscalatedFrameCaptureWithFocusAndResubscribe() async throws {
        let service = FakeDashboardService(health: .captureReady)
        let model = HostDashboardModel(service: service)

        await model.launchNotepad()
        model.receiveWindowFrame(.notepadFirstFrame, receivedAt: Date(timeIntervalSince1970: 1_000))
        await model.restartFrameSubscription(
            windowId: "hwnd:0003029A",
            restartedAt: Date(timeIntervalSince1970: 1_001)
        )
        model.receiveWindowFrame(.notepadSecondFrame, receivedAt: Date(timeIntervalSince1970: 1_002))
        await model.restartFrameSubscription(
            windowId: "hwnd:0003029A",
            restartedAt: Date(timeIntervalSince1970: 1_003)
        )
        model.receiveWindowFrame(.notepadFirstFrame, receivedAt: Date(timeIntervalSince1970: 1_004))

        let recoveredWindowIds = await model.recoverEscalatedFrameCaptures(
            generatedAt: Date(timeIntervalSince1970: 1_010)
        )
        let session = try #require(model.mirrorSessions.first)

        #expect(recoveredWindowIds == ["hwnd:0003029A"])
        #expect(service.focusedWindowIds == ["hwnd:0003029A"])
        #expect(service.frameUnsubscriptions == ["hwnd:0003029A", "hwnd:0003029A", "hwnd:0003029A"])
        #expect(service.frameSubscriptions == ["hwnd:0003029A", "hwnd:0003029A", "hwnd:0003029A", "hwnd:0003029A"])
        #expect(session.captureState == .pending)
        #expect(session.latestFrame == nil)
        #expect(session.frameTiming == nil)
        #expect(session.frameStreamRestartCount == 3)
        #expect(session.latestFrameStreamRestartedAt == Date(timeIntervalSince1970: 1_010))
    }

    @Test("escalates frame stream recovery to app window reopen after capture recovery stalls")
    @MainActor
    func escalatesFrameStreamRecoveryToAppWindowReopenAfterCaptureRecoveryStalls() async throws {
        let service = FakeDashboardService(health: .captureReady)
        let model = HostDashboardModel(service: service)

        await model.launchNotepad()
        model.receiveWindowFrame(.notepadFirstFrame, receivedAt: Date(timeIntervalSince1970: 1_000))
        await model.restartFrameSubscription(
            windowId: "hwnd:0003029A",
            restartedAt: Date(timeIntervalSince1970: 1_001)
        )
        model.receiveWindowFrame(.notepadSecondFrame, receivedAt: Date(timeIntervalSince1970: 1_002))
        await model.restartFrameSubscription(
            windowId: "hwnd:0003029A",
            restartedAt: Date(timeIntervalSince1970: 1_003)
        )
        model.receiveWindowFrame(.notepadFirstFrame, receivedAt: Date(timeIntervalSince1970: 1_004))
        await model.recoverFrameCapture(
            windowId: "hwnd:0003029A",
            recoveredAt: Date(timeIntervalSince1970: 1_005)
        )
        model.receiveWindowFrame(.notepadSecondFrame, receivedAt: Date(timeIntervalSince1970: 1_006))

        let report = model.runtimeStatusReport(generatedAt: Date(timeIntervalSince1970: 1_012))
        let windowStatus = try #require(report.mirrorSessions.first)
        let reopenAction = try #require(report.actions.first { $0.id == "windowsApps.reopenWindow" })
        let recoverAction = try #require(report.actions.first { $0.id == "windowsApps.recoverWindowCapture" })

        #expect(windowStatus.frameStreamStatus == .stale)
        #expect(windowStatus.frameStreamRecommendedAction == "reopen-windows-app")
        #expect(windowStatus.frameStreamRestartCount == 3)
        #expect(windowStatus.latestFrameStreamRestartedAt == Date(timeIntervalSince1970: 1_005))
        #expect(windowStatus.frameStreamRecoveryEscalated == false)
        #expect(windowStatus.frameStreamReopenEscalated)
        #expect(reopenAction.title == "Reopen App Window")
        #expect(reopenAction.isAvailable)
        #expect(recoverAction.isAvailable == false)
    }

    @Test("reopens escalated app windows by closing the stale HWND and launching the same app")
    @MainActor
    func reopensEscalatedAppWindowsByClosingStaleHWNDAndLaunchingSameApp() async throws {
        let service = FakeDashboardService(health: .captureReady)
        service.launchWindows = [.notepad, .secondNotepad]
        let model = HostDashboardModel(service: service)

        await model.launchNotepad()
        model.receiveWindowFrame(.notepadFirstFrame, receivedAt: Date(timeIntervalSince1970: 1_000))
        await model.restartFrameSubscription(
            windowId: "hwnd:0003029A",
            restartedAt: Date(timeIntervalSince1970: 1_001)
        )
        model.receiveWindowFrame(.notepadSecondFrame, receivedAt: Date(timeIntervalSince1970: 1_002))
        await model.restartFrameSubscription(
            windowId: "hwnd:0003029A",
            restartedAt: Date(timeIntervalSince1970: 1_003)
        )
        model.receiveWindowFrame(.notepadFirstFrame, receivedAt: Date(timeIntervalSince1970: 1_004))
        await model.recoverFrameCapture(
            windowId: "hwnd:0003029A",
            recoveredAt: Date(timeIntervalSince1970: 1_005)
        )
        model.receiveWindowFrame(.notepadSecondFrame, receivedAt: Date(timeIntervalSince1970: 1_006))

        let results = await model.reopenEscalatedAppWindows(generatedAt: Date(timeIntervalSince1970: 1_012))

        #expect(results.map(\.requestedWindowId) == ["hwnd:0003029A"])
        #expect(results.map(\.launch.window.windowId) == ["hwnd:00010500"])
        #expect(service.closedWindowIds == ["hwnd:0003029A"])
        #expect(service.launchedAppIds == ["winapp_notepad", "winapp_notepad"])
        #expect(model.mirrorSessions.map(\.id) == ["hwnd:00010500"])
        #expect(model.mirrorSessions.first?.captureState == .pending)
        #expect(model.mirrorSessions.first?.frameStreamRestartCount == 0)
    }

    @Test("routes a protocol frame message into the matching mirror session")
    @MainActor
    func routesProtocolFrameMessageIntoMirrorSession() async throws {
        let service = FakeDashboardService(health: .captureReady)
        let model = HostDashboardModel(service: service)
        let message = Data(WindowFrameEvent.notepadFirstFrameJSON.utf8)

        await model.launchNotepad()
        let result = try await model.receiveProtocolMessage(message)

        let session = try #require(model.mirrorSessions.first)
        #expect(result == .handledWindowFrame(windowId: "hwnd:0003029A"))
        #expect(session.captureState == .streaming)
        #expect(session.latestFrame?.frameId == "frame_000001")
    }

    @Test("routes a protocol created message into automatic mirrored window setup")
    @MainActor
    func routesProtocolCreatedMessageIntoAutomaticMirrorSession() async throws {
        let service = FakeDashboardService(health: .captureReady, apps: [.notepad, .paint])
        let model = HostDashboardModel(service: service)
        let message = Data(WindowCreatedEvent.paintCreatedJSON.utf8)

        await model.load()
        let result = try await model.receiveProtocolMessage(message)

        let session = try #require(model.mirrorSessions.first)
        #expect(result == .handledWindowCreated(windowId: "hwnd:0005029C"))
        #expect(model.activeWindows.map(\.windowId) == ["hwnd:0005029C"])
        #expect(session.id == "hwnd:0005029C")
        #expect(session.window.appId == "winapp_paint")
        #expect(session.captureState == .pending)
        #expect(model.restorableAppIds == ["winapp_paint"])
        #expect(service.frameSubscriptions == ["hwnd:0005029C"])
    }

    @Test("routes a protocol updated message into mirrored window metadata")
    @MainActor
    func routesProtocolUpdatedMessageIntoMirroredWindowMetadata() async throws {
        let service = FakeDashboardService(health: .captureReady)
        let model = HostDashboardModel(service: service)
        let message = Data(WindowUpdatedEvent.notepadUpdatedJSON.utf8)

        await model.launchNotepad()
        model.receiveWindowFrame(.notepadFirstFrame, receivedAt: Date(timeIntervalSince1970: 1_000))
        let result = try await model.receiveProtocolMessage(message)

        let session = try #require(model.mirrorSessions.first)
        #expect(result == .handledWindowUpdated(windowId: "hwnd:0003029A"))
        #expect(model.activeWindows.first?.title == "Notes.txt - Notepad")
        #expect(model.activeWindows.first?.bounds.width == 1360)
        #expect(session.window.title == "Notes.txt - Notepad")
        #expect(session.window.bounds.height == 860)
        #expect(session.latestFrame?.frameId == "frame_000001")
        #expect(session.frameTiming?.receivedFrameCount == 1)
    }

    @Test("routes a protocol closed message into mirrored window cleanup")
    @MainActor
    func routesProtocolClosedMessageIntoMirroredWindowCleanup() async throws {
        let service = FakeDashboardService(health: .captureReady)
        let model = HostDashboardModel(service: service)
        let message = Data(WindowClosedEvent.notepadClosedJSON.utf8)

        await model.launchNotepad()
        let result = try await model.receiveProtocolMessage(message)

        #expect(result == .handledWindowClosed(windowId: "hwnd:0003029A"))
        #expect(model.activeWindows.isEmpty)
        #expect(model.mirrorSessions.isEmpty)
        #expect(model.lastLaunch == nil)
        #expect(model.restorableAppIds.isEmpty)

        let report = model.runtimeStatusReport()
        #expect(report.launcherVisibility.shouldHideMainWindow == false)
        #expect(report.visibleSurfacePolicy.primarySurface == "launcher")
        #expect(report.visibleSurfacePolicy.expectedVisibleSurfaceCount == 1)
        #expect(report.oneScreenUX.mode == "launcher")
        #expect(report.oneScreenUX.expectedVisibleSurfaceCount == 1)
        #expect(report.oneScreenUX.usesSinglePrimarySurfaceFamily)
        #expect(report.oneScreenUX.hidesLauncherDuringAppMirroring)
        #expect(report.oneScreenUX.keepsMenuBarControlAvailable)
        #expect(report.oneScreenUX.keepsDockControlAvailable)
        #expect(report.oneScreenUX.canRecoverFromMenuOrDock)
        #expect(report.oneScreenUX.returnsToLauncherWhenNoAppWindows)
        #expect(report.oneScreenUX.keepsDisplayRecoveryManual)
        #expect(report.oneScreenUX.heroRunsPrimaryAction)
        #expect(report.quietRuntime.hasOpenedAppWindowThisSession)
        #expect(report.quietRuntime.openWindowCount == 0)
        #expect(report.quietRuntime.canQuietRuntime)
        #expect(report.quietRuntime.willQuietAutomatically)
    }

    @Test("consumes protocol frames from an event source")
    @MainActor
    func consumesProtocolFramesFromEventSource() async throws {
        let service = FakeDashboardService(health: .captureReady)
        let model = HostDashboardModel(service: service)
        let source = StaticHostEventSource(messages: [
            Data(WindowFrameEvent.notepadFirstFrameJSON.utf8)
        ])
        var handledResults: [HostProtocolMessageResult] = []

        await model.launchNotepad()
        await model.consumeProtocolMessages(from: source) { result in
            handledResults.append(result)
        }

        let session = try #require(model.mirrorSessions.first)
        #expect(handledResults == [.handledWindowFrame(windowId: "hwnd:0003029A")])
        #expect(session.captureState == .streaming)
        #expect(session.latestFrame?.frameId == "frame_000001")
    }

    @Test("marks phase reconnecting when the event stream drops, and connected while messages flow again")
    @MainActor
    func marksPhaseReconnectingWhenEventStreamDropsAndConnectedAgainOnRecovery() async throws {
        // The production HostEventSource (WebSocketTransport.eventMessages()) only ever ends by
        // throwing -- it never completes normally -- so this test only asserts the phase mid-stream
        // (via the onMessageHandled callback) rather than after a finite fake stream naturally ends,
        // which would otherwise flip phase back to .reconnecting for a reason that can't happen in
        // production.
        let service = FakeDashboardService(health: .captureReady)
        let model = HostDashboardModel(service: service)
        await model.load()
        #expect(model.phase == .connected)

        let failingSource = StaticHostEventSource(messages: [], failure: URLError(.networkConnectionLost))
        await model.consumeProtocolMessages(from: failingSource) { _ in }
        #expect(model.phase == .reconnecting)

        let recoveredSource = StaticHostEventSource(messages: [
            Data(WindowFrameEvent.notepadFirstFrameJSON.utf8)
        ])
        await model.launchNotepad()
        var phaseWhileMessageWasHandled: HostDashboardPhase?
        await model.consumeProtocolMessages(from: recoveredSource) { _ in
            phaseWhileMessageWasHandled = model.phase
        }

        #expect(phaseWhileMessageWasHandled == .connected)
    }

    @Test("does not clobber an unrelated phase when the event stream drops")
    @MainActor
    func doesNotClobberAnUnrelatedPhaseWhenTheEventStreamDrops() async throws {
        // consumeProtocolMessages() runs continuously in the background alongside user-triggered
        // flows that share the same `phase` property (launching an app, loading, etc.) -- it must
        // only ever move between .connected and .reconnecting, never stomp on those other states.
        let service = FakeDashboardService(health: .captureReady)
        let model = HostDashboardModel(service: service)
        await model.launchNotepad()
        #expect(model.phase == .connected)

        service.error = URLError(.cannotFindHost)
        await model.launchNotepad()
        #expect(model.phase == .failed)

        let failingSource = StaticHostEventSource(messages: [], failure: URLError(.networkConnectionLost))
        await model.consumeProtocolMessages(from: failingSource) { _ in }

        #expect(model.phase == .failed)
    }

    @Test("carries a decoded app icon through to the loaded app catalog")
    @MainActor
    func carriesDecodedAppIconThroughToLoadedAppCatalog() async throws {
        let service = FakeDashboardService(health: .captureReady, apps: [.notepad, .calculator])
        let model = HostDashboardModel(service: service)

        await model.load()

        let notepad = try #require(model.apps.first { $0.id == "winapp_notepad" })
        let iconBase64 = try #require(notepad.iconPngBase64)
        #expect(Data(base64Encoded: iconBase64) != nil)

        let calculator = try #require(model.apps.first { $0.id == "winapp_calculator" })
        #expect(calculator.iconPngBase64 == nil)
    }

    @Test("consumes guest clipboard text from an event source once")
    @MainActor
    func consumesGuestClipboardTextFromEventSourceOnce() async throws {
        let service = FakeDashboardService(health: .clipboardReady)
        let model = HostDashboardModel(service: service)
        let source = StaticHostEventSource(messages: [
            Data(ClipboardTextSet.guestEventJSON.utf8),
            Data(ClipboardTextSet.guestEventJSON.utf8)
        ])
        var handledResults: [HostProtocolMessageResult] = []

        await model.load()
        await model.consumeProtocolMessages(from: source) { result in
            handledResults.append(result)
        }

        #expect(model.latestGuestClipboardText == "hello from Windows")
        #expect(model.lastGuestClipboardSequence == 43)
        #expect(handledResults == [
            .handledClipboardText(sequence: 43),
            .ignored
        ])
    }

    @Test("ignores frames for windows without a mirror session")
    @MainActor
    func ignoresFramesWithoutMirrorSession() async throws {
        let service = FakeDashboardService(health: .captureReady)
        let model = HostDashboardModel(service: service)

        await model.launchNotepad()
        model.receiveWindowFrame(.orphanFrame)

        let session = try #require(model.mirrorSessions.first)
        #expect(session.captureState == .pending)
        #expect(session.latestFrame == nil)
    }

    @Test("closes mirrored Windows windows through the agent")
    @MainActor
    func closesMirroredWindowsThroughAgent() async throws {
        let service = FakeDashboardService(health: .captureReady)
        let model = HostDashboardModel(service: service)

        await model.launchNotepad()
        let response = await model.closeMirrorSession(windowId: "hwnd:0003029A")

        #expect(response?.accepted == true)
        #expect(service.closedWindowIds == ["hwnd:0003029A"])
        #expect(model.activeWindows.isEmpty)
        #expect(model.mirrorSessions.isEmpty)
        #expect(model.lastLaunch == nil)
        #expect(model.phase == .connected)
        #expect(service.frameUnsubscriptions == ["hwnd:0003029A"])
    }

    @Test("keeps mirrored window state when the agent rejects close")
    @MainActor
    func keepsMirroredWindowWhenAgentRejectsClose() async throws {
        let service = FakeDashboardService(health: .captureReady, closeAccepted: false)
        let model = HostDashboardModel(service: service)

        await model.launchNotepad()
        let response = await model.closeMirrorSession(windowId: "hwnd:0003029A")

        #expect(response?.accepted == false)
        #expect(model.activeWindows.map(\.windowId) == ["hwnd:0003029A"])
        #expect(model.mirrorSessions.map(\.id) == ["hwnd:0003029A"])
        #expect(model.lastLaunch?.window.windowId == "hwnd:0003029A")
    }

    @Test("closes all mirrored Windows windows through the agent")
    @MainActor
    func closesAllMirroredWindowsThroughAgent() async throws {
        let service = FakeDashboardService(health: .captureReady, apps: [.notepad, .calculator])
        let model = HostDashboardModel(service: service)

        await model.launchApp(appId: "winapp_notepad")
        await model.launchApp(appId: "winapp_calculator")
        let responses = await model.closeAllMirrorSessions()

        #expect(responses.map(\.windowId) == ["hwnd:0003029A", "hwnd:0003030B"])
        #expect(responses.map(\.accepted) == [true, true])
        #expect(service.closedWindowIds == ["hwnd:0003029A", "hwnd:0003030B"])
        #expect(service.frameUnsubscriptions == ["hwnd:0003029A", "hwnd:0003030B"])
        #expect(model.activeWindows.isEmpty)
        #expect(model.mirrorSessions.isEmpty)
        #expect(model.phase == .connected)
    }

    @Test("forwards mouse input for mirrored windows")
    @MainActor
    func forwardsMouseInputForMirroredWindows() async throws {
        let service = FakeDashboardService(health: .inputReady)
        let model = HostDashboardModel(service: service)

        await model.launchNotepad()
        await model.sendMouseInput(windowId: "hwnd:0003029A", event: "leftDown", x: 240, y: 130)

        #expect(service.mouseInputs == [
            InputMouseEvent(windowId: "hwnd:0003029A", event: "leftDown", x: 240, y: 130)
        ])
        #expect(model.phase == .connected)
    }

    @Test("ignores mouse input for windows without a mirror session")
    @MainActor
    func ignoresMouseInputForUnknownWindows() async throws {
        let service = FakeDashboardService(health: .inputReady)
        let model = HostDashboardModel(service: service)

        await model.sendMouseInput(windowId: "hwnd:DEADBEEF", event: "leftDown", x: 20, y: 20)

        #expect(service.mouseInputs.isEmpty)
        #expect(model.phase == .idle)
    }

    @Test("forwards key input for mirrored windows")
    @MainActor
    func forwardsKeyInputForMirroredWindows() async throws {
        let service = FakeDashboardService(health: .inputReady)
        let model = HostDashboardModel(service: service)

        await model.launchNotepad()
        await model.sendKeyInput(
            windowId: "hwnd:0003029A",
            event: "keyDown",
            key: "c",
            windowsVirtualKey: 67,
            modifiers: ["ctrl"]
        )

        #expect(service.keyInputs == [
            InputKeyEvent(
                windowId: "hwnd:0003029A",
                event: "keyDown",
                key: "c",
                windowsVirtualKey: 67,
                modifiers: ["ctrl"]
            )
        ])
        #expect(model.phase == .connected)
    }

    @Test("ignores key input for windows without a mirror session")
    @MainActor
    func ignoresKeyInputForUnknownWindows() async throws {
        let service = FakeDashboardService(health: .inputReady)
        let model = HostDashboardModel(service: service)

        await model.sendKeyInput(windowId: "hwnd:DEADBEEF", event: "keyDown", key: "c", windowsVirtualKey: 67)

        #expect(service.keyInputs.isEmpty)
        #expect(model.phase == .idle)
    }

    @Test("sends host clipboard text with increasing sequence")
    @MainActor
    func sendsHostClipboardTextWithIncreasingSequence() async throws {
        let service = FakeDashboardService(health: .clipboardReady)
        let model = HostDashboardModel(service: service)

        await model.load()
        await model.sendHostClipboardText("hello")
        await model.sendHostClipboardText("world")

        #expect(service.clipboardTexts.map(\.text) == ["hello", "world"])
        #expect(service.clipboardTexts.map(\.origin) == ["host", "host"])
        #expect(service.clipboardTexts.map(\.sequence) == [1, 2])
        #expect(model.clipboardSequence == 2)
        #expect(model.phase == .connected)
    }

    @Test("does not send host clipboard text without live clipboard support")
    @MainActor
    func doesNotSendClipboardTextWithoutLiveClipboardSupport() async throws {
        let service = FakeDashboardService(health: .inputReady)
        let model = HostDashboardModel(service: service)

        await model.load()
        await model.sendHostClipboardText("hello")

        #expect(service.clipboardTexts.isEmpty)
        #expect(model.clipboardSequence == 0)
        #expect(model.phase == .connected)
    }

    @Test("reports command availability from live agent capabilities")
    @MainActor
    func reportsCommandAvailabilityFromLiveAgentCapabilities() async throws {
        let service = FakeDashboardService(health: .clipboardReady)
        let model = HostDashboardModel(service: service)

        await model.load()

        #expect(model.canRequestAppLaunch(appId: "winapp_notepad"))
        #expect(model.canLaunchApp(appId: "winapp_notepad"))
        #expect(!model.canRequestAppLaunch(appId: "winapp_missing"))
        #expect(!model.canFocusMirrorSession(windowId: "hwnd:0003029A"))
        #expect(!model.canCloseMirrorSession(windowId: "hwnd:0003029A"))
        #expect(!model.canCloseAllMirrorSessions)
        #expect(!model.canSendInput(to: "hwnd:0003029A"))
        #expect(model.canSendHostClipboardText)
        #expect(!model.canRestoreMirrorSessions)

        await model.launchNotepad()

        #expect(model.canFocusMirrorSession(windowId: "hwnd:0003029A"))
        #expect(model.canCloseMirrorSession(windowId: "hwnd:0003029A"))
        #expect(model.canCloseAllMirrorSessions)
        #expect(model.canSendInput(to: "hwnd:0003029A"))
        #expect(model.canSendHostClipboardText)
        #expect(!model.canRestoreMirrorSessions)
    }

    @Test("focuses a mirrored window through the live agent")
    @MainActor
    func focusesMirrorSessionThroughLiveAgent() async throws {
        let service = FakeDashboardService(
            health: .inputReady,
            apps: [.notepad, .calculator]
        )
        let model = HostDashboardModel(service: service)

        await model.load()
        await model.launchApp(appId: "winapp_notepad")
        await model.launchApp(appId: "winapp_calculator")
        let response = await model.focusMirrorSession(windowId: "hwnd:0003030B")

        #expect(response?.type == .windowFocusResponse)
        #expect(response?.accepted == true)
        #expect(service.focusedWindowIds == ["hwnd:0003030B"])
        #expect(model.activeWindows.first { $0.windowId == "hwnd:0003029A" }?.focused == false)
        #expect(model.activeWindows.first { $0.windowId == "hwnd:0003030B" }?.focused == true)
        #expect(model.mirrorSessions.first { $0.id == "hwnd:0003029A" }?.window.focused == false)
        #expect(model.mirrorSessions.first { $0.id == "hwnd:0003030B" }?.window.focused == true)
    }

    @Test("disables unsupported input and clipboard commands")
    @MainActor
    func disablesUnsupportedInputAndClipboardCommands() async throws {
        let service = FakeDashboardService(health: .captureReady)
        let model = HostDashboardModel(service: service)

        await model.load()
        await model.launchNotepad()

        #expect(model.canRequestAppLaunch(appId: "winapp_notepad"))
        #expect(model.canLaunchApp(appId: "winapp_notepad"))
        #expect(!model.canSendInput(to: "hwnd:0003029A"))
        #expect(!model.canSendHostClipboardText)
    }

    @Test("builds app runtime status report for harness automation")
    @MainActor
    func buildsAppRuntimeStatusReportForHarnessAutomation() async throws {
        let service = FakeDashboardService(health: .clipboardReadyWithSparsePackageStatus)
        let model = HostDashboardModel(service: service)
        let generatedAt = Date(timeIntervalSince1970: 1_782_800_000)

        await model.load()
        await model.launchNotepad()
        let report = model.runtimeStatusReport(generatedAt: generatedAt)

        #expect(report.kind == "windowsAppRuntimeStatus")
        #expect(report.generatedAt == generatedAt)
        #expect(report.connection.mode == .agent)
        #expect(report.connection.hasLiveAgentConnection)
        #expect(report.connection.agentVersion == "0.1.0")
        #expect(report.connection.capabilities?.windowCapture == true)
        #expect(report.connection.capabilities?.input == true)
        #expect(report.connection.capabilities?.clipboardText == true)
        #expect(report.connection.capabilities?.packageIdentity == false)
        #expect(report.connection.packageIdentityStatus?.stage == "packageSigned")
        #expect(report.dailyUseReadiness.packageIdentityReady == false)
        #expect(report.dailyUseReadiness.packageIdentityStatus?.statusPath.contains("sparse-package-status.json") == true)
        #expect(report.dailyUseReadiness.packageIdentityStage == "packageSigned")
        #expect(report.dailyUseReadiness.packageIdentitySucceeded == false)
        #expect(report.dailyUseReadiness.packageIdentityMessage == "SignTool signed the sparse identity package.")
        #expect(report.dailyUseReadiness.packageIdentityEvidencePath?.contains("sparse-package-status.json") == true)
        #expect(report.dailyUseReadiness.reason.contains("stage packageSigned"))
        #expect(report.dailyUseReadiness.borderlessCapturePreflightPassed == false)
        #expect(report.dailyUseReadiness.borderlessCaptureRecommendedAction == "prepare-sparse-package")
        #expect(report.dailyUseReadiness.borderlessCaptureRequirement.contains("signed sparse package identity"))
        #expect(report.dailyUseReadiness.borderlessCaptureRequirement.contains("windowCapture capability"))
        #expect(report.dailyUseReadiness.notificationBridgePreflightPassed == false)
        #expect(report.dailyUseReadiness.notificationBridgeRecommendedAction == "prepare-sparse-package")
        #expect(report.dailyUseReadiness.notificationBridgeRequirement.contains("Windows UserNotificationListener consent"))
        #expect(report.dailyUseReadiness.printerBridgeMode == "manual-ipp-experiment")
        #expect(report.dailyUseReadiness.printerBridgeRecommendedAction == "manual-ipp-experiment")
        #expect(report.dailyUseReadiness.printerBridgeEndpointTemplate == "http://10.0.2.2:631/printers/<shared-printer-name>")
        #expect(report.dailyUseReadiness.printerBridgeSetupHint.contains("Share the Mac printer"))
        #expect(report.dailyUseReadiness.printerBridgeSetupHint.contains("IPP network printer"))
        #expect(report.dailyUseReadiness.recommendedAction == "prepare-sparse-package")
        #expect(report.dailyUseReadiness.recommendedCommand == "veil-vmctl app-runtime-action --json --action prepare-sparse-package --wait-seconds 120")
        #expect(report.guestAgentDiagnostics.endpoint == HostDashboardModel.defaultAgentEndpoint)
        #expect(report.guestAgentDiagnostics.isConnected)
        #expect(report.guestAgentDiagnostics.diagnosticCommand == "veil-host-probe --diagnose-agent")
        #expect(report.guestAgentDiagnostics.waitCommand == "veil-vmctl guest-agent-wait --json --wait-seconds 30")
        #expect(report.guestAgentDiagnostics.recommendedAction == "run-app-window-proof")
        #expect(report.localRuntime.isKnown == false)
        #expect(report.localRuntime.canStart)
        #expect(report.localRuntime.recommendedAction == "inspect-local-runtime")
        #expect(report.apps.map(\.id) == ["winapp_notepad"])
        #expect(report.apps.map(\.canRequestLaunch) == [true])
        #expect(report.apps.map(\.canLaunchNow) == [true])
        #expect(report.mirrorSessions.map(\.windowId) == ["hwnd:0003029A"])
        #expect(report.mirrorSessions.map(\.title) == ["Untitled - Notepad"])
        #expect(report.mirrorSessions.map(\.frameStreamStatus) == [.waitingForFirstFrame])
        #expect(report.mirrorSessions.map(\.latestFrameAgeMilliseconds) == [nil])
        #expect(report.mirrorSessions.map(\.latestFrameIntervalMilliseconds) == [nil])
        #expect(report.mirrorSessions.map(\.receivedFrameCount) == [0])
        #expect(report.mirrorSessions.map(\.frameStreamRecommendedAction) == ["wait-for-first-frame"])
        #expect(report.mirrorSessions.map(\.frameStreamRestartCount) == [0])
        #expect(report.mirrorSessions.map(\.latestFrameStreamRestartedAt) == [nil])
        #expect(report.mirrorSessions.map(\.frameStreamRecoveryEscalated) == [false])
        #expect(report.mirrorSessions.map(\.canFocus) == [true])
        #expect(report.mirrorSessions.map(\.canClose) == [true])
        #expect(report.mirrorSessions.map(\.canSendInput) == [true])
        #expect(report.restorableAppIds == ["winapp_notepad"])
        #expect(report.dockIntegration.isEnabled)
        #expect(report.dockIntegration.openWindowCount == 1)
        #expect(report.dockIntegration.pendingLaunchCount == 0)
        #expect(report.dockIntegration.restorableAppCount == 1)
        #expect(report.dockIntegration.restorableWindowCount == 1)
        #expect(report.dockIntegration.badgeLabel == "1")
        #expect(report.dockIntegration.canOpenMainWindow)
        #expect(report.dockIntegration.canBringWindowsAppsForward)
        #expect(report.dockIntegration.canRestorePreviousApps == false)
        #expect(report.dockIntegration.canReconnectPreviousApps == false)
        #expect(report.dockIntegration.canLaunchSelectedApp)
        #expect(report.menuBarIntegration.isEnabled)
        #expect(report.menuBarIntegration.statusTitle == "1 Windows App Open")
        #expect(report.menuBarIntegration.symbolName == "rectangle.stack.fill")
        #expect(report.menuBarIntegration.primaryActionId == "dock.bringWindowsAppsForward")
        #expect(report.menuBarIntegration.primaryActionTitle == "Bring Notepad Forward")
        #expect(report.menuBarIntegration.primaryActionAvailable)
        #expect(report.menuBarIntegration.canBringWindowsAppsForward)
        #expect(report.menuBarIntegration.canLaunchSelectedApp)
        #expect(report.launcherVisibility.isEnabled)
        #expect(report.launcherVisibility.canOpenMainWindow)
        #expect(report.launcherVisibility.shouldHideMainWindow)
        #expect(report.launcherVisibility.keepsDockMenuAvailable)
        #expect(report.launcherVisibility.recommendedAction == "hide-main-window-use-app-windows")
        #expect(report.visibleSurfacePolicy.isEnabled)
        #expect(report.visibleSurfacePolicy.primarySurface == "windows-app-windows")
        #expect(report.visibleSurfacePolicy.expectedVisibleSurfaceCount == 1)
        #expect(report.visibleSurfacePolicy.shouldHideLauncher)
        #expect(report.visibleSurfacePolicy.keepsRecoveryDisplayManual)
        #expect(report.oneScreenUX.isEnabled)
        #expect(report.oneScreenUX.mode == "windows-app-windows")
        #expect(report.oneScreenUX.expectedVisibleSurfaceCount == 1)
        #expect(report.oneScreenUX.usesSinglePrimarySurfaceFamily)
        #expect(report.oneScreenUX.hidesLauncherDuringAppMirroring)
        #expect(report.oneScreenUX.keepsMenuBarControlAvailable)
        #expect(report.oneScreenUX.keepsDockControlAvailable)
        #expect(report.oneScreenUX.canRecoverFromMenuOrDock)
        #expect(report.oneScreenUX.returnsToLauncherWhenNoAppWindows)
        #expect(report.oneScreenUX.keepsDisplayRecoveryManual)
        #expect(report.oneScreenUX.primaryActionId == "runtime.refreshStatus")
        #expect(report.oneScreenUX.heroRunsPrimaryAction)
        #expect(report.macWindowIntegration.isEnabled)
        #expect(report.macWindowIntegration.acceptsGuestWindowEvents)
        #expect(report.macWindowIntegration.opensMacWindowsAutomatically)
        #expect(report.macWindowIntegration.hidesLauncherWhenMirroring)
        #expect(report.macWindowIntegration.mirroredWindowCount == 1)
        #expect(report.macWindowIntegration.foregroundableWindowCount == 1)
        #expect(report.macWindowIntegration.foregroundWindowId == "hwnd:0003029A")
        #expect(report.macWindowIntegration.foregroundWindowTitle == "Untitled - Notepad")
        #expect(report.macWindowIntegration.pendingFrameWindowCount == 1)
        #expect(report.macWindowIntegration.streamingWindowCount == 0)
        #expect(report.macWindowIntegration.freshFrameWindowCount == 0)
        #expect(report.macWindowIntegration.delayedFrameWindowCount == 0)
        #expect(report.macWindowIntegration.staleFrameWindowCount == 0)
        #expect(report.macWindowIntegration.reason == "Windows app windows are mirrored as macOS windows.")
        #expect(!report.macWindowIntegration.reason.contains("Windows agent"))
        #expect(!report.macWindowIntegration.reason.contains("HWND"))
        #expect(report.quietRuntime.isEnabled)
        #expect(report.quietRuntime.hasOpenedAppWindowThisSession)
        #expect(report.quietRuntime.openWindowCount == 1)
        #expect(report.quietRuntime.canQuietRuntime == false)
        #expect(report.quietRuntime.willQuietAutomatically == false)
        #expect(report.quietRuntime.automaticQuietDelaySeconds == 8)
        #expect(report.quietRuntime.recommendedAction == "keep-running")
        #expect(report.quietRuntime.recommendedStopCommand == nil)
        #expect(report.quietRuntime.reason == "Windows app windows are still open.")
        #expect(report.launchPlan.selectedAppId == "winapp_notepad")
        #expect(report.launchPlan.canRequestSelectedAppLaunch)
        #expect(report.launchPlan.canLaunchSelectedAppNow)
        #expect(report.launchPlan.willOpenAppAutomatically)
        #expect(report.launchPlan.requiresRuntimeStart == false)
        #expect(report.launchPlan.requiresGuestAgent == false)
        #expect(report.launchPlan.recommendedAction == "launch-now")
        #expect(report.launchPlan.recommendedLaunchCommand == "veil-vmctl app-runtime-action --json --action launch --app-id winapp_notepad")
        #expect(report.proofPlan.selectedAppId == "winapp_notepad")
        #expect(report.proofPlan.canRunAppWindowProof)
        #expect(report.proofPlan.canRunCoherenceProof)
        #expect(report.proofPlan.canRunMVPProof)
        #expect(report.proofPlan.recommendedProofKind == "mvp")
        #expect(report.proofPlan.recommendedProofCommand == "veil-vmctl mvp-proof --json --app-id winapp_notepad --require-proved")
        #expect(report.proofPlan.recommendedAppWindowProofCommand == "veil-vmctl app-window-proof --json --app-id winapp_notepad")
        #expect(report.proofPlan.recommendedCoherenceProofCommand == "veil-vmctl coherence-proof --json --app-id winapp_notepad")
        #expect(report.proofPlan.recommendedMVPProofCommand == "veil-vmctl mvp-proof --json --app-id winapp_notepad --require-proved")
        #expect(report.proofPlan.reason == "The Windows app connection can run window, input, and full app checks for the selected app.")
        #expect(!report.proofPlan.reason.contains("Windows agent"))
        #expect(!report.proofPlan.reason.contains("proof"))
        #expect(report.releaseGate.isEnabled)
        #expect(report.releaseGate.requiredStepCount == 5)
        #expect((3...4).contains(report.releaseGate.passingStepCount))
        #expect(report.releaseGate.isPassing == false)
        #expect(report.releaseGate.recommendedAction == "windowsSetup")
        #expect(report.releaseGate.steps.map(\.id) == [
            "windowsSetup",
            "oneScreenPath",
            "openWindowsApp",
            "appCheckEvidence",
            "closeOrRestore"
        ])
        #expect(report.releaseGate.steps.first { $0.id == "oneScreenPath" }?.isPassing == true)
        #expect(report.releaseGate.steps.first { $0.id == "openWindowsApp" }?.nextActionCommand == "veil-vmctl app-runtime-action --json --action launch --app-id winapp_notepad")
        #expect(report.releaseGate.steps.first { $0.id == "closeOrRestore" }?.nextActionCommand == "veil-vmctl app-runtime-action --json --action close-all")
        #expect(report.releaseGate.screenshotSlots.map(\.id) == [
            "preBootLauncher",
            "firstAppLaunch",
            "appWindowOnly",
            "menuRestore",
            "closeQuiet"
        ])
        #expect(report.releaseGate.steps.map(\.title).allSatisfy { !$0.contains("Guest Agent") })
        #expect(report.releaseGate.steps.map(\.title).allSatisfy { !$0.contains("Runtime") })
        #expect(report.releaseGate.steps.map(\.title).allSatisfy { !$0.contains("Proof") })
        #expect(report.releaseGate.steps.map(\.title).allSatisfy { !$0.contains("HWND") })
        #expect(report.primaryNextAction.id == "windowsSetup")
        #expect(report.primaryNextAction.title == "Windows Setup Ready")
        #expect(report.primaryNextAction.source == "releaseGate")
        #expect(report.primaryNextAction.isAvailable)
        #expect(report.primaryNextAction.runsInApp)
        #expect(report.primaryNextAction.actionId == "runtime.refreshStatus")
        #expect(report.primaryNextAction.command == "veil-vmctl qemu-install-status --json")
        #expect(report.primaryNextAction.reason == report.releaseGate.steps.first { $0.id == "windowsSetup" }?.evidence)
        #expect(report.actions.first { $0.id == "dock.openMainWindow" }?.isAvailable == true)
        #expect(report.actions.first { $0.id == "dock.bringWindowsAppsForward" }?.isAvailable == true)
        #expect(report.actions.first { $0.id == "clipboard.setText" }?.isAvailable == true)
        #expect(report.actions.first { $0.id == "windowsApps.restorePrevious" }?.isAvailable == false)
        #expect(report.actions.first { $0.id == "macWindows.autoOpen" }?.isAvailable == true)
        #expect(report.actions.first { $0.id == "windowsApps.launchSelected" }?.isAvailable == true)
        #expect(report.actions.first { $0.id == "runtime.prepareWindows" }?.isAvailable == false)
        #expect(report.actions.first { $0.id == "runtime.refreshStatus" }?.isAvailable == true)
        #expect(report.actions.first { $0.id == "runtime.startWindowsForApp" }?.isAvailable == false)
        #expect(report.actions.first { $0.id == "runtime.repairGuestAgentForApp" }?.isAvailable == false)
        #expect(report.actions.first { $0.id == "runtime.prepareSparsePackage" }?.isAvailable == true)
        #expect(report.actions.first { $0.id == "dailyUse.verifyIntegrations" }?.isAvailable == false)
        #expect(report.actions.first { $0.id == "dailyUse.verifyWindowCapture" }?.isAvailable == false)
        #expect(report.actions.first { $0.id == "dailyUse.requestNotificationConsent" }?.isAvailable == false)
        #expect(report.actions.first { $0.id == "runtime.recoverDisplay" }?.isAvailable == false)
        #expect(report.actions.first { $0.id == "runtime.fulfillPendingLaunch" }?.isAvailable == false)
        #expect(report.actions.first { $0.id == "runtime.waitAgent" }?.isAvailable == false)
        #expect(report.actions.first { $0.id == "runtime.quietWhenIdle" }?.isAvailable == false)
        #expect(report.actions.first { $0.id == "runtime.stopWhenIdle" }?.isAvailable == false)
        #expect(report.actions.first { $0.id == "proof.appWindow" }?.isAvailable == true)
        #expect(report.actions.first { $0.id == "proof.coherence" }?.isAvailable == true)
        #expect(report.actions.first { $0.id == "proof.mvp" }?.isAvailable == true)
        #expect(report.actions.first { $0.id == "proof.recommended" }?.isAvailable == true)

        let actionTitles = report.actions.map(\.title)
        #expect(actionTitles.contains("Repair App Connection"))
        #expect(actionTitles.contains("Check Windows App"))
        #expect(actionTitles.contains("Check App Connection"))
        #expect(actionTitles.contains("Verify Daily Use"))
        #expect(actionTitles.contains("Verify Window Capture"))
        #expect(actionTitles.contains("Check Notifications"))
        #expect(actionTitles.allSatisfy { !$0.contains("Guest Agent") })
        #expect(actionTitles.allSatisfy { !$0.contains("Runtime") })
        #expect(actionTitles.allSatisfy { !$0.contains("Proof") })
        #expect(actionTitles.allSatisfy { !$0.contains("HWND") })
    }

    @Test("menu bar promotes package identity preparation when no Windows app is open")
    @MainActor
    func menuBarPromotesPackageIdentityPreparationWhenNoWindowsAppIsOpen() async throws {
        let service = FakeDashboardService(health: .clipboardReadyWithSparsePackageStatus)
        let model = HostDashboardModel(service: service)

        await model.load()
        let report = model.runtimeStatusReport()

        #expect(report.mirrorSessions.isEmpty)
        #expect(report.dailyUseReadiness.recommendedAction == "prepare-sparse-package")
        #expect(report.dailyUseReadiness.recommendedCommand == "veil-vmctl app-runtime-action --json --action prepare-sparse-package --wait-seconds 120")
        #expect(report.menuBarIntegration.statusTitle == "App Identity Needed")
        #expect(report.menuBarIntegration.symbolName == "shippingbox")
        #expect(report.menuBarIntegration.primaryActionId == "runtime.prepareSparsePackage")
        #expect(report.menuBarIntegration.primaryActionTitle == "Prepare Identity")
        #expect(report.menuBarIntegration.primaryActionAvailable)
    }

    @Test("daily use readiness continues into the strongest app check after package identity")
    @MainActor
    func dailyUseReadinessContinuesIntoStrongestAppCheckAfterPackageIdentity() async throws {
        let service = FakeDashboardService(health: .dailyUseReady)
        let model = HostDashboardModel(service: service)

        await model.load()
        let report = model.runtimeStatusReport()

        #expect(report.connection.capabilities?.packageIdentity == true)
        #expect(report.dailyUseReadiness.packageIdentityReady)
        #expect(report.dailyUseReadiness.packageIdentityStage == "registered")
        #expect(report.dailyUseReadiness.packageIdentitySucceeded == true)
        #expect(report.dailyUseReadiness.packageIdentityMessage == "Sparse package registered and agent restarted with package identity.")
        #expect(report.dailyUseReadiness.packageIdentityEvidencePath?.contains("sparse-package-status.json") == true)
        #expect(report.dailyUseReadiness.borderlessCapturePreflightPassed)
        #expect(report.dailyUseReadiness.borderlessCaptureRecommendedAction == "verify-daily-use-integrations")
        #expect(report.dailyUseReadiness.borderlessCaptureRequirement.contains("borderless Windows Graphics Capture consent"))
        #expect(report.dailyUseReadiness.notificationBridgePreflightPassed)
        #expect(report.dailyUseReadiness.notificationBridgeRecommendedAction == "verify-notification-listener-consent")
        #expect(report.dailyUseReadiness.notificationBridgeRequirement.contains("signed sparse package identity"))
        #expect(report.dailyUseReadiness.printerBridgeEndpointTemplate == "http://10.0.2.2:631/printers/<shared-printer-name>")
        #expect(report.dailyUseReadiness.printerBridgeSetupHint.contains("IPP network printer"))
        #expect(report.dailyUseReadiness.recommendedAction == "verify-daily-use-integrations")
        #expect(report.dailyUseReadiness.recommendedCommand == "veil-vmctl app-runtime-action --json --action proof-recommended")
        #expect(report.menuBarIntegration.statusTitle == "App Check Needed")
        #expect(report.menuBarIntegration.symbolName == "checkmark.seal")
        #expect(report.menuBarIntegration.primaryActionId == "dailyUse.verifyIntegrations")
        #expect(report.menuBarIntegration.primaryActionTitle == "Verify Daily Use")
        #expect(report.menuBarIntegration.primaryActionAvailable)
        #expect(report.actions.first { $0.id == "runtime.prepareSparsePackage" }?.isAvailable == false)
        #expect(report.actions.first { $0.id == "dailyUse.verifyIntegrations" }?.isAvailable == true)
        #expect(report.actions.first { $0.id == "dailyUse.verifyWindowCapture" }?.isAvailable == false)
        #expect(report.actions.first { $0.id == "dailyUse.requestNotificationConsent" }?.isAvailable == false)
        #expect(report.actions.first { $0.id == "proof.recommended" }?.isAvailable == true)
    }

    @Test("Daily Use window capture action is available between package identity and capture readiness")
    @MainActor
    func dailyUseWindowCaptureActionIsAvailableBetweenPackageIdentityAndCaptureReadiness() async throws {
        let service = FakeDashboardService(health: .packageIdentityWithoutWindowCapture)
        let model = HostDashboardModel(service: service)

        await model.load()
        let report = model.runtimeStatusReport()

        #expect(report.connection.capabilities?.packageIdentity == true)
        #expect(report.connection.capabilities?.windowCapture == false)
        #expect(report.dailyUseReadiness.packageIdentityReady)
        #expect(report.dailyUseReadiness.borderlessCapturePreflightPassed == false)
        #expect(report.dailyUseReadiness.borderlessCaptureRecommendedAction == "verify-window-capture")
        #expect(report.dailyUseReadiness.notificationBridgeRecommendedAction == "verify-notification-listener-consent")
        #expect(report.dailyUseReadiness.recommendedAction == "verify-window-capture")
        #expect(report.dailyUseReadiness.recommendedCommand == "veil-vmctl app-runtime-status --json")
        #expect(report.actions.first { $0.id == "runtime.prepareSparsePackage" }?.isAvailable == false)
        #expect(report.actions.first { $0.id == "dailyUse.verifyWindowCapture" }?.isAvailable == true)
        #expect(report.actions.first { $0.id == "dailyUse.verifyIntegrations" }?.isAvailable == false)
        #expect(report.actions.first { $0.id == "dailyUse.requestNotificationConsent" }?.isAvailable == false)
    }

    @Test("reports quiet runtime readiness after the final Windows app window closes")
    @MainActor
    func reportsQuietRuntimeReadinessAfterFinalWindowCloses() async throws {
        let service = FakeDashboardService(health: .captureReady)
        let model = HostDashboardModel(service: service)

        await model.launchNotepad()
        _ = await model.closeMirrorSession(windowId: "hwnd:0003029A")
        let report = model.runtimeStatusReport()

        #expect(model.hasOpenedAppWindowThisSession)
        #expect(model.canQuietRuntimeWhenIdle)
        #expect(report.mirrorSessions.isEmpty)
        #expect(report.quietRuntime.hasOpenedAppWindowThisSession)
        #expect(report.quietRuntime.openWindowCount == 0)
        #expect(report.quietRuntime.canQuietRuntime)
        #expect(report.quietRuntime.willQuietAutomatically)
        #expect(report.quietRuntime.automaticQuietDelaySeconds == 8)
        #expect(report.quietRuntime.recommendedAction == "stop-or-suspend-runtime")
        #expect(report.quietRuntime.recommendedStopCommand == "veil-vmctl app-runtime-action --json --action stop-runtime")
        #expect(report.quietRuntime.reason == "All Windows app windows are closed and the Windows app connection is ready to stop cleanly.")
        #expect(!report.quietRuntime.reason.contains("live agent"))
        #expect(!report.quietRuntime.reason.contains("runtime"))
        #expect(report.guestAgentDiagnostics.isConnected)
        #expect(report.guestAgentDiagnostics.recommendedAction == "run-app-window-proof")
        #expect(report.macWindowIntegration.acceptsGuestWindowEvents)
        #expect(report.macWindowIntegration.hidesLauncherWhenMirroring == false)
        #expect(report.macWindowIntegration.mirroredWindowCount == 0)
        #expect(report.macWindowIntegration.foregroundWindowId == nil)
        #expect(report.macWindowIntegration.foregroundWindowTitle == nil)
        #expect(report.launcherVisibility.shouldHideMainWindow == false)
        #expect(report.launcherVisibility.recommendedAction == "show-launcher")
        #expect(report.visibleSurfacePolicy.primarySurface == "launcher")
        #expect(report.visibleSurfacePolicy.expectedVisibleSurfaceCount == 1)
        #expect(report.visibleSurfacePolicy.shouldHideLauncher == false)
        #expect(report.visibleSurfacePolicy.keepsRecoveryDisplayManual)
        #expect(report.oneScreenUX.mode == "launcher")
        #expect(report.oneScreenUX.expectedVisibleSurfaceCount == 1)
        #expect(report.oneScreenUX.usesSinglePrimarySurfaceFamily)
        #expect(report.oneScreenUX.hidesLauncherDuringAppMirroring)
        #expect(report.oneScreenUX.keepsMenuBarControlAvailable)
        #expect(report.oneScreenUX.keepsDockControlAvailable)
        #expect(report.oneScreenUX.canRecoverFromMenuOrDock)
        #expect(report.oneScreenUX.returnsToLauncherWhenNoAppWindows)
        #expect(report.oneScreenUX.keepsDisplayRecoveryManual)
        #expect(report.oneScreenUX.heroRunsPrimaryAction)
        #expect(report.proofPlan.selectedAppId == "winapp_notepad")
        #expect(report.proofPlan.canRunAppWindowProof)
        #expect(report.proofPlan.canRunCoherenceProof == false)
        #expect(report.proofPlan.canRunMVPProof == false)
        #expect(report.proofPlan.recommendedProofKind == "app-window")
        #expect(report.proofPlan.recommendedProofCommand == "veil-vmctl app-window-proof --json --app-id winapp_notepad")
        #expect(report.proofPlan.recommendedAppWindowProofCommand == "veil-vmctl app-window-proof --json --app-id winapp_notepad")
        #expect(report.proofPlan.recommendedCoherenceProofCommand == nil)
        #expect(report.proofPlan.recommendedMVPProofCommand == nil)
        #expect(report.actions.first { $0.id == "runtime.quietWhenIdle" }?.isAvailable == true)
        #expect(report.actions.first { $0.id == "runtime.waitAgent" }?.isAvailable == false)
        #expect(report.actions.first { $0.id == "runtime.stopWhenIdle" }?.isAvailable == true)
        #expect(report.actions.first { $0.id == "proof.appWindow" }?.isAvailable == true)
        #expect(report.actions.first { $0.id == "proof.coherence" }?.isAvailable == false)
        #expect(report.actions.first { $0.id == "proof.mvp" }?.isAvailable == false)
        #expect(report.actions.first { $0.id == "proof.recommended" }?.isAvailable == true)

        let stoppedRuntime = WindowsAppRuntimeLocalRuntimeStatus(
            isKnown: true,
            state: .stopped,
            bootReady: true,
            canStart: true,
            isRunning: false,
            windowsInstalled: true,
            recommendedAction: "start-runtime",
            recommendedInstallStatusCommand: "veil-vmctl qemu-install-status --json",
            reason: "The local Windows runtime is already stopped."
        )
        let stoppedReport = model.runtimeStatusReport(localRuntime: stoppedRuntime)

        #expect(stoppedReport.quietRuntime.canQuietRuntime == false)
        #expect(stoppedReport.quietRuntime.willQuietAutomatically == false)
        #expect(stoppedReport.quietRuntime.recommendedAction == "already-quiet")
        #expect(stoppedReport.quietRuntime.recommendedStopCommand == nil)
        #expect(stoppedReport.quietRuntime.reason == "All Windows app windows are closed and Windows is already quiet.")
        #expect(stoppedReport.actions.first { $0.id == "runtime.quietWhenIdle" }?.isAvailable == false)
        #expect(stoppedReport.actions.first { $0.id == "runtime.stopWhenIdle" }?.isAvailable == false)
    }

    @Test("reports passing release gate when setup app check and restore evidence are present")
    @MainActor
    func reportsPassingReleaseGateWhenEvidenceIsPresent() async throws {
        let service = FakeDashboardService(health: .clipboardReady)
        let model = HostDashboardModel(service: service)

        await model.load()
        await model.launchNotepad()

        let localRuntime = WindowsAppRuntimeLocalRuntimeStatus(
            isKnown: true,
            state: .running,
            bootReady: true,
            canStart: false,
            isRunning: true,
            windowsInstalled: true,
            recommendedAction: "wait-for-guest-agent",
            recommendedInstallStatusCommand: "veil-vmctl qemu-install-status --json",
            reason: "Windows is installed and ready for app checks."
        )
        let macWindowIntegration = model.macWindowIntegrationStatus()
        let launcherVisibility = model.launcherVisibilityStatus(
            macWindowIntegration: macWindowIntegration
        )
        let visibleSurfacePolicy = model.visibleSurfacePolicyStatus(
            launcherVisibility: launcherVisibility,
            macWindowIntegration: macWindowIntegration
        )
        let releaseGate = model.releaseGateStatus(
            localRuntime: localRuntime,
            launcherVisibility: launcherVisibility,
            visibleSurfacePolicy: visibleSurfacePolicy,
            macWindowIntegration: macWindowIntegration,
            quietRuntime: model.quietRuntimeStatus(localRuntime: localRuntime),
            launchPlan: model.launchPlanStatus(localRuntime: localRuntime),
            pendingLaunch: model.pendingLaunchStatus(),
            proofPlan: model.proofPlanStatus(),
            proofArtifacts: WindowsAppRuntimeProofArtifactStatus(
                diagnosticsDirectory: "/tmp/Veil/Diagnostics",
                recommendedProofDirectory: "/tmp/Veil/Diagnostics/Recommended Proof",
                latestProofKind: "mvp",
                latestProofPath: "/tmp/Veil/Diagnostics/Recommended Proof/mvp-proof-latest.json",
                latestProofFileName: "mvp-proof-latest.json",
                latestProofModifiedAt: Date(timeIntervalSince1970: 1_700_000_100),
                reason: "Latest app check artifact is available in Veil diagnostics."
            )
        )

        #expect(releaseGate.requiredStepCount == 5)
        #expect(releaseGate.passingStepCount == 5)
        #expect(releaseGate.isPassing)
        #expect(releaseGate.recommendedAction == "ready-for-release-card")
        #expect(releaseGate.reason == "The one-screen Windows app release gate has current setup, launch, app check, and close or restore evidence.")
        #expect(releaseGate.steps.first { $0.id == "appCheckEvidence" }?.state == "passed")
        #expect(releaseGate.steps.first { $0.id == "closeOrRestore" }?.state == "ready")
        #expect(releaseGate.steps.first { $0.id == "closeOrRestore" }?.nextActionCommand == "veil-vmctl app-runtime-action --json --action close-all")
    }

    @Test("reports latest proof artifact from diagnostics")
    @MainActor
    func reportsLatestProofArtifactFromDiagnostics() async throws {
        let service = FakeDashboardService(health: .captureReady)
        let model = HostDashboardModel(service: service)
        let diagnosticsDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("veil-proof-artifacts-\(UUID().uuidString)", isDirectory: true)
        let appWindowDirectory = diagnosticsDirectory
            .appendingPathComponent("App Window Proof", isDirectory: true)
        let recommendedDirectory = diagnosticsDirectory
            .appendingPathComponent("Recommended Proof", isDirectory: true)
        try FileManager.default.createDirectory(at: appWindowDirectory, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: recommendedDirectory, withIntermediateDirectories: true)
        defer {
            try? FileManager.default.removeItem(at: diagnosticsDirectory)
        }

        let olderProofURL = appWindowDirectory.appendingPathComponent("app-window-proof.json")
        let latestProofURL = recommendedDirectory.appendingPathComponent("mvp-proof-latest.json")
        try Data("{}".utf8).write(to: olderProofURL)
        try Data("{}".utf8).write(to: latestProofURL)
        try FileManager.default.setAttributes(
            [.modificationDate: Date(timeIntervalSince1970: 1_700_000_000)],
            ofItemAtPath: olderProofURL.path
        )
        try FileManager.default.setAttributes(
            [.modificationDate: Date(timeIntervalSince1970: 1_700_000_100)],
            ofItemAtPath: latestProofURL.path
        )

        let artifacts = model.proofArtifactStatus(diagnosticsDirectory: diagnosticsDirectory)

        #expect(artifacts.diagnosticsDirectory == diagnosticsDirectory.path)
        #expect(artifacts.recommendedProofDirectory == recommendedDirectory.path)
        #expect(artifacts.latestProofKind == "mvp")
        #expect(artifacts.latestProofPath?.hasSuffix("/Recommended Proof/mvp-proof-latest.json") == true)
        #expect(artifacts.latestProofFileName == "mvp-proof-latest.json")
        #expect(artifacts.latestProofModifiedAt == Date(timeIntervalSince1970: 1_700_000_100))
        #expect(artifacts.reason == "Latest app check artifact is available in Veil diagnostics.")
    }

    @Test("updates active window sessions by HWND")
    @MainActor
    func updatesActiveWindowSessionsByHWND() async throws {
        let service = FakeDashboardService()
        let model = HostDashboardModel(service: service)

        await model.launchNotepad()
        await model.launchNotepad()

        #expect(model.activeWindows.count == 1)
        #expect(model.activeWindows.first?.windowId == "hwnd:0003029A")
        #expect(model.activeWindows.first?.title == "Untitled - Notepad")
        #expect(service.launchCount == 2)
    }

    @Test("stores service failures as user visible errors")
    @MainActor
    func storesServiceFailures() async throws {
        let service = FakeDashboardService(error: VeilHostError.appMissing("winapp_notepad"))
        let model = HostDashboardModel(service: service)

        await model.load()

        #expect(model.phase == .failed)
        #expect(model.errorMessage == "The Windows app winapp_notepad is not available from the Windows agent.")
        #expect(model.canLaunchSelectedApp == false)
    }

    @Test("does not launch when no app is selected")
    @MainActor
    func doesNotLaunchWithoutSelection() async throws {
        let service = FakeDashboardService()
        let model = HostDashboardModel(service: service)

        await model.launchSelectedApp()

        #expect(model.phase == .failed)
        #expect(model.errorMessage == "Select an app before launching.")
        #expect(service.launchCount == 0)
    }

    @Test("launches the selected Windows app")
    @MainActor
    func launchesSelectedWindowsApp() async throws {
        let service = FakeDashboardService(apps: [.calculator])
        let model = HostDashboardModel(service: service)

        await model.load()
        await model.launchSelectedApp()

        #expect(model.selectedAppId == "winapp_calculator")
        #expect(model.canLaunchSelectedApp)
        #expect(model.phase == .connected)
        #expect(model.lastLaunch?.window.appId == "winapp_calculator")
        #expect(model.lastLaunch?.window.title == "Calculator")
        #expect(service.launchedAppIds == ["winapp_calculator"])
    }

    @Test("opens a dropped file in the target Windows app")
    @MainActor
    func opensADroppedFileInTheTargetApp() async throws {
        let service = FakeDashboardService(apps: [.notepad])
        let model = HostDashboardModel(service: service)

        let result = await model.openFile(appId: "winapp_notepad", fileName: "notes.txt", contentBase64: "aGVsbG8=")

        #expect(result?.window.appId == "winapp_notepad")
        #expect(model.phase == .connected)
        #expect(model.selectedAppId == "winapp_notepad")
        #expect(service.openedFiles.count == 1)
        #expect(service.openedFiles.first?.fileName == "notes.txt")
        #expect(service.openedFiles.first?.contentBase64 == "aGVsbG8=")
    }

    @Test("surfaces an error when opening a dropped file fails")
    @MainActor
    func surfacesErrorWhenOpeningADroppedFileFails() async throws {
        let service = FakeDashboardService(error: VeilHostError.appMissing("winapp_notepad"))
        let model = HostDashboardModel(service: service)

        let result = await model.openFile(appId: "winapp_notepad", fileName: "notes.txt", contentBase64: "aGVsbG8=")

        #expect(result == nil)
        #expect(model.phase == .failed)
        #expect(model.errorMessage == "The Windows app winapp_notepad is not available from the Windows agent.")
    }

    @Test("loads demo overview when primary agent is unavailable")
    @MainActor
    func loadsDemoOverviewWhenPrimaryAgentIsUnavailable() async throws {
        let primary = FakeDashboardService(error: URLError(.cannotConnectToHost))
        let service = FallbackHostDashboardService(
            primary: primary,
            fallback: DemoHostDashboardService(),
            primaryEndpointDescription: "ws://127.0.0.1:18444"
        )
        let model = HostDashboardModel(service: service)

        await model.load()

        #expect(model.phase == .connected)
        #expect(model.errorMessage == nil)
        #expect(model.health?.agentVersion == "demo-0.1.0")
        #expect(model.connectionMode == .demo)
        #expect(model.hasLiveAgentConnection == false)
        #expect(model.guestAgentInstallEvidence == nil)
        #expect(model.statusText == "Demo mode: Windows agent unavailable")
        #expect(model.connectionDetail == "No Windows agent reachable at ws://127.0.0.1:18444. Showing built-in demo data.")
        #expect(model.agentDiagnostic?.status == .unavailable)
        #expect(model.agentDiagnostic?.endpoint == "ws://127.0.0.1:18444")
        #expect(model.agentDiagnostic?.nextActions.contains("Inside Windows, run Veil Shared\\Veil Guest Agent\\Install Veil Agent.cmd.") == true)
        #expect(model.agentDiagnostic?.nextActions.contains("If the agent still does not connect, run Veil Shared\\Veil Guest Agent\\Collect Veil Agent Diagnostics.cmd and inspect the desktop ZIP.") == true)
        let report = model.runtimeStatusReport(agentEndpoint: "ws://127.0.0.1:18444")
        #expect(report.connection.agentVersion == nil)
        #expect(report.connection.os == nil)
        #expect(report.connection.capabilities == nil)
        #expect(report.guestAgentDiagnostics.endpoint == "ws://127.0.0.1:18444")
        #expect(report.guestAgentDiagnostics.isConnected == false)
        #expect(report.guestAgentDiagnostics.recommendedAction == "diagnose-agent")
        #expect(report.guestAgentDiagnostics.diagnosticCommand == "veil-host-probe --diagnose-agent")
        #expect(report.guestAgentDiagnostics.waitCommand == "veil-vmctl guest-agent-wait --json --wait-seconds 30")
        let blockedRuntime = WindowsAppRuntimeLocalRuntimeStatus(
            isKnown: true,
            state: .stopped,
            bootReady: false,
            canStart: false,
            isRunning: false,
            windowsInstalled: false,
            recommendedAction: "prepare-local-runtime",
            recommendedInstallStatusCommand: "veil-vmctl qemu-install-status --json",
            recommendedPrepareCommand: "veil-vmctl prepare --installer /path/to/Windows.iso",
            reason: "Installer media must be re-selected before boot."
        )
        let blockedReport = model.runtimeStatusReport(
            agentEndpoint: "ws://127.0.0.1:18444",
            localRuntime: blockedRuntime
        )
        #expect(blockedReport.localRuntime.bootReady == false)
        #expect(blockedReport.launchPlan.recommendedAction == "prepare-local-runtime")
        #expect(blockedReport.launchPlan.willOpenAppAutomatically == false)
        #expect(blockedReport.launchPlan.requiresRuntimeStart)
        #expect(blockedReport.launchPlan.recommendedStartCommand == nil)
        #expect(blockedReport.actions.first { $0.id == "runtime.startWindowsForApp" }?.isAvailable == false)
        #expect(blockedReport.actions.first { $0.id == "runtime.waitAgent" }?.isAvailable == true)
        #expect(model.apps.map(\.id).contains("winapp_notepad"))
        #expect(model.canLaunchSelectedApp == false)
    }

    @Test("local runtime prepare command uses selected installer and drivers")
    @MainActor
    func localRuntimePrepareCommandUsesSelectedMedia() {
        let model = HostDashboardModel(service: FakeDashboardService())
        let snapshot = VMRuntimeSnapshot(
            state: .stopped,
            virtualizationAvailable: true,
            architecture: "arm64",
            minimumOSSupported: true,
            profileName: "Windows 11 Arm",
            installerMediaPath: "/Users/test/Downloads/Win11_25H2_Korean_Arm64_v2.iso",
            driverMediaPath: "/Users/test/Downloads/virtio drivers.iso",
            virtualDiskPath: "/Users/test/Virtual Machines/Windows 11 Arm.img",
            preflightChecks: [
                VMPreflightCheck(
                    id: "installer-media",
                    title: "Installer media",
                    detail: "Installer media is in Downloads. Re-select it with the file picker so Veil can store macOS file access before starting Windows.",
                    state: .failed
                )
            ],
            installEvidence: VMInstallEvidenceSummary(
                kind: .setupBlocked,
                isInstalled: false,
                title: "Setup blocked",
                detail: "Installer media is in Downloads."
            ),
            bootReady: false,
            windowsInstalled: false,
            detail: "Installer media requires file picker access."
        )

        let status = model.localRuntimeStatus(snapshot: snapshot)

        #expect(status.recommendedAction == "prepare-local-runtime")
        #expect(status.canStart == false)
        #expect(status.installEvidence?.kind == .setupBlocked)
        #expect(status.installEvidence?.isInstalled == false)
        #expect(status.recommendedPrepareCommand == "veil-vmctl prepare --installer /Users/test/Downloads/Win11_25H2_Korean_Arm64_v2.iso --drivers '/Users/test/Downloads/virtio drivers.iso'")
    }

    @Test("runtime status upgrades profile install flag to live guest agent evidence")
    @MainActor
    func runtimeStatusUpgradesProfileInstallFlagToLiveGuestAgentEvidence() async throws {
        let service = FakeDashboardService(health: .captureReady)
        let model = HostDashboardModel(service: service)
        await model.load()

        let localRuntime = WindowsAppRuntimeLocalRuntimeStatus(
            isKnown: true,
            state: .running,
            bootReady: true,
            canStart: false,
            isRunning: true,
            windowsInstalled: true,
            installEvidence: VMInstallEvidenceSummary(
                kind: .profileFlag,
                isInstalled: true,
                title: "Windows installed",
                detail: "The local profile is marked installed."
            ),
            recommendedAction: "wait-for-guest-agent",
            recommendedInstallStatusCommand: "veil-vmctl qemu-install-status --json",
            reason: "The local Windows runtime is already running."
        )

        let report = model.runtimeStatusReport(localRuntime: localRuntime)

        #expect(report.connection.hasLiveAgentConnection)
        #expect(report.localRuntime.windowsInstalled)
        #expect(report.localRuntime.installEvidence?.kind == .guestAgent)
        #expect(report.localRuntime.installEvidence?.isInstalled == true)
        #expect(report.localRuntime.installEvidence?.detail.contains("0.1.0") == true)
    }

    @Test("local runtime reports display recovery when running console preview is stale")
    @MainActor
    func localRuntimeReportsDisplayRecoveryForStalePreview() {
        let model = HostDashboardModel(service: FakeDashboardService())
        let snapshot = VMRuntimeSnapshot(
            state: .running,
            virtualizationAvailable: true,
            architecture: "arm64",
            minimumOSSupported: true,
            profileName: "Windows 11 Arm",
            virtualDiskPath: "/Users/test/Virtual Machines/Windows 11 Arm.img",
            latestConsoleLaunch: VMConsoleLaunchEvidence(
                provider: "QEMU/HVF",
                pid: 94195,
                processLogPath: "/tmp/qemu.log",
                monitorSocketPath: "/tmp/qemu.sock",
                qmpSocketPath: "/tmp/qemu.qmp.sock",
                vncHost: "127.0.0.1",
                vncPort: 5900,
                consoleScreenshotPath: "/tmp/qemu-console.png",
                previewStatus: .stale,
                startedAt: Date(timeIntervalSince1970: 1_000)
            ),
            installEvidence: VMInstallEvidenceSummary(
                kind: .guestAgent,
                isInstalled: true,
                title: "Guest agent connected",
                detail: "The guest agent has already been proved for this display recovery check."
            ),
            bootReady: true,
            windowsInstalled: true,
            detail: "Windows is running."
        )

        let status = model.localRuntimeStatus(snapshot: snapshot)

        #expect(status.isRunning)
        #expect(status.installEvidence?.kind == .guestAgent)
        #expect(status.installEvidence?.isInstalled == true)
        #expect(status.consolePreviewStatus == .stale)
        #expect(status.recommendedAction == "recover-runtime-display")
        #expect(status.recommendedDisplayCommand == "veil-vmctl qemu-display-smoke --json")
        #expect(status.recommendedRecoveryCommand == "veil-vmctl qemu-capture --json")
        #expect(status.reason.contains("embedded console preview is stale"))

        let report = model.runtimeStatusReport(localRuntime: status)
        #expect(report.actions.first { $0.id == "runtime.recoverDisplay" }?.isAvailable == true)
        #expect(report.releaseGate.isPassing == false)
        #expect(report.releaseGate.recommendedAction == "windowsSetup")
        #expect(report.releaseGate.steps.first { $0.id == "windowsSetup" }?.isPassing == false)
        #expect(report.releaseGate.steps.first { $0.id == "windowsSetup" }?.nextActionCommand == "veil-vmctl qemu-capture --json")
        #expect(report.primaryNextAction.id == "windowsSetup")
        #expect(report.primaryNextAction.actionId == "runtime.recoverDisplay")
        #expect(report.primaryNextAction.command == "veil-vmctl qemu-capture --json")
    }

    @Test("local runtime blocks guest agent repair when attached guest tools media is stale")
    @MainActor
    func localRuntimeBlocksGuestAgentRepairForStaleMedia() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let sharedFolderURL = directory.appendingPathComponent("Veil Shared", isDirectory: true)
        let agentBundleURL = sharedFolderURL.appendingPathComponent("Veil Guest Agent", isDirectory: true)
        try FileManager.default.createDirectory(at: agentBundleURL, withIntermediateDirectories: true)
        defer {
            try? FileManager.default.removeItem(at: directory)
        }

        let installerURL = directory.appendingPathComponent("Windows.iso")
        let driverURL = directory.appendingPathComponent("virtio-win.iso")
        let mediaURL = sharedFolderURL.appendingPathComponent("VeilAutoInstall.iso")
        let answerURL = sharedFolderURL.appendingPathComponent("Autounattend.xml")
        let scriptURL = agentBundleURL.appendingPathComponent("V.cmd")
        try Data("installer".utf8).write(to: installerURL)
        try Data("drivers".utf8).write(to: driverURL)
        try Data("old media".utf8).write(to: mediaURL)
        try Data("<unattend />".utf8).write(to: answerURL)
        try Data("new script".utf8).write(to: scriptURL)

        let oldDate = Date(timeIntervalSince1970: 1_782_900_000)
        let newDate = Date(timeIntervalSince1970: 1_782_910_000)
        try FileManager.default.setAttributes([.modificationDate: oldDate], ofItemAtPath: mediaURL.path)
        try FileManager.default.setAttributes([.modificationDate: oldDate], ofItemAtPath: answerURL.path)
        try FileManager.default.setAttributes([.modificationDate: newDate], ofItemAtPath: scriptURL.path)
        try FileManager.default.setAttributes([.modificationDate: newDate], ofItemAtPath: agentBundleURL.path)

        let snapshot = VMRuntimeSnapshot(
            state: .running,
            virtualizationAvailable: true,
            architecture: "arm64",
            minimumOSSupported: true,
            profileName: "Windows 11 Arm",
            installerMediaPath: installerURL.path,
            driverMediaPath: driverURL.path,
            automaticInstallAnswerFilePath: answerURL.path,
            automaticInstallMediaPath: mediaURL.path,
            installEvidence: VMInstallEvidenceSummary(
                kind: .profileFlag,
                isInstalled: true,
                title: "Windows installed",
                detail: "The profile is marked installed."
            ),
            bootReady: true,
            windowsInstalled: true,
            detail: "Windows is running."
        )
        let model = HostDashboardModel(service: FakeDashboardService())

        let status = model.localRuntimeStatus(snapshot: snapshot)

        #expect(status.recommendedAction == "rebuild-guest-tools-media")
        #expect(status.requiresGuestToolsMediaRebuild)
        #expect(status.canStart == false)
        #expect(status.automaticInstallMediaStatus?.state == .stale)
        #expect(status.recommendedMediaRebuildCommand == "veil-vmctl prepare --installer \(installerURL.path) --drivers \(driverURL.path)")
        #expect(status.recommendedPowerDownCommand == "veil-vmctl app-runtime-action --json --action stop-runtime")
        #expect(status.recommendedPrepareCommand == nil)
        #expect(status.reason.contains("power down Windows"))

        let primary = FakeDashboardService(error: URLError(.cannotConnectToHost))
        let fallback = DemoHostDashboardService()
        let service = FallbackHostDashboardService(
            primary: primary,
            fallback: fallback,
            primaryEndpointDescription: "ws://127.0.0.1:18444"
        )
        let appModel = HostDashboardModel(service: service)
        await appModel.load()
        await appModel.launchSelectedApp()

        let report = appModel.runtimeStatusReport(localRuntime: status)

        #expect(report.localRuntime.requiresGuestToolsMediaRebuild)
        #expect(report.launchPlan.recommendedAction == "rebuild-guest-tools-media-before-launch")
        #expect(report.launchPlan.recommendedRepairCommand == nil)
        #expect(report.launchPlan.willOpenAppAutomatically == false)
        #expect(report.menuBarIntegration.primaryActionId == "runtime.stopWhenIdle")
        #expect(report.menuBarIntegration.primaryActionTitle == "Stop Windows")
        #expect(report.menuBarIntegration.primaryActionAvailable)
        #expect(report.releaseGate.recommendedAction == "windowsSetup")
        #expect(report.releaseGate.steps.first { $0.id == "windowsSetup" }?.nextActionCommand == "veil-vmctl app-runtime-action --json --action stop-runtime")
        #expect(report.primaryNextAction.id == "windowsSetup")
        #expect(report.primaryNextAction.actionId == "runtime.stopWhenIdle")
        #expect(report.actions.first { $0.id == "runtime.repairGuestAgentForApp" }?.isAvailable == false)
        #expect(report.actions.first { $0.id == "runtime.startWindowsForApp" }?.isAvailable == false)
        #expect(report.actions.first { $0.id == "runtime.stopWhenIdle" }?.isAvailable == true)
    }

    @Test("refresh live agent retries after demo fallback")
    @MainActor
    func refreshLiveAgentRetriesAfterDemoFallback() async throws {
        let primary = FakeDashboardService(error: URLError(.cannotConnectToHost))
        let service = FallbackHostDashboardService(
            primary: primary,
            fallback: DemoHostDashboardService(),
            primaryEndpointDescription: "ws://127.0.0.1:18444"
        )
        let model = HostDashboardModel(service: service)

        await model.load()
        primary.error = nil
        _ = await model.refreshLiveAgentIfNeeded()

        #expect(model.phase == .connected)
        #expect(model.connectionMode == .agent)
        #expect(model.health?.agentVersion == "0.1.0")
        #expect(model.hasLiveAgentConnection)
        #expect(model.connectionDetail == nil)
        #expect(model.agentDiagnostic == nil)
        #expect(primary.loadCount == 2)
    }

    @Test("queues Notepad launch until live agent connects")
    @MainActor
    func queuesNotepadLaunchUntilLiveAgentConnects() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let pendingLaunchStore = JSONPendingLaunchIntentStore(directory: directory)
        let primary = FakeDashboardService(error: URLError(.cannotConnectToHost))
        let service = FallbackHostDashboardService(
            primary: primary,
            fallback: DemoHostDashboardService(),
            primaryEndpointDescription: "ws://127.0.0.1:18444"
        )
        let model = HostDashboardModel(service: service, pendingLaunchIntentStore: pendingLaunchStore)

        await model.load()
        await model.launchSelectedApp()

        #expect(model.phase == .connected)
        #expect(model.errorMessage == nil)
        #expect(model.lastLaunch == nil)
        #expect(model.mirrorSessions.isEmpty)
        #expect(model.pendingLaunchAppId == "winapp_notepad")
        #expect(model.connectionMode == .demo)
        #expect(model.connectionDetail == "No Windows agent reachable at ws://127.0.0.1:18444. Showing built-in demo data.")
        #expect(model.launchPlanStatus().selectedAppId == "winapp_notepad")
        #expect(model.launchPlanStatus().pendingLaunchAppId == "winapp_notepad")
        #expect(model.launchPlanStatus().willOpenAppAutomatically)
        #expect(model.launchPlanStatus().requiresRuntimeStart)
        #expect(model.launchPlanStatus().requiresGuestAgent)
        #expect(model.launchPlanStatus().recommendedAction == "start-runtime-for-pending-launch")
        #expect(model.launchPlanStatus().recommendedStartCommand == "veil-vmctl qemu-start --json --wait-seconds 30")
        #expect(model.launchPlanStatus().recommendedWaitCommand == "veil-vmctl guest-agent-wait --json --wait-seconds 30")
        #expect(model.launchPlanStatus().recommendedLaunchCommand == "veil-vmctl app-runtime-action --json --action fulfill-pending")
        let queuedReport = model.runtimeStatusReport()
        #expect(queuedReport.pendingLaunch.isQueued)
        #expect(queuedReport.pendingLaunch.appId == "winapp_notepad")
        #expect(queuedReport.pendingLaunch.willLaunchOnAgentReconnect)
        #expect(queuedReport.pendingLaunch.recommendedAction == "auto-launch-on-agent-reconnect")
        #expect(queuedReport.pendingLaunch.reason == "Veil will launch the queued Windows app after the app connection returns.")
        #expect(queuedReport.dockIntegration.openWindowCount == 0)
        #expect(queuedReport.dockIntegration.pendingLaunchCount == 1)
        #expect(queuedReport.dockIntegration.restorableAppCount == 0)
        #expect(queuedReport.dockIntegration.badgeLabel == "...")
        #expect(queuedReport.menuBarIntegration.statusTitle == "Notepad Waiting")
        #expect(queuedReport.menuBarIntegration.symbolName == "clock.fill")
        #expect(queuedReport.menuBarIntegration.primaryActionId == "runtime.startWindowsForApp")
        #expect(queuedReport.menuBarIntegration.primaryActionTitle == "Open Windows for Notepad")
        #expect(queuedReport.menuBarIntegration.primaryActionAvailable)
        #expect(model.canFulfillPendingLaunch == false)
        #expect(queuedReport.actions.first { $0.id == "runtime.startWindowsForApp" }?.isAvailable == true)
        #expect(queuedReport.actions.first { $0.id == "runtime.repairGuestAgentForApp" }?.isAvailable == false)
        #expect(queuedReport.actions.first { $0.id == "runtime.fulfillPendingLaunch" }?.isAvailable == false)
        #expect(queuedReport.actions.first { $0.id == "runtime.waitAgent" }?.isAvailable == true)
        #expect(try await pendingLaunchStore.load()?.appId == "winapp_notepad")

        let runningRuntime = WindowsAppRuntimeLocalRuntimeStatus(
            isKnown: true,
            state: .running,
            bootReady: true,
            canStart: false,
            isRunning: true,
            windowsInstalled: true,
            recommendedAction: "wait-for-guest-agent",
            recommendedInstallStatusCommand: "veil-vmctl qemu-install-status --json",
            reason: "The local Windows runtime is already running."
        )
        let runningQueuedReport = model.runtimeStatusReport(localRuntime: runningRuntime)
        #expect(runningQueuedReport.launchPlan.recommendedAction == "repair-guest-agent-for-pending-launch")
        #expect(runningQueuedReport.launchPlan.willOpenAppAutomatically)
        #expect(runningQueuedReport.launchPlan.recommendedStartCommand == nil)
        #expect(runningQueuedReport.launchPlan.recommendedWaitCommand == "veil-vmctl guest-agent-wait --json --wait-seconds 30")
        #expect(runningQueuedReport.launchPlan.recommendedRepairCommand == "veil-vmctl app-runtime-action --json --action repair-agent --wait-seconds 120")
        #expect(runningQueuedReport.launchPlan.recommendedLaunchCommand == "veil-vmctl app-runtime-action --json --action fulfill-pending")
        #expect(runningQueuedReport.launchPlan.reason == "Windows is running and the selected app launch is queued; repair or start the guest agent, then open the app automatically.")
        #expect(runningQueuedReport.actions.first { $0.id == "runtime.startWindowsForApp" }?.isAvailable == false)
        #expect(runningQueuedReport.actions.first { $0.id == "runtime.repairGuestAgentForApp" }?.isAvailable == true)
        #expect(runningQueuedReport.actions.first { $0.id == "runtime.fulfillPendingLaunch" }?.isAvailable == false)
        #expect(runningQueuedReport.actions.first { $0.id == "runtime.waitAgent" }?.isAvailable == true)
        #expect(runningQueuedReport.releaseGate.isPassing == false)
        #expect(runningQueuedReport.releaseGate.recommendedAction == "openWindowsApp")
        #expect(runningQueuedReport.releaseGate.steps.first { $0.id == "openWindowsApp" }?.isPassing == false)
        #expect(runningQueuedReport.releaseGate.steps.first { $0.id == "openWindowsApp" }?.state == "ready")
        #expect(runningQueuedReport.releaseGate.steps.first { $0.id == "openWindowsApp" }?.title == "Continue Notepad")
        #expect(runningQueuedReport.releaseGate.steps.first { $0.id == "openWindowsApp" }?.nextActionCommand == "veil-vmctl app-runtime-action --json --action repair-agent --wait-seconds 120")
        #expect(runningQueuedReport.primaryNextAction.id == "openWindowsApp")
        #expect(runningQueuedReport.primaryNextAction.title == "Continue Notepad")
        #expect(runningQueuedReport.primaryNextAction.actionId == "runtime.repairGuestAgentForApp")
        #expect(runningQueuedReport.primaryNextAction.command == "veil-vmctl app-runtime-action --json --action repair-agent --wait-seconds 120")
        #expect(runningQueuedReport.launchOnboarding.currentStepTitle == "Continue Notepad")
        #expect(runningQueuedReport.launchOnboarding.currentStepDetail == "Reconnect the app connection, then open Notepad automatically.")
        #expect(runningQueuedReport.launchOnboarding.completedStepCount == 3)
        #expect(runningQueuedReport.launchOnboarding.totalStepCount == 5)
        #expect(runningQueuedReport.launchOnboarding.currentStepNumber == 3)
        #expect(runningQueuedReport.launchOnboarding.progressLabel == "Step 3 of 5")

        primary.error = nil
        let fulfilledLaunch = await model.refreshLiveAgentIfNeeded()
        let fulfilledReport = model.runtimeStatusReport()

        #expect(model.connectionMode == .agent)
        #expect(model.pendingLaunchAppId == nil)
        #expect(model.canFulfillPendingLaunch == false)
        #expect(fulfilledReport.dockIntegration.pendingLaunchCount == 0)
        #expect(fulfilledReport.dockIntegration.badgeLabel == "1")
        #expect(fulfilledReport.macWindowIntegration.foregroundableWindowCount == 1)
        #expect(fulfilledReport.macWindowIntegration.foregroundWindowTitle == "Untitled - Notepad")
        #expect(fulfilledReport.pendingLaunch.isQueued == false)
        #expect(fulfilledReport.pendingLaunch.appId == nil)
        #expect(fulfilledReport.pendingLaunch.willLaunchOnAgentReconnect == false)
        #expect(fulfilledReport.pendingLaunch.recommendedAction == "none")
        #expect(fulfilledReport.actions.first { $0.id == "runtime.fulfillPendingLaunch" }?.isAvailable == false)
        #expect(model.lastLaunch?.window.title == "Untitled - Notepad")
        #expect(fulfilledLaunch?.window.title == "Untitled - Notepad")
        #expect(model.mirrorSessions.map(\.id) == ["hwnd:0003029A"])
        #expect(primary.launchCount == 1)
        #expect(try await pendingLaunchStore.load()?.appId == nil)
    }

    @Test("loads persisted pending app launch intent on startup")
    @MainActor
    func loadsPersistedPendingAppLaunchIntentOnStartup() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let pendingLaunchStore = JSONPendingLaunchIntentStore(directory: directory)
        try await pendingLaunchStore.save(PendingLaunchIntent(appId: "winapp_notepad"))
        let service = FakeDashboardService(health: .captureReady)
        let model = HostDashboardModel(
            service: service,
            pendingLaunchIntentStore: pendingLaunchStore
        )

        await model.loadRestoreIntent()
        await model.load()

        #expect(model.pendingLaunchAppId == "winapp_notepad")
        #expect(model.runtimeStatusReport().pendingLaunch.isQueued)
        #expect(model.runtimeStatusReport().pendingLaunch.recommendedAction == "launch-pending-now")
        #expect(model.runtimeStatusReport().launchPlan.recommendedAction == "fulfill-pending-now")
        #expect(model.runtimeStatusReport().launchPlan.willOpenAppAutomatically)
        #expect(model.runtimeStatusReport().launchPlan.recommendedLaunchCommand == "veil-vmctl app-runtime-action --json --action fulfill-pending")
        #expect(model.canFulfillPendingLaunch)
        #expect(model.runtimeStatusReport().actions.first { $0.id == "runtime.fulfillPendingLaunch" }?.isAvailable == true)

        let fulfilledLaunch = await model.fulfillPendingLaunch()

        #expect(fulfilledLaunch?.window.windowId == "hwnd:0003029A")
        #expect(model.pendingLaunchAppId == nil)
        #expect(model.canFulfillPendingLaunch == false)
        #expect(model.runtimeStatusReport().actions.first { $0.id == "runtime.fulfillPendingLaunch" }?.isAvailable == false)
        #expect(try await pendingLaunchStore.load()?.appId == nil)
        #expect(service.launchCount == 1)
    }

    @Test("pending app launch stays the menu primary action over reconnect restore")
    @MainActor
    func pendingAppLaunchStaysMenuPrimaryActionOverReconnectRestore() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let intentStore = JSONWindowRestoreIntentStore(directory: directory)
        let pendingLaunchStore = JSONPendingLaunchIntentStore(directory: directory)
        try await intentStore.save(
            WindowRestoreIntent(
                appIds: ["winapp_notepad"],
                appWindowCounts: ["winapp_notepad": 2]
            )
        )
        try await pendingLaunchStore.save(PendingLaunchIntent(appId: "winapp_notepad"))
        let primary = FakeDashboardService(health: .captureReady)
        primary.error = URLError(.cannotConnectToHost)
        let service = FallbackHostDashboardService(
            primary: primary,
            fallback: DemoHostDashboardService(),
            primaryEndpointDescription: "ws://127.0.0.1:18444"
        )
        let model = HostDashboardModel(
            service: service,
            restoreIntentStore: intentStore,
            pendingLaunchIntentStore: pendingLaunchStore
        )

        await model.loadRestoreIntent()
        await model.load()
        let report = model.runtimeStatusReport()

        #expect(report.pendingLaunch.isQueued)
        #expect(report.dockIntegration.restorableAppCount == 1)
        #expect(report.menuBarIntegration.statusTitle == "Notepad Waiting")
        #expect(report.menuBarIntegration.symbolName == "clock.fill")
        #expect(report.menuBarIntegration.primaryActionId == "runtime.startWindowsForApp")
        #expect(report.menuBarIntegration.primaryActionTitle == "Open Windows for Notepad")
        #expect(report.actions.first { $0.id == "windowsApps.reconnectRestore" }?.isAvailable == true)
    }

    @Test("does not hide live launch failures behind demo fallback")
    @MainActor
    func doesNotHideLiveLaunchFailuresBehindDemoFallback() async throws {
        let primary = FakeDashboardService()
        let service = FallbackHostDashboardService(
            primary: primary,
            fallback: DemoHostDashboardService(),
            primaryEndpointDescription: "ws://127.0.0.1:18444"
        )
        let model = HostDashboardModel(service: service)

        await model.load()
        primary.error = URLError(.cannotConnectToHost)
        await model.launchSelectedApp()

        #expect(model.phase == .failed)
        #expect(model.connectionMode == .agent)
        #expect(model.lastLaunch == nil)
        #expect(model.mirrorSessions.isEmpty)
        #expect(model.errorMessage != nil)
        #expect(primary.launchCount == 0)
    }

    @Test("restores mapped app windows after the live agent reconnects")
    @MainActor
    func restoresMappedAppWindowsAfterReconnect() async throws {
        let primary = FakeDashboardService(health: .captureReady)
        let service = FallbackHostDashboardService(
            primary: primary,
            fallback: DemoHostDashboardService(),
            primaryEndpointDescription: "ws://127.0.0.1:18444"
        )
        let model = HostDashboardModel(service: service)

        await model.load()
        await model.launchSelectedApp()

        #expect(model.restorableAppIds == ["winapp_notepad"])
        #expect(primary.launchCount == 1)
        #expect(primary.frameSubscriptions == ["hwnd:0003029A"])

        primary.error = URLError(.cannotConnectToHost)
        await model.load()

        #expect(model.connectionMode == .demo)
        #expect(model.hasLiveAgentConnection == false)

        primary.error = nil
        let restored = await model.restoreMirroredWindowsAfterReconnect()

        #expect(restored.map(\.window.windowId) == ["hwnd:0003029A"])
        #expect(model.connectionMode == .agent)
        #expect(model.mirrorSessions.map(\.id) == ["hwnd:0003029A"])
        #expect(model.restorableAppIds == ["winapp_notepad"])
        #expect(primary.launchCount == 2)
        #expect(primary.frameSubscriptions == ["hwnd:0003029A", "hwnd:0003029A"])
    }

    @Test("restores multiple same-app windows after reconnect")
    @MainActor
    func restoresMultipleSameAppWindowsAfterReconnect() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let intentStore = JSONWindowRestoreIntentStore(directory: directory)
        try await intentStore.save(
            WindowRestoreIntent(
                appIds: ["winapp_notepad"],
                appWindowCounts: ["winapp_notepad": 2]
            )
        )
        let service = FakeDashboardService(health: .captureReady)
        service.launchWindows = [.notepad, .secondNotepad]
        let model = HostDashboardModel(service: service, restoreIntentStore: intentStore)

        await model.loadRestoreIntent()
        await model.load()
        let restored = await model.restoreMirroredWindowsAfterReconnect()

        #expect(restored.map(\.window.windowId) == ["hwnd:0003029A", "hwnd:00010500"])
        #expect(model.mirrorSessions.map(\.id) == ["hwnd:0003029A", "hwnd:00010500"])
        #expect(model.restorableAppIds == ["winapp_notepad"])
        #expect(model.restorableAppWindowCounts == ["winapp_notepad": 2])
        #expect(try await intentStore.load()?.appWindowCounts == ["winapp_notepad": 2])
        #expect(service.launchedAppIds == ["winapp_notepad", "winapp_notepad"])
        #expect(service.frameSubscriptions == ["hwnd:0003029A", "hwnd:00010500"])

        let report = model.runtimeStatusReport()
        #expect(report.dockIntegration.restorableAppCount == 1)
        #expect(report.dockIntegration.restorableWindowCount == 2)
    }

    @Test("clears a stale error message when there is nothing to restore")
    @MainActor
    func clearsStaleErrorMessageWhenThereIsNothingToRestore() async throws {
        // Regression test: restoreMirroredWindowsAfterReconnect() used to leave an unrelated,
        // already-stale errorMessage untouched on its early-return "nothing to restore" path, so a
        // caller reading errorMessage right after an empty restore result could misreport an old,
        // unrelated failure as if it were this call's own failure.
        let primary = FakeDashboardService()
        let service = FallbackHostDashboardService(
            primary: primary,
            fallback: DemoHostDashboardService(),
            primaryEndpointDescription: "ws://127.0.0.1:18444"
        )
        let model = HostDashboardModel(service: service)

        await model.load()
        primary.error = URLError(.cannotConnectToHost)
        await model.launchSelectedApp()
        #expect(model.errorMessage != nil)
        #expect(model.restorableAppIds.isEmpty)

        let restored = await model.restoreMirroredWindowsAfterReconnect()

        #expect(restored.isEmpty)
        #expect(model.errorMessage == nil)
    }

    @Test("removes restored app intent when a mapped window closes")
    @MainActor
    func removesRestoredAppIntentWhenMappedWindowCloses() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let intentStore = JSONWindowRestoreIntentStore(directory: directory)
        let service = FakeDashboardService(health: .captureReady)
        let model = HostDashboardModel(service: service, restoreIntentStore: intentStore)

        await model.launchNotepad()
        #expect(try await intentStore.load()?.appIds == ["winapp_notepad"])

        _ = await model.closeMirrorSession(windowId: "hwnd:0003029A")

        #expect(model.restorableAppIds.isEmpty)
        #expect(try await intentStore.load()?.appIds == [])
    }

    @Test("keeps restored app intent until the last same-app window closes")
    @MainActor
    func keepsRestoredAppIntentUntilLastSameAppWindowCloses() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let intentStore = JSONWindowRestoreIntentStore(directory: directory)
        let service = FakeDashboardService(health: .captureReady)
        let model = HostDashboardModel(service: service, restoreIntentStore: intentStore)

        await model.launchNotepad()
        _ = try await model.receiveProtocolMessage(Data(WindowCreatedEvent.secondNotepadCreatedJSON.utf8))

        #expect(model.mirrorSessions.map(\.id) == ["hwnd:0003029A", "hwnd:00010500"])
        #expect(model.restorableAppIds == ["winapp_notepad"])
        #expect(model.restorableAppWindowCounts == ["winapp_notepad": 2])
        #expect(try await intentStore.load()?.appIds == ["winapp_notepad"])
        #expect(try await intentStore.load()?.appWindowCounts == ["winapp_notepad": 2])

        _ = await model.closeMirrorSession(windowId: "hwnd:0003029A")

        #expect(model.mirrorSessions.map(\.id) == ["hwnd:00010500"])
        #expect(model.restorableAppIds == ["winapp_notepad"])
        #expect(model.restorableAppWindowCounts == ["winapp_notepad": 1])
        #expect(try await intentStore.load()?.appIds == ["winapp_notepad"])
        #expect(try await intentStore.load()?.appWindowCounts == ["winapp_notepad": 1])

        _ = await model.closeMirrorSession(windowId: "hwnd:00010500")

        #expect(model.mirrorSessions.isEmpty)
        #expect(model.restorableAppIds.isEmpty)
        #expect(model.restorableAppWindowCounts.isEmpty)
        #expect(try await intentStore.load()?.appIds == [])
        #expect(try await intentStore.load()?.appWindowCounts == nil)
    }

    @Test("loads persisted mapped app intent on startup")
    @MainActor
    func loadsPersistedMappedAppIntentOnStartup() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let intentStore = JSONWindowRestoreIntentStore(directory: directory)
        try await intentStore.save(
            WindowRestoreIntent(
                appIds: ["winapp_notepad"],
                appWindowCounts: ["winapp_notepad": 2]
            )
        )
        let model = HostDashboardModel(
            service: FakeDashboardService(health: .captureReady),
            restoreIntentStore: intentStore
        )

        await model.loadRestoreIntent()
        await model.load()

        #expect(model.restorableAppIds == ["winapp_notepad"])
        #expect(model.canRestoreMirrorSessions)
        #expect(model.canReconnectRestoreMirrorSessions)
        #expect(model.runtimeStatusReport().actions.first { $0.id == "windowsApps.reconnectRestore" }?.isAvailable == true)
    }

    @Test("reports reconnect restore availability before the live agent reconnects")
    @MainActor
    func reportsReconnectRestoreAvailabilityBeforeLiveAgentReconnects() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let intentStore = JSONWindowRestoreIntentStore(directory: directory)
        let pendingLaunchStore = JSONPendingLaunchIntentStore(directory: directory)
        try await intentStore.save(
            WindowRestoreIntent(
                appIds: ["winapp_notepad"],
                appWindowCounts: ["winapp_notepad": 2]
            )
        )
        let primary = FakeDashboardService(health: .captureReady)
        primary.error = URLError(.cannotConnectToHost)
        let service = FallbackHostDashboardService(
            primary: primary,
            fallback: DemoHostDashboardService(),
            primaryEndpointDescription: "ws://127.0.0.1:18444"
        )
        let model = HostDashboardModel(
            service: service,
            restoreIntentStore: intentStore,
            pendingLaunchIntentStore: pendingLaunchStore
        )

        await model.loadRestoreIntent()
        await model.load()
        let report = model.runtimeStatusReport()

        #expect(model.hasLiveAgentConnection == false)
        #expect(model.canRestoreMirrorSessions == false)
        #expect(model.canReconnectRestoreMirrorSessions)
        #expect(model.restorableAppWindowCounts == ["winapp_notepad": 2])
        #expect(report.dockIntegration.openWindowCount == 0)
        #expect(report.dockIntegration.pendingLaunchCount == 0)
        #expect(report.dockIntegration.restorableAppCount == 1)
        #expect(report.dockIntegration.restorableWindowCount == 2)
        #expect(report.dockIntegration.badgeLabel == "R2")
        #expect(report.menuBarIntegration.statusTitle == "Notepad Windows Can Reconnect")
        #expect(report.menuBarIntegration.primaryActionTitle == "Reconnect 2 Notepad Windows")
        #expect(report.dockIntegration.canRestorePreviousApps == false)
        #expect(report.dockIntegration.canReconnectPreviousApps)
        #expect(report.menuBarIntegration.symbolName == "arrow.counterclockwise.circle.fill")
        #expect(report.menuBarIntegration.primaryActionId == "windowsApps.reconnectRestore")
        #expect(report.menuBarIntegration.primaryActionAvailable)
        #expect(report.menuBarIntegration.canReconnectPreviousApps)
        #expect(report.actions.first { $0.id == "windowsApps.restorePrevious" }?.isAvailable == false)
        #expect(report.actions.first { $0.id == "windowsApps.reconnectRestore" }?.isAvailable == true)
    }

    @Test("does not hide primary agent protocol failures behind demo fallback")
    @MainActor
    func doesNotHidePrimaryAgentProtocolFailuresBehindDemoFallback() async throws {
        let service = FallbackHostDashboardService(
            primary: FakeDashboardService(error: VeilHostError.appMissing("winapp_notepad")),
            fallback: DemoHostDashboardService(),
            primaryEndpointDescription: "ws://127.0.0.1:18444"
        )
        let model = HostDashboardModel(service: service)

        await model.load()

        #expect(model.phase == .failed)
        #expect(model.errorMessage == "The Windows app winapp_notepad is not available from the Windows agent.")
        #expect(model.agentDiagnostic?.status == .unavailable)
        #expect(model.agentDiagnostic?.errorMessage == "The Windows app winapp_notepad is not available from the Windows agent.")
        #expect(model.health == nil)
        #expect(model.apps.isEmpty)
    }

    @Test("does not hide close failures behind demo fallback")
    @MainActor
    func doesNotHideCloseFailuresBehindDemoFallback() async throws {
        let primary = FakeDashboardService(health: .captureReady)
        let service = FallbackHostDashboardService(
            primary: primary,
            fallback: DemoHostDashboardService(),
            primaryEndpointDescription: "ws://127.0.0.1:18444"
        )
        let model = HostDashboardModel(service: service)

        await model.launchNotepad()
        primary.error = URLError(.cannotConnectToHost)
        let response = await model.closeMirrorSession(windowId: "hwnd:0003029A")

        #expect(response == nil)
        #expect(model.phase == .failed)
        #expect(model.activeWindows.map(\.windowId) == ["hwnd:0003029A"])
        #expect(model.mirrorSessions.map(\.id) == ["hwnd:0003029A"])
    }
}

@MainActor
private final class FakeDashboardService: HostDashboardService {
    var error: (any Error)?
    var health: AgentHealthResponse
    var apps: [WindowsApp]
    var closeAccepted: Bool
    var agentWaitReport: AgentConnectionWaitReport?
    var launchWindows: [WindowCreatedEvent] = []
    private(set) var loadCount = 0
    private(set) var launchCount = 0
    private(set) var launchedAppIds: [String] = []
    private(set) var openedFiles: [(appId: String, fileName: String, contentBase64: String)] = []
    private(set) var focusedWindowIds: [String] = []
    private(set) var closedWindowIds: [String] = []
    private(set) var mouseInputs: [InputMouseEvent] = []
    private(set) var keyInputs: [InputKeyEvent] = []
    private(set) var clipboardTexts: [ClipboardTextSet] = []
    private(set) var frameSubscriptions: [String] = []
    private(set) var frameUnsubscriptions: [String] = []

    init(
        error: (any Error)? = nil,
        health: AgentHealthResponse = .fixture,
        apps: [WindowsApp] = [.notepad],
        closeAccepted: Bool = true,
        agentWaitReport: AgentConnectionWaitReport? = nil
    ) {
        self.error = error
        self.health = health
        self.apps = apps
        self.closeAccepted = closeAccepted
        self.agentWaitReport = agentWaitReport
    }

    func loadOverview() async throws -> HostOverview {
        loadCount += 1
        if let error {
            throw error
        }

        return HostOverview(
            health: health,
            apps: apps
        )
    }

    func launchApp(appId: String) async throws -> WindowsAppLaunchResult {
        if let error {
            throw error
        }

        launchCount += 1
        launchedAppIds.append(appId)
        let window = launchWindows.isEmpty ? .fixture(appId: appId) : launchWindows.removeFirst()
        return WindowsAppLaunchResult(
            health: health,
            apps: apps,
            launch: .fixture,
            window: window
        )
    }

    func launchNotepad() async throws -> NotepadLaunchResult {
        try await launchApp(appId: "winapp_notepad")
    }

    func openFile(appId: String, fileName: String, contentBase64: String) async throws -> WindowsAppLaunchResult {
        if let error {
            throw error
        }

        openedFiles.append((appId, fileName, contentBase64))
        return WindowsAppLaunchResult(
            health: health,
            apps: apps,
            launch: .fixture,
            window: .fixture(appId: appId)
        )
    }

    func focusWindow(windowId: String) async throws -> WindowFocusResponse {
        if let error {
            throw error
        }

        focusedWindowIds.append(windowId)
        return WindowFocusResponse(
            type: .windowFocusResponse,
            requestId: "req_focus_window",
            windowId: windowId,
            accepted: true
        )
    }

    func closeWindow(windowId: String) async throws -> WindowCloseResponse {
        if let error {
            throw error
        }

        closedWindowIds.append(windowId)
        return WindowCloseResponse(
            type: .windowCloseResponse,
            requestId: "req_close_notepad",
            windowId: windowId,
            accepted: closeAccepted
        )
    }

    func sendMouseInput(_ input: InputMouseEvent) async throws {
        if let error {
            throw error
        }

        mouseInputs.append(input)
    }

    func sendKeyInput(_ input: InputKeyEvent) async throws {
        if let error {
            throw error
        }

        keyInputs.append(input)
    }

    func sendClipboardText(_ clipboard: ClipboardTextSet) async throws {
        if let error {
            throw error
        }

        clipboardTexts.append(clipboard)
    }

    func subscribeWindowFrames(windowId: String) async throws {
        if let error {
            throw error
        }

        frameSubscriptions.append(windowId)
    }

    func unsubscribeWindowFrames(windowId: String) async throws {
        if let error {
            throw error
        }

        frameUnsubscriptions.append(windowId)
    }

    func waitForAgentConnection(endpoint: String, timeoutSeconds: Int) async -> AgentConnectionWaitReport {
        if let agentWaitReport {
            return agentWaitReport
        }

        let diagnostic = AgentConnectionDiagnostic.unavailable(
            endpoint: endpoint,
            errorMessage: "FakeDashboardService does not simulate a live guest agent connection."
        )
        return AgentConnectionWaitReport(
            endpoint: endpoint,
            status: .unavailable,
            waitedSeconds: min(max(timeoutSeconds, 0), 300),
            attempts: 1,
            diagnostic: diagnostic,
            nextActions: diagnostic.nextActions
        )
    }
}

private struct StaticHostEventSource: HostEventSource {
    var messages: [Data]
    var failure: (any Error)?

    init(messages: [Data], failure: (any Error)? = nil) {
        self.messages = messages
        self.failure = failure
    }

    func eventMessages() -> AsyncThrowingStream<Data, any Error> {
        AsyncThrowingStream { continuation in
            for message in messages {
                continuation.yield(message)
            }
            continuation.finish(throwing: failure)
        }
    }
}

private extension AgentHealthResponse {
    static var fixture: AgentHealthResponse {
        AgentHealthResponse(
            type: .agentHealthResponse,
            requestId: "req_health",
            protocolVersion: 1,
            agentVersion: "0.1.0",
            os: "windows-arm64",
            session: AgentSession(interactive: true, user: "veil-user"),
            capabilities: AgentCapabilities(
                appList: true,
                appLaunch: true,
                windowTracking: true,
                windowCapture: false,
                input: false,
                clipboardText: false
            )
        )
    }

    static var captureReady: AgentHealthResponse {
        AgentHealthResponse(
            type: .agentHealthResponse,
            requestId: "req_health",
            protocolVersion: 1,
            agentVersion: "0.1.0",
            os: "windows-arm64",
            session: AgentSession(interactive: true, user: "veil-user"),
            capabilities: AgentCapabilities(
                appList: true,
                appLaunch: true,
                windowTracking: true,
                windowCapture: true,
                input: false,
                clipboardText: false
            )
        )
    }

    static var inputReady: AgentHealthResponse {
        AgentHealthResponse(
            type: .agentHealthResponse,
            requestId: "req_health",
            protocolVersion: 1,
            agentVersion: "0.1.0",
            os: "windows-arm64",
            session: AgentSession(interactive: true, user: "veil-user"),
            capabilities: AgentCapabilities(
                appList: true,
                appLaunch: true,
                windowTracking: true,
                windowCapture: true,
                input: true,
                clipboardText: false
            )
        )
    }

    static var clipboardReady: AgentHealthResponse {
        AgentHealthResponse(
            type: .agentHealthResponse,
            requestId: "req_health",
            protocolVersion: 1,
            agentVersion: "0.1.0",
            os: "windows-arm64",
            session: AgentSession(interactive: true, user: "veil-user"),
            capabilities: AgentCapabilities(
                appList: true,
                appLaunch: true,
                windowTracking: true,
                windowCapture: true,
                input: true,
                clipboardText: true
            )
        )
    }

    static var clipboardReadyWithSparsePackageStatus: AgentHealthResponse {
        var response = clipboardReady
        response.packageIdentityStatus = PackageIdentityStatus(
            statusPath: #"C:\Users\veil\AppData\Local\Veil\Agent\package\sparse-package-status.json"#,
            stage: "packageSigned",
            succeeded: false,
            message: "SignTool signed the sparse identity package.",
            updatedAt: "2026-07-10T05:40:00.0000000+09:00",
            packagePath: #"C:\Users\veil\AppData\Local\Veil\Agent\package\VeilAgent.Identity.msix"#,
            certificatePath: #"C:\Users\veil\AppData\Local\Veil\Agent\package\VeilAgent.Identity.cer"#
        )
        return response
    }

    static var dailyUseReady: AgentHealthResponse {
        var response = clipboardReadyWithSparsePackageStatus
        response.capabilities.packageIdentity = true
        response.packageIdentityStatus?.stage = "registered"
        response.packageIdentityStatus?.succeeded = true
        response.packageIdentityStatus?.message = "Sparse package registered and agent restarted with package identity."
        return response
    }

    static var packageIdentityWithoutWindowCapture: AgentHealthResponse {
        var response = dailyUseReady
        response.capabilities.windowCapture = false
        return response
    }
}

private extension WindowsApp {
    static var notepad: WindowsApp {
        WindowsApp(
            id: "winapp_notepad",
            name: "Notepad",
            exePath: "C:\\Windows\\System32\\notepad.exe",
            publisher: "Microsoft",
            iconId: "icon_notepad",
            iconPngBase64: "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mNk+A8AAQUBAScY42YAAAAASUVORK5CYII="
        )
    }

    static var calculator: WindowsApp {
        WindowsApp(
            id: "winapp_calculator",
            name: "Calculator",
            exePath: "C:\\Windows\\System32\\calc.exe",
            publisher: "Microsoft",
            iconId: "icon_calculator"
        )
    }

    static var paint: WindowsApp {
        WindowsApp(
            id: "winapp_paint",
            name: "Paint",
            exePath: "C:\\Windows\\System32\\mspaint.exe",
            publisher: "Microsoft",
            iconId: "icon_paint"
        )
    }
}

private extension AppLaunchResponse {
    static var fixture: AppLaunchResponse {
        AppLaunchResponse(
            type: .appLaunchResponse,
            requestId: "req_launch_notepad",
            accepted: true,
            processId: 4912
        )
    }
}

private extension WindowCreatedEvent {
    static func fixture(appId: String) -> WindowCreatedEvent {
        if appId == "winapp_calculator" {
            return WindowCreatedEvent(
                type: .windowCreated,
                windowId: "hwnd:0003030B",
                processId: 4912,
                appId: "winapp_calculator",
                title: "Calculator",
                bounds: WindowBounds(x: 10, y: 10, width: 520, height: 720),
                state: "normal",
                focused: true
            )
        }

        return .notepad
    }

    static var notepad: WindowCreatedEvent {
        WindowCreatedEvent(
            type: .windowCreated,
            windowId: "hwnd:0003029A",
            processId: 4912,
            appId: "winapp_notepad",
            title: "Untitled - Notepad",
            bounds: WindowBounds(x: 10, y: 10, width: 1280, height: 800),
            state: "normal",
            focused: true
        )
    }

    static var secondNotepad: WindowCreatedEvent {
        WindowCreatedEvent(
            type: .windowCreated,
            windowId: "hwnd:00010500",
            processId: 4931,
            appId: "winapp_notepad",
            title: "Notes.txt - Notepad",
            bounds: WindowBounds(x: 20, y: 20, width: 1360, height: 820),
            state: "normal",
            focused: true
        )
    }

    static var paintCreatedJSON: String {
        #"{"type":"window.created","windowId":"hwnd:0005029C","processId":4948,"appId":"winapp_paint","title":"Untitled - Paint","bounds":{"x":40,"y":40,"width":1280,"height":800},"state":"normal","focused":true}"#
    }

    static var secondNotepadCreatedJSON: String {
        #"{"type":"window.created","windowId":"hwnd:00010500","processId":4931,"appId":"winapp_notepad","title":"Notes.txt - Notepad","bounds":{"x":20,"y":20,"width":1360,"height":820},"state":"normal","focused":true}"#
    }
}

private extension WindowFrameEvent {
    static var notepadFirstFrameJSON: String {
        #"{"type":"window.frame","windowId":"hwnd:0003029A","frameId":"frame_000001","sequence":1,"format":"png","width":1,"height":1,"scale":1,"encodedData":"iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+/p9sAAAAASUVORK5CYII="}"#
    }

    static var notepadFirstFrame: WindowFrameEvent {
        WindowFrameEvent(
            type: .windowFrame,
            windowId: "hwnd:0003029A",
            frameId: "frame_000001",
            sequence: 1,
            format: "png",
            width: 1,
            height: 1,
            scale: 1,
            encodedData: "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+/p9sAAAAASUVORK5CYII="
        )
    }

    static var notepadSecondFrame: WindowFrameEvent {
        WindowFrameEvent(
            type: .windowFrame,
            windowId: "hwnd:0003029A",
            frameId: "frame_000002",
            sequence: 2,
            format: "png",
            width: 1,
            height: 1,
            scale: 1,
            encodedData: "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+/p9sAAAAASUVORK5CYII="
        )
    }

    static var orphanFrame: WindowFrameEvent {
        WindowFrameEvent(
            type: .windowFrame,
            windowId: "hwnd:DEADBEEF",
            frameId: "frame_orphan",
            sequence: 1,
            format: "png",
            width: 1,
            height: 1,
            scale: 1,
            encodedData: "iVBORw0KGgo="
        )
    }
}

private extension WindowClosedEvent {
    static var notepadClosedJSON: String {
        #"{"type":"window.closed","windowId":"hwnd:0003029A"}"#
    }
}

private extension WindowUpdatedEvent {
    static var notepadUpdatedJSON: String {
        #"{"type":"window.updated","windowId":"hwnd:0003029A","processId":4912,"appId":"winapp_notepad","title":"Notes.txt - Notepad","bounds":{"x":20,"y":24,"width":1360,"height":860},"state":"normal","focused":true}"#
    }
}

private extension ClipboardTextSet {
    static var guestEventJSON: String {
        #"{"type":"clipboard.text.set","requestId":"evt_clipboard_43","origin":"guest","sequence":43,"text":"hello from Windows"}"#
    }
}
