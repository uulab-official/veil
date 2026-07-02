import Foundation
import Observation

public protocol HostDashboardService: Sendable {
    func loadOverview() async throws -> HostOverview
    func launchNotepad() async throws -> NotepadLaunchResult
    func closeWindow(windowId: String) async throws -> WindowCloseResponse
    func sendMouseInput(_ input: InputMouseEvent) async throws
    func sendKeyInput(_ input: InputKeyEvent) async throws
    func sendClipboardText(_ clipboard: ClipboardTextSet) async throws
    func subscribeWindowFrames(windowId: String) async throws
    func unsubscribeWindowFrames(windowId: String) async throws
}

public struct HostOverview: Codable, Equatable, Sendable {
    public var health: AgentHealthResponse
    public var apps: [WindowsApp]
    public var connectionMode: HostConnectionMode
    public var connectionDetail: String?

    public init(
        health: AgentHealthResponse,
        apps: [WindowsApp],
        connectionMode: HostConnectionMode = .agent,
        connectionDetail: String? = nil
    ) {
        self.health = health
        self.apps = apps
        self.connectionMode = connectionMode
        self.connectionDetail = connectionDetail
    }
}

public enum HostConnectionMode: String, Codable, Equatable, Sendable {
    case agent
    case demo
}

public enum WindowCaptureState: String, Codable, Equatable, Sendable {
    case unavailable
    case pending
    case streaming
}

public struct WindowMirrorSession: Codable, Equatable, Identifiable, Sendable {
    public var id: String { window.windowId }
    public var window: WindowCreatedEvent
    public var connectionMode: HostConnectionMode
    public var captureState: WindowCaptureState
    public var latestFrame: WindowFrameEvent?

    public init(
        window: WindowCreatedEvent,
        connectionMode: HostConnectionMode,
        captureState: WindowCaptureState,
        latestFrame: WindowFrameEvent? = nil
    ) {
        self.window = window
        self.connectionMode = connectionMode
        self.captureState = captureState
        self.latestFrame = latestFrame
    }
}

public enum HostDashboardPhase: Equatable, Sendable {
    case idle
    case loading
    case connected
    case launching
    case failed
}

public enum HostProtocolMessageResult: Equatable, Sendable {
    case handledWindowFrame(windowId: String)
    case handledClipboardText(sequence: Int)
    case ignored
}

@MainActor
@Observable
public final class HostDashboardModel {
    public private(set) var phase: HostDashboardPhase = .idle
    public private(set) var health: AgentHealthResponse?
    public private(set) var apps: [WindowsApp] = []
    public private(set) var lastLaunch: NotepadLaunchResult?
    public private(set) var activeWindows: [WindowCreatedEvent] = []
    public private(set) var mirrorSessions: [WindowMirrorSession] = []
    public private(set) var errorMessage: String?
    public private(set) var connectionMode: HostConnectionMode = .agent
    public private(set) var connectionDetail: String?
    public private(set) var pendingLaunchAppId: String?
    public private(set) var clipboardSequence = 0
    public private(set) var latestGuestClipboardText: String?
    public private(set) var lastGuestClipboardSequence = 0
    public private(set) var restorableAppIds: [String] = []
    public var selectedAppId: String?

    private let service: any HostDashboardService
    private let restoreIntentStore: any WindowRestoreIntentStore

    public init(
        service: any HostDashboardService,
        restoreIntentStore: any WindowRestoreIntentStore = JSONWindowRestoreIntentStore()
    ) {
        self.service = service
        self.restoreIntentStore = restoreIntentStore
    }

    public var statusText: String {
        switch phase {
        case .idle:
            "Ready to connect"
        case .loading:
            "Connecting to Windows agent"
        case .connected:
            if let lastLaunch {
                connectionMode == .demo
                    ? "Demo launched \(lastLaunch.window.title)"
                    : "Launched \(lastLaunch.window.title)"
            } else if let health {
                connectionMode == .demo
                    ? "Demo mode: Windows agent unavailable"
                    : "Connected to Windows agent \(health.agentVersion)"
            } else {
                "Connected"
            }
        case .launching:
            "Launching Notepad"
        case .failed:
            errorMessage ?? "Connection failed"
        }
    }

    public var selectedApp: WindowsApp? {
        guard let selectedAppId else {
            return nil
        }

        return apps.first { $0.id == selectedAppId }
    }

    public var canLaunchSelectedApp: Bool {
        selectedApp?.id == "winapp_notepad"
            && hasLiveAgentConnection
            && phase != .loading
            && phase != .launching
    }

    public var canRequestSelectedAppLaunch: Bool {
        selectedApp?.id == "winapp_notepad" && phase != .loading && phase != .launching
    }

    public var hasLiveAgentConnection: Bool {
        phase == .connected && connectionMode == .agent && health != nil
    }

