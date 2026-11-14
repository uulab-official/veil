import Foundation
import Testing

@testable import VeilHostCore

struct GuestStateSyncProtocolTests {
    @Test func timeSyncFixturesDecode() throws {
        let request: TimeSyncRequest = try decodeStateSyncFixture("time.sync.request")
        let response: TimeSyncResponse = try decodeStateSyncFixture("time.sync.response")

        #expect(request.type == .timeSyncRequest)
        #expect(request.reason == .vmResume)
        #expect(response.timeSync.outcome == .corrected)
        #expect(response.timeSync.skewMilliseconds == 40_638_882)
    }

    @Test func appearanceFixturesDecode() throws {
        let request: AppearanceSetRequest = try decodeStateSyncFixture("appearance.set.request")
        let response: AppearanceSetResponse = try decodeStateSyncFixture("appearance.set.response")

        #expect(request.theme == .dark)
        #expect(response.appearance.appsUseLightTheme == false)
        #expect(response.appearance.broadcast)
    }

    @Test func timeSyncRepairFixturesDecode() throws {
        let request: TimeSyncRepairRequest = try decodeStateSyncFixture("time.sync.repair.request")
        let response: TimeSyncRepairResponse = try decodeStateSyncFixture("time.sync.repair.response")

        #expect(request.type == .timeSyncRepairRequest)
        #expect(response.repair.outcome == "approval-requested")
        #expect(response.repair.isSupported)
    }

    @Test func clientAsksForTheClockRepairAndReadsTheAnswer() async throws {
        let transport = StateSyncTransport(replies: [
            #"{"type":"time.sync.repair.response","requestId":"req_time_sync_repair","protocolVersion":1,"repair":{"isSupported":true,"outcome":"already-running","message":"Windows is already asking for approval."}}"#
        ])
        let client = VeilHostClient(transport: transport)

        let response = try await client.repairGuestTimeSync()

        #expect(response.repair.outcome == "already-running")
    }

    @Test func visualEffectsFixturesDecode() throws {
        let request: VisualEffectsSetRequest = try decodeStateSyncFixture("visual.effects.set.request")
        let response: VisualEffectsSetResponse = try decodeStateSyncFixture("visual.effects.set.response")

        #expect(request.type == .visualEffectsSetRequest)
        #expect(request.reduced)
        #expect(response.visualEffects.transparency == false)
        #expect(response.visualEffects.changed)
        #expect(try JSONEncoder.veilProtocol.encode(request).count > 0)
    }

    @Test func encodedTimeSyncRequestMatchesTheShapeTheGuestAccepts() throws {
        let date = Date(timeIntervalSince1970: 1_794_389_400) // 2026-11-11T09:30:00Z
        let data = try JSONEncoder.veilProtocol.encode(
            TimeSyncRequest(requestId: "req_time_sync", hostUtc: date, reason: .vmResume)
        )
        let object = try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
        let fixtureURL = try #require(Bundle.module.url(forResource: "time.sync.request", withExtension: "json"))
        let fixture = try #require(
            try JSONSerialization.jsonObject(with: Data(contentsOf: fixtureURL)) as? [String: Any]
        )

        #expect(Set(object.keys) == Set(fixture.keys))
        #expect(object["type"] as? String == "time.sync.request")
        #expect(object["hostUtc"] as? String == "2026-11-11T09:30:00.000Z")
        #expect(object["reason"] as? String == "vm-resume")
    }

    @Test func clientSurfacesGuestErrorReplies() async throws {
        let transport = StateSyncTransport(replies: [
            #"{"type":"error","requestId":"req_appearance_set","code":"appearance_set_failed","message":"denied"}"#
        ])
        let client = VeilHostClient(transport: transport)

        await #expect(throws: VeilHostError.agentError(code: "appearance_set_failed", message: "denied")) {
            _ = try await client.setGuestAppearance(theme: .dark)
        }
        #expect(transport.sentTypes == ["appearance.set.request"])
    }

    @Test func clientDecodesTimeSyncResponse() async throws {
        let fixtureURL = try #require(Bundle.module.url(forResource: "time.sync.response", withExtension: "json"))
        let fixture = try String(contentsOf: fixtureURL, encoding: .utf8)
        let transport = StateSyncTransport(replies: [fixture])
        let client = VeilHostClient(transport: transport)

        let response = try await client.syncGuestTime(hostUtc: Date(), reason: .macWake)

        #expect(response.timeSync.method == "set-system-time")
        #expect(transport.sentTypes == ["time.sync.request"])
    }

    @Test func matchMacAppearanceDefaultsToOn() throws {
        let defaults = try #require(UserDefaults(suiteName: "veil.tests.guestStateSync.\(UUID().uuidString)"))
        #expect(GuestStateSyncSettings.matchMacAppearance(in: defaults))

        defaults.set(false, forKey: GuestStateSyncSettings.matchMacAppearanceKey)
        #expect(!GuestStateSyncSettings.matchMacAppearance(in: defaults))
    }
}

