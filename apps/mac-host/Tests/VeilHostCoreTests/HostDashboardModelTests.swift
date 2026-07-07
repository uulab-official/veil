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
        let service = FakeDashboardService(health: .clipboardReady)
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
        #expect(report.mirrorSessions.map(\.canFocus) == [true])
        #expect(report.mirrorSessions.map(\.canClose) == [true])
        #expect(report.mirrorSessions.map(\.canSendInput) == [true])
        #expect(report.restorableAppIds == ["winapp_notepad"])
        #expect(report.dockIntegration.isEnabled)
        #expect(report.dockIntegration.openWindowCount == 1)
        #expect(report.dockIntegration.pendingLaunchCount == 0)
        #expect(report.dockIntegration.badgeLabel == "1")
        #expect(report.dockIntegration.canOpenMainWindow)
        #expect(report.dockIntegration.canBringWindowsAppsForward)
        #expect(report.dockIntegration.canLaunchSelectedApp)
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
        #expect(report.quietRuntime.isEnabled)
        #expect(report.quietRuntime.hasOpenedAppWindowThisSession)
        #expect(report.quietRuntime.openWindowCount == 1)
        #expect(report.quietRuntime.canQuietRuntime == false)
        #expect(report.quietRuntime.willQuietAutomatically == false)
        #expect(report.quietRuntime.automaticQuietDelaySeconds == 8)
        #expect(report.quietRuntime.recommendedAction == "keep-running")
        #expect(report.quietRuntime.recommendedStopCommand == nil)
        #expect(report.launchPlan.selectedAppId == "winapp_notepad")
        #expect(report.launchPlan.canRequestSelectedAppLaunch)
        #expect(report.launchPlan.canLaunchSelectedAppNow)
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
        #expect(report.actions.first { $0.id == "dock.openMainWindow" }?.isAvailable == true)
        #expect(report.actions.first { $0.id == "dock.bringWindowsAppsForward" }?.isAvailable == true)
        #expect(report.actions.first { $0.id == "clipboard.setText" }?.isAvailable == true)
        #expect(report.actions.first { $0.id == "windowsApps.restorePrevious" }?.isAvailable == false)
        #expect(report.actions.first { $0.id == "macWindows.autoOpen" }?.isAvailable == true)
        #expect(report.actions.first { $0.id == "runtime.startWindowsForApp" }?.isAvailable == false)
        #expect(report.actions.first { $0.id == "runtime.repairGuestAgentForApp" }?.isAvailable == false)
        #expect(report.actions.first { $0.id == "runtime.recoverDisplay" }?.isAvailable == false)
        #expect(report.actions.first { $0.id == "runtime.fulfillPendingLaunch" }?.isAvailable == false)
        #expect(report.actions.first { $0.id == "runtime.waitAgent" }?.isAvailable == false)
        #expect(report.actions.first { $0.id == "runtime.quietWhenIdle" }?.isAvailable == false)
        #expect(report.actions.first { $0.id == "runtime.stopWhenIdle" }?.isAvailable == false)
        #expect(report.actions.first { $0.id == "proof.appWindow" }?.isAvailable == true)
        #expect(report.actions.first { $0.id == "proof.coherence" }?.isAvailable == true)
        #expect(report.actions.first { $0.id == "proof.mvp" }?.isAvailable == true)
        #expect(report.actions.first { $0.id == "proof.recommended" }?.isAvailable == true)
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
        #expect(status.recommendedPrepareCommand == "veil-vmctl prepare --installer /Users/test/Downloads/Win11_25H2_Korean_Arm64_v2.iso --drivers '/Users/test/Downloads/virtio drivers.iso'")
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
                kind: .profileFlag,
                isInstalled: true,
                title: "Windows installed",
                detail: "The profile is marked installed."
            ),
            bootReady: true,
            windowsInstalled: true,
            detail: "Windows is running."
        )

        let status = model.localRuntimeStatus(snapshot: snapshot)

        #expect(status.isRunning)
        #expect(status.consolePreviewStatus == .stale)
        #expect(status.recommendedAction == "recover-runtime-display")
        #expect(status.recommendedDisplayCommand == "veil-vmctl qemu-display-smoke --json")
        #expect(status.recommendedRecoveryCommand == "veil-vmctl qemu-capture --json")
        #expect(status.reason.contains("embedded console preview is stale"))

        let report = model.runtimeStatusReport(localRuntime: status)
        #expect(report.actions.first { $0.id == "runtime.recoverDisplay" }?.isAvailable == true)
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
        #expect(queuedReport.pendingLaunch.reason == "Veil will launch the queued Windows app after the guest agent reconnects.")
        #expect(queuedReport.dockIntegration.openWindowCount == 0)
        #expect(queuedReport.dockIntegration.pendingLaunchCount == 1)
        #expect(queuedReport.dockIntegration.badgeLabel == "...")
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
        #expect(runningQueuedReport.launchPlan.recommendedStartCommand == nil)
        #expect(runningQueuedReport.launchPlan.recommendedWaitCommand == "veil-vmctl guest-agent-wait --json --wait-seconds 30")
        #expect(runningQueuedReport.launchPlan.recommendedRepairCommand == "veil-vmctl qemu-install-agent --json --wait-seconds 120")
        #expect(runningQueuedReport.launchPlan.recommendedLaunchCommand == "veil-vmctl app-runtime-action --json --action fulfill-pending")
        #expect(runningQueuedReport.launchPlan.reason == "Windows is running and the selected app launch is queued; repair or start the guest agent, then open the app automatically.")
        #expect(runningQueuedReport.actions.first { $0.id == "runtime.startWindowsForApp" }?.isAvailable == false)
        #expect(runningQueuedReport.actions.first { $0.id == "runtime.repairGuestAgentForApp" }?.isAvailable == true)
        #expect(runningQueuedReport.actions.first { $0.id == "runtime.fulfillPendingLaunch" }?.isAvailable == false)
        #expect(runningQueuedReport.actions.first { $0.id == "runtime.waitAgent" }?.isAvailable == true)

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

    @Test("loads persisted mapped app intent on startup")
    @MainActor
    func loadsPersistedMappedAppIntentOnStartup() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let intentStore = JSONWindowRestoreIntentStore(directory: directory)
        try await intentStore.save(WindowRestoreIntent(appIds: ["winapp_notepad"]))
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
        try await intentStore.save(WindowRestoreIntent(appIds: ["winapp_notepad"]))
        let primary = FakeDashboardService(health: .captureReady)
        primary.error = URLError(.cannotConnectToHost)
        let service = FallbackHostDashboardService(
            primary: primary,
            fallback: DemoHostDashboardService(),
            primaryEndpointDescription: "ws://127.0.0.1:18444"
        )
        let model = HostDashboardModel(service: service, restoreIntentStore: intentStore)

        await model.loadRestoreIntent()
        await model.load()
        let report = model.runtimeStatusReport()

        #expect(model.hasLiveAgentConnection == false)
        #expect(model.canRestoreMirrorSessions == false)
        #expect(model.canReconnectRestoreMirrorSessions)
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
        return WindowsAppLaunchResult(
            health: health,
            apps: apps,
            launch: .fixture,
            window: .fixture(appId: appId)
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

    static var paintCreatedJSON: String {
        #"{"type":"window.created","windowId":"hwnd:0005029C","processId":4948,"appId":"winapp_paint","title":"Untitled - Paint","bounds":{"x":40,"y":40,"width":1280,"height":800},"state":"normal","focused":true}"#
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