    public var guestAgentInstallEvidence: VMInstallEvidenceSummary? {
        guard hasLiveAgentConnection, let health else {
            return nil
        }

        return VMInstallEvidenceSummary(
            kind: .guestAgent,
            isInstalled: true,
            title: "Guest agent connected",
            detail: "Windows is running the Veil guest agent \(health.agentVersion) over the local runtime channel."
        )
    }

    public func load() async {
        phase = .loading
        errorMessage = nil

        do {
            let overview = try await service.loadOverview()
            health = overview.health
            apps = overview.apps
            connectionMode = overview.connectionMode
            connectionDetail = overview.connectionDetail
            selectDefaultAppIfNeeded()
            phase = .connected
        } catch {
            errorMessage = userMessage(for: error)
            phase = .failed
        }
    }

    public func refreshLiveAgentIfNeeded() async -> NotepadLaunchResult? {
        guard !hasLiveAgentConnection else {
            return nil
        }

        await load()

        if hasLiveAgentConnection,
           pendingLaunchAppId == "winapp_notepad" {
            pendingLaunchAppId = nil
            return await launchNotepad()
        }

        return nil
    }

    public func loadRestoreIntent() async {
        do {
            restorableAppIds = try await restoreIntentStore.load()?.appIds ?? []
        } catch {
            errorMessage = userMessage(for: error)
        }
    }

    public func restoreMirroredWindowsAfterReconnect() async -> [NotepadLaunchResult] {
        guard !restorableAppIds.isEmpty else {
            return []
        }

        if !hasLiveAgentConnection {
            await load()
        }

        guard hasLiveAgentConnection else {
            return []
        }

        var restored: [NotepadLaunchResult] = []
        for appId in restorableAppIds where appId == "winapp_notepad" {
            if let result = await launchNotepad() {
                restored.append(result)
            }
        }

        return restored
    }

    public func launchSelectedApp() async {
        guard selectedApp != nil else {
            errorMessage = "Select an app before launching."
            phase = .failed
            return
        }

        guard hasLiveAgentConnection else {
            pendingLaunchAppId = selectedAppId
            errorMessage = nil
            return
        }

        guard canLaunchSelectedApp else {
            errorMessage = userMessage(for: VeilHostError.unsupportedHarnessApp)
            phase = .failed
            return
        }

        _ = await launchNotepad()
    }

    @discardableResult
    public func launchNotepad() async -> NotepadLaunchResult? {
        phase = .launching
        errorMessage = nil

        do {
            let result = try await service.launchNotepad()
            health = result.health
            apps = result.apps
            connectionMode = result.connectionMode
            connectionDetail = result.connectionDetail
            selectedAppId = result.window.appId
            lastLaunch = result
            await rememberRestorableAppId(result.window.appId)
            storeActiveWindow(result.window)
            storeMirrorSession(
                window: result.window,
                connectionMode: result.connectionMode,
                supportsCapture: result.health.capabilities.windowCapture
            )
            if result.connectionMode == .agent,
               result.health.capabilities.windowCapture {
                try await service.subscribeWindowFrames(windowId: result.window.windowId)
            }
            phase = .connected
            return result
        } catch {
            errorMessage = userMessage(for: error)
            phase = .failed
            return nil
        }
    }

    public func receiveWindowFrame(_ frame: WindowFrameEvent) {
        guard let index = mirrorSessions.firstIndex(where: { $0.id == frame.windowId }) else {
            return
        }

        mirrorSessions[index].latestFrame = frame
        mirrorSessions[index].captureState = .streaming
    }

    @discardableResult
    public func closeMirrorSession(windowId: String) async -> WindowCloseResponse? {
        guard mirrorSessions.contains(where: { $0.id == windowId })
                || activeWindows.contains(where: { $0.windowId == windowId }) else {
            return nil
        }

        do {
            if let session = mirrorSessions.first(where: { $0.id == windowId }),
               session.captureState != .unavailable,
               hasLiveAgentConnection {
                try await service.unsubscribeWindowFrames(windowId: windowId)
            }
            let response = try await service.closeWindow(windowId: windowId)
            if response.accepted {
                await removeWindowState(windowId: windowId)
            }
            return response
        } catch {
            errorMessage = userMessage(for: error)
            phase = .failed
            return nil
        }
    }

    public func sendMouseInput(
        windowId: String,
        event: String,
        x: Int,
        y: Int,
        modifiers: [String] = []
    ) async {
        guard mirrorSessions.contains(where: { $0.id == windowId }),
              hasLiveAgentConnection,
              health?.capabilities.input == true else {
            return
        }

        do {
            try await service.sendMouseInput(
                InputMouseEvent(windowId: windowId, event: event, x: x, y: y, modifiers: modifiers)
            )
        } catch {
            errorMessage = userMessage(for: error)
            phase = .failed
        }
    }