@MainActor
struct GuestStateSyncCoordinatorTests {
    private static var effectsCapabilities: AgentCapabilities {
        var capabilities = syncCapabilities
        capabilities.visualEffects = true
        return capabilities
    }

    @Test func visualEffectsAreSentOncePerConnectionAndWhenTheSettingChanges() async {
        let service = StateSyncRecordingService()
        let coordinator = GuestStateSyncCoordinator()
        func flush(live: Bool = true, reduced: Bool?) async {
            await coordinator.flush(
                service: service,
                isLive: live,
                capabilities: Self.effectsCapabilities,
                macTheme: .dark,
                matchMacAppearance: true,
                reduceVisualEffects: reduced
            )
        }

        await flush(reduced: true)
        await flush(reduced: true)
        #expect(service.visualEffects == [true])
        #expect(coordinator.confirmedReducedEffects == true)

        // Turned off: sent as well, which is what puts back what the user had in Windows.
        await flush(reduced: false)
        #expect(service.visualEffects == [true, false])

        // A new connection may be a new agent, or Windows after a restart.
        await flush(live: false, reduced: false)
        await flush(reduced: false)
        #expect(service.visualEffects == [true, false, false])
    }

    @Test func visualEffectsAreNotAskedOfAnAgentThatCannotSetThem() async {
        let service = StateSyncRecordingService()
        let coordinator = GuestStateSyncCoordinator()

        await coordinator.flush(
            service: service,
            isLive: true,
            capabilities: Self.syncCapabilities,
            macTheme: .dark,
            matchMacAppearance: true,
            reduceVisualEffects: true
        )
        // A caller that leaves the setting out sends nothing either.
        await coordinator.flush(
            service: service,
            isLive: true,
            capabilities: Self.effectsCapabilities,
            macTheme: .dark,
            matchMacAppearance: true
        )

        #expect(service.visualEffects.isEmpty)
    }

    @Test func aFailingVisualEffectsRequestIsRetriedOnlyAFewTimes() async {
        let service = StateSyncRecordingService(failing: true)
        let coordinator = GuestStateSyncCoordinator()

        for _ in 0..<6 {
            await coordinator.flush(
                service: service,
                isLive: true,
                capabilities: Self.effectsCapabilities,
                macTheme: .dark,
                matchMacAppearance: false,
                reduceVisualEffects: true
            )
        }

        #expect(service.visualEffects.count == GuestStateSyncCoordinator.maximumAttemptsPerTrigger)
        #expect(coordinator.confirmedReducedEffects == nil)
    }

    private static let syncCapabilities = AgentCapabilities(
        appList: true,
        appLaunch: true,
        windowTracking: true,
        windowCapture: true,
        input: true,
        clipboardText: true,
        timeSync: true,
        appearanceSync: true
    )

    private static let olderAgentCapabilities = AgentCapabilities(
        appList: true,
        appLaunch: true,
        windowTracking: true,
        windowCapture: true,
        input: true,
        clipboardText: true
    )

    @Test func firstLiveConnectionSyncsClockAndAppearance() async {
        let service = StateSyncRecordingService()
        let coordinator = GuestStateSyncCoordinator()

        await coordinator.flush(service: service, isLive: true, capabilities: Self.syncCapabilities, macTheme: .dark, matchMacAppearance: true)

        #expect(service.timeSyncReasons == [.agentConnected])
        #expect(service.themes == [.dark])
        #expect(coordinator.confirmedTheme == .dark)
        #expect(coordinator.lastTimeSync?.outcome == .inSync)
    }

    @Test func repeatedFlushesDoNotResendAnything() async {
        let service = StateSyncRecordingService()
        let coordinator = GuestStateSyncCoordinator()

        for _ in 0..<3 {
            await coordinator.flush(service: service, isLive: true, capabilities: Self.syncCapabilities, macTheme: .light, matchMacAppearance: true)
        }

        #expect(service.timeSyncReasons.count == 1)
        #expect(service.themes == [.light])
    }

    @Test func wakeWhileDisconnectedIsSentOnceTheAgentReconnects() async {
        let service = StateSyncRecordingService()
        let coordinator = GuestStateSyncCoordinator()
        await coordinator.flush(service: service, isLive: true, capabilities: Self.syncCapabilities, macTheme: .light, matchMacAppearance: true)

        coordinator.requestTimeSync(.macWake)
        await coordinator.flush(service: service, isLive: false, capabilities: Self.syncCapabilities, macTheme: .light, matchMacAppearance: true)
        #expect(service.timeSyncReasons == [.agentConnected])

        await coordinator.flush(service: service, isLive: true, capabilities: Self.syncCapabilities, macTheme: .light, matchMacAppearance: true)

        // The wake reason survives the reconnect rather than being replaced by agent-connected.
        #expect(service.timeSyncReasons == [.agentConnected, .macWake])
        // A reconnect may be a different agent process, so the theme is told again.
        #expect(service.themes == [.light, .light])
    }

    @Test func resumeRequestIsSentWithItsReason() async {
        let service = StateSyncRecordingService()
        let coordinator = GuestStateSyncCoordinator()
        await coordinator.flush(service: service, isLive: true, capabilities: Self.syncCapabilities, macTheme: .light, matchMacAppearance: true)

        coordinator.requestTimeSync(.vmResume)
        await coordinator.flush(service: service, isLive: true, capabilities: Self.syncCapabilities, macTheme: .light, matchMacAppearance: true)

        #expect(service.timeSyncReasons == [.agentConnected, .vmResume])
    }

    @Test func appearanceChangeIsSentAndDisabledSettingSendsNothing() async {
        let service = StateSyncRecordingService()
        let coordinator = GuestStateSyncCoordinator()
        await coordinator.flush(service: service, isLive: true, capabilities: Self.syncCapabilities, macTheme: .light, matchMacAppearance: true)
        await coordinator.flush(service: service, isLive: true, capabilities: Self.syncCapabilities, macTheme: .dark, matchMacAppearance: true)
        #expect(service.themes == [.light, .dark])

        await coordinator.flush(service: service, isLive: true, capabilities: Self.syncCapabilities, macTheme: .light, matchMacAppearance: false)
        #expect(service.themes == [.light, .dark])

        // Turning the setting back on resends the current Mac appearance.
        coordinator.invalidateAppearance()
        await coordinator.flush(service: service, isLive: true, capabilities: Self.syncCapabilities, macTheme: .light, matchMacAppearance: true)
        #expect(service.themes == [.light, .dark, .light])
    }

    @Test func olderAgentIsNeverSentMessagesItCannotRoute() async {
        let service = StateSyncRecordingService()
        let coordinator = GuestStateSyncCoordinator()

        await coordinator.flush(service: service, isLive: true, capabilities: Self.olderAgentCapabilities, macTheme: .dark, matchMacAppearance: true)
        coordinator.requestTimeSync(.macWake)
        await coordinator.flush(service: service, isLive: true, capabilities: Self.olderAgentCapabilities, macTheme: .dark, matchMacAppearance: true)

        #expect(service.timeSyncReasons.isEmpty)
        #expect(service.themes.isEmpty)
        #expect(coordinator.pendingTimeSyncReason == nil)
    }

    @Test func failingGuestIsRetriedOnlyWithinTheBudget() async {
        let service = StateSyncRecordingService(failing: true)
        let coordinator = GuestStateSyncCoordinator()

        for _ in 0..<(GuestStateSyncCoordinator.maximumAttemptsPerTrigger + 3) {
            await coordinator.flush(service: service, isLive: true, capabilities: Self.syncCapabilities, macTheme: .dark, matchMacAppearance: true)
        }

        #expect(service.timeSyncReasons.count == GuestStateSyncCoordinator.maximumAttemptsPerTrigger)
        #expect(service.themes.count == GuestStateSyncCoordinator.maximumAttemptsPerTrigger)
        #expect(coordinator.lastErrorMessage != nil)
        #expect(coordinator.confirmedTheme == nil)

        // A fresh trigger gets a fresh budget.
        coordinator.requestTimeSync(.macWake)
        await coordinator.flush(service: service, isLive: true, capabilities: Self.syncCapabilities, macTheme: .dark, matchMacAppearance: true)
        #expect(service.timeSyncReasons.count == GuestStateSyncCoordinator.maximumAttemptsPerTrigger + 1)
    }

    @Test func hostClockIsSampledAtSendTime() async {
        let service = StateSyncRecordingService()
        let sendTime = Date(timeIntervalSince1970: 1_794_389_400)
        let coordinator = GuestStateSyncCoordinator(now: { sendTime })

        await coordinator.flush(service: service, isLive: true, capabilities: Self.syncCapabilities, macTheme: .dark, matchMacAppearance: false)

        #expect(service.hostTimes == [sendTime])
    }
}

private final class StateSyncTransport: HostTransport, @unchecked Sendable {
    private var replies: [String]
    private(set) var sentTypes: [String] = []

    init(replies: [String]) {
        self.replies = replies
    }

    func send(_ message: Data, expectedReplies: Int) async throws -> [Data] {
        let object = try JSONSerialization.jsonObject(with: message) as? [String: Any]
        sentTypes.append(object?["type"] as? String ?? "")
        let batch = Array(replies.prefix(expectedReplies))
        replies.removeFirst(batch.count)
        return batch.map { Data($0.utf8) }
    }
}