    public func sendKeyInput(
        windowId: String,
        event: String,
        key: String,
        windowsVirtualKey: Int,
        modifiers: [String] = []
    ) async {
        guard mirrorSessions.contains(where: { $0.id == windowId }),
              hasLiveAgentConnection,
              health?.capabilities.input == true else {
            return
        }

        do {
            try await service.sendKeyInput(
                InputKeyEvent(
                    windowId: windowId,
                    event: event,
                    key: key,
                    windowsVirtualKey: windowsVirtualKey,
                    modifiers: modifiers
                )
            )
        } catch {
            errorMessage = userMessage(for: error)
            phase = .failed
        }
    }

    public func sendHostClipboardText(_ text: String) async {
        guard hasLiveAgentConnection,
              health?.capabilities.clipboardText == true else {
            return
        }

        let nextSequence = clipboardSequence + 1
        do {
            try await service.sendClipboardText(
                ClipboardTextSet(
                    requestId: "req_clipboard_\(nextSequence)",
                    origin: "host",
                    sequence: nextSequence,
                    text: text
                )
            )
            clipboardSequence = nextSequence
        } catch {
            errorMessage = userMessage(for: error)
            phase = .failed
        }
    }

    public func receiveClipboardText(_ clipboard: ClipboardTextSet) -> Bool {
        guard clipboard.origin == "guest",
              clipboard.sequence > lastGuestClipboardSequence else {
            return false
        }

        latestGuestClipboardText = clipboard.text
        lastGuestClipboardSequence = clipboard.sequence
        return true
    }

    public func receiveProtocolMessage(
        _ message: Data,
        decoder: JSONDecoder = .veilProtocol
    ) throws -> HostProtocolMessageResult {
        let envelope = try decoder.decode(ProtocolMessageEnvelope.self, from: message)

        switch envelope.type {
        case .windowFrame:
            let frame = try decoder.decode(WindowFrameEvent.self, from: message)
            receiveWindowFrame(frame)
            return mirrorSessions.contains(where: { $0.id == frame.windowId && $0.latestFrame == frame })
                ? .handledWindowFrame(windowId: frame.windowId)
                : .ignored
        case .clipboardTextSet:
            let clipboard = try decoder.decode(ClipboardTextSet.self, from: message)
            return receiveClipboardText(clipboard)
                ? .handledClipboardText(sequence: clipboard.sequence)
                : .ignored
        default:
            return .ignored
        }
    }

    public func consumeProtocolMessages(
        from source: any HostEventSource,
        onMessageHandled: @MainActor (HostProtocolMessageResult) -> Void = { _ in }
    ) async {
        do {
            for try await message in source.eventMessages() {
                let result = try receiveProtocolMessage(message)
                onMessageHandled(result)
            }
        } catch {
            return
        }
    }

    private func storeActiveWindow(_ window: WindowCreatedEvent) {
        if let index = activeWindows.firstIndex(where: { $0.windowId == window.windowId }) {
            activeWindows[index] = window
            return
        }

        activeWindows.append(window)
    }

    private func storeMirrorSession(
        window: WindowCreatedEvent,
        connectionMode: HostConnectionMode,
        supportsCapture: Bool
    ) {
        let captureState: WindowCaptureState = connectionMode == .agent && supportsCapture ? .pending : .unavailable
        let session = WindowMirrorSession(
            window: window,
            connectionMode: connectionMode,
            captureState: captureState
        )

        if let index = mirrorSessions.firstIndex(where: { $0.id == session.id }) {
            mirrorSessions[index] = session
            return
        }

        mirrorSessions.append(session)
    }

    private func removeWindowState(windowId: String) async {
        let removedAppIds = activeWindows
            .filter { $0.windowId == windowId }
            .map(\.appId)
        activeWindows.removeAll { $0.windowId == windowId }
        mirrorSessions.removeAll { $0.id == windowId }

        if lastLaunch?.window.windowId == windowId {
            lastLaunch = nil
        }

        for appId in removedAppIds {
            await forgetRestorableAppId(appId)
        }
    }

    private func rememberRestorableAppId(_ appId: String) async {
        if !restorableAppIds.contains(appId) {
            restorableAppIds.append(appId)
        }

        await persistRestoreIntent()
    }

    private func forgetRestorableAppId(_ appId: String) async {
        restorableAppIds.removeAll { $0 == appId }
        await persistRestoreIntent()
    }

    private func persistRestoreIntent() async {
        do {
            try await restoreIntentStore.save(WindowRestoreIntent(appIds: restorableAppIds))
        } catch {
            errorMessage = userMessage(for: error)
            return
        }
    }

    private func selectDefaultAppIfNeeded() {
        if let selectedAppId, apps.contains(where: { $0.id == selectedAppId }) {
            return
        }

        selectedAppId = apps.first?.id
    }

    private func userMessage(for error: any Error) -> String {
        if let localized = error as? LocalizedError,
           let description = localized.errorDescription {
            return description
        }

        return String(describing: error)
    }
}