private struct StateSyncTestError: Error {}

private final class StateSyncRecordingService: HostDashboardService, @unchecked Sendable {
    private let failing: Bool
    private(set) var timeSyncReasons: [GuestTimeSyncReason] = []
    private(set) var hostTimes: [Date] = []
    private(set) var themes: [GuestAppearanceTheme] = []

    init(failing: Bool = false) {
        self.failing = failing
    }

    func syncGuestTime(hostUtc: Date, reason: GuestTimeSyncReason) async throws -> TimeSyncResponse {
        timeSyncReasons.append(reason)
        hostTimes.append(hostUtc)
        if failing {
            throw StateSyncTestError()
        }
        return TimeSyncResponse(
            requestId: "req_time_sync",
            timeSync: GuestTimeSyncStatus(
                isSupported: true,
                guestUtcBefore: TimeSyncRequest.format(hostUtc),
                skewMilliseconds: 0,
                outcome: .inSync,
                method: "none"
            )
        )
    }

    private(set) var visualEffects: [Bool] = []
    private(set) var repairs = 0
    var timeSyncAction = "none"

    func repairGuestTimeSync() async throws -> TimeSyncRepairResponse {
        repairs += 1
        if failing {
            throw StateSyncTestError()
        }
        return TimeSyncRepairResponse(
            requestId: "req_time_sync_repair",
            repair: GuestTimeSyncRepairStatus(isSupported: true, outcome: "approval-requested")
        )
    }

    func setGuestVisualEffects(reduced: Bool) async throws -> VisualEffectsSetResponse {
        visualEffects.append(reduced)
        if failing {
            throw StateSyncTestError()
        }
        return VisualEffectsSetResponse(
            requestId: "req_visual_effects_set",
            visualEffects: GuestVisualEffectsStatus(
                isSupported: true,
                reduced: reduced,
                transparency: !reduced,
                windowAnimation: !reduced,
                clientAnimation: !reduced,
                changed: true
            )
        )
    }

    func setGuestAppearance(theme: GuestAppearanceTheme) async throws -> AppearanceSetResponse {
        themes.append(theme)
        if failing {
            throw StateSyncTestError()
        }
        let light = theme == .light
        return AppearanceSetResponse(
            requestId: "req_appearance_set",
            appearance: GuestAppearanceStatus(
                isSupported: true,
                theme: theme,
                appsUseLightTheme: light,
                systemUsesLightTheme: light,
                changed: true,
                broadcast: true
            )
        )
    }

    func loadOverview() async throws -> HostOverview { throw StateSyncTestError() }
    func launchApp(appId: String) async throws -> WindowsAppLaunchResult { throw StateSyncTestError() }
    func launchNotepad() async throws -> NotepadLaunchResult { throw StateSyncTestError() }
    func openFile(appId: String, fileName: String, contentBase64: String) async throws -> WindowsAppLaunchResult { throw StateSyncTestError() }
    func focusWindow(windowId: String) async throws -> WindowFocusResponse { throw StateSyncTestError() }
    func closeWindow(windowId: String) async throws -> WindowCloseResponse { throw StateSyncTestError() }
    func openSharedFile(appId: String, fileName: String, guestPath: String) async throws -> WindowsAppLaunchResult { throw StateSyncTestError() }
    func resizeDisplay(width: Int, height: Int) async throws -> DisplayResizeResponse { throw StateSyncTestError() }
    func setDisplayScale(scalePercent: Int?) async throws -> DisplayScaleResponse { throw StateSyncTestError() }
    func requestSystemShutdown() async throws -> SystemShutdownResponse { throw StateSyncTestError() }
    func setCroppedWindows(windowIds: [String], hidesDesktop: Bool) async throws {}
    func moveWindow(windowId: String, x: Int, y: Int) async throws {}
    func sendMouseInput(_ input: InputMouseEvent) async throws {}
    func sendKeyInput(_ input: InputKeyEvent) async throws {}
    func sendClipboardText(_ clipboard: ClipboardTextSet) async throws {}
    func subscribeWindowFrames(windowId: String) async throws {}
    func unsubscribeWindowFrames(windowId: String) async throws {}
    func waitForAgentConnection(endpoint: String, timeoutSeconds: Int) async -> AgentConnectionWaitReport {
        fatalError("not used by guest state sync tests")
    }
}

private func decodeStateSyncFixture<T: Decodable>(_ name: String) throws -> T {
    let url = try #require(Bundle.module.url(forResource: name, withExtension: "json"))
    return try JSONDecoder.veilProtocol.decode(T.self, from: Data(contentsOf: url))
}
