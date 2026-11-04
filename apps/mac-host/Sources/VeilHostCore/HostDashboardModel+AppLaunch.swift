import CoreGraphics
import Foundation
import Observation

extension HostDashboardModel {
    public func load() async {
        phase = .loading
        errorMessage = nil

        do {
            let overview = try await service.loadOverview()
            health = overview.health
            apps = overview.apps
            connectionMode = overview.connectionMode
            connectionDetail = overview.connectionDetail
            agentDiagnostic = overview.agentDiagnostic
            selectDefaultAppIfNeeded()
            phase = .connected
        } catch {
            errorMessage = userMessage(for: error)
            if let serviceError = error as? HostDashboardServiceError,
               case .agentEndpointUnavailable(let endpoint, let detail, let nextActions) = serviceError {
                agentDiagnostic = AgentConnectionDiagnostic(
                    status: .unavailable,
                    endpoint: endpoint,
                    errorMessage: detail,
                    nextActions: nextActions
                )
            } else {
                agentDiagnostic = AgentConnectionDiagnostic.unavailable(
                    endpoint: "configured Windows agent",
                    errorMessage: userMessage(for: error)
                )
            }
            phase = .failed
        }
    }

    public func refreshLiveAgentIfNeeded() async -> NotepadLaunchResult? {
        if hasLiveAgentConnection,
           canFulfillPendingLaunch {
            return await fulfillPendingLaunch()
        }

        if hasLiveAgentConnection {
            return nil
        }

        await load()

        if hasLiveAgentConnection,
           canFulfillPendingLaunch {
            return await fulfillPendingLaunch()
        }

        return nil
    }

    @discardableResult
    public func waitForLiveAgentConnection(
        endpoint: String = HostDashboardModel.defaultAgentEndpoint,
        timeoutSeconds: Int = 5
    ) async -> AgentConnectionWaitReport {
        phase = .loading
        errorMessage = nil

        let report = await service.waitForAgentConnection(
            endpoint: endpoint,
            timeoutSeconds: timeoutSeconds
        )
        latestAgentWait = report
        agentDiagnostic = report.diagnostic

        if report.status == .connected {
            await load()
        } else {
            phase = .failed
            errorMessage = report.diagnostic.errorMessage
        }

        return report
    }

    @discardableResult
    public func fulfillPendingLaunch() async -> WindowsAppLaunchResult? {
        guard canFulfillPendingLaunch,
              let pendingLaunchAppId else {
            return nil
        }

        return await launchApp(appId: pendingLaunchAppId)
    }

    public func loadRestoreIntent() async {
        do {
            let restoreIntent = try await restoreIntentStore.load()
            restorableAppIds = restoreIntent?.appIds ?? []
            restorableAppWindowCounts = restoreIntent?.normalizedAppWindowCounts ?? [:]
            if let restoreIntent,
               restoreIntent.appWindowCounts != restorableAppWindowCounts {
                try await restoreIntentStore.save(
                    WindowRestoreIntent(
                        appIds: restorableAppIds,
                        appWindowCounts: restorableAppWindowCounts
                    )
                )
            }
            pendingLaunchAppId = try await pendingLaunchIntentStore.load()?.appId
        } catch {
            errorMessage = userMessage(for: error)
        }
    }

    public func restoreMirroredWindowsAfterReconnect() async -> [NotepadLaunchResult] {
        // Cleared unconditionally, including on the early-return paths below, so a stale
        // errorMessage from some earlier unrelated failure can never be mistaken by a caller for a
        // failure of *this* call (callers like VeilHostShellApp.restoreWindowsAppWindows() read
        // errorMessage after an empty result to distinguish "nothing to restore" from "restore
        // failed").
        errorMessage = nil

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
        for appId in restorableAppIdsForLaunches() {
            if let result = await launchApp(appId: appId, preferExistingWindow: true) {
                restored.append(result)
            }
        }

        return restored
    }

    @discardableResult
    public func launchSelectedApp() async -> WindowsAppLaunchResult? {
        guard selectedApp != nil else {
            errorMessage = "Select an app before launching."
            phase = .failed
            return nil
        }

        guard hasLiveAgentConnection else {
            await queuePendingLaunchIntent(appId: selectedAppId)
            errorMessage = nil
            return nil
        }

        guard let selectedAppId, canLaunchSelectedApp else {
            errorMessage = "The selected Windows app is not available."
            phase = .failed
            return nil
        }

        return await launchApp(appId: selectedAppId)
    }

    @discardableResult
    public func launchNotepad() async -> NotepadLaunchResult? {
        await launchApp(appId: "winapp_notepad")
    }

    @discardableResult
    public func launchApp(
        appId: String,
        preferExistingWindow: Bool = false
    ) async -> WindowsAppLaunchResult? {
        if let task = appLaunchTasks[appId] {
            return await task.value
        }

        let task = Task<WindowsAppLaunchResult?, Never> { @MainActor [weak self] in
            guard let self else {
                return nil
            }
            return await self.performAppLaunch(
                appId: appId,
                preferExistingWindow: preferExistingWindow
            )
        }
        appLaunchTasks[appId] = task
        let result = await task.value
        appLaunchTasks[appId] = nil
        return result
    }

    private func performAppLaunch(
        appId: String,
        preferExistingWindow: Bool
    ) async -> WindowsAppLaunchResult? {
        phase = .launching
        errorMessage = nil
        let shouldReuseExistingWindow = preferExistingWindow
            || mirrorSessions.contains(where: { $0.window.appId == appId })
            || activeWindows.contains(where: { $0.appId == appId })

        do {
            let result = try await (shouldReuseExistingWindow
                ? service.restoreApp(appId: appId)
                : service.launchApp(appId: appId))
            return try await applyWindowsAppLaunchResult(result)
        } catch {
            errorMessage = userMessage(for: error)
            phase = .failed
            return nil
        }
    }

    /// Opens a host file in the given app on the Windows guest -- the drag-and-drop entry point.
    /// Applies the exact same side effects as `launchApp` since the wire response has the same
    /// launch-acceptance-plus-`window.created` shape; the only difference is what triggered it.
    /// Records a drag-and-drop refusal decided on the host.
    ///
    /// Refusals happen before the guest is contacted, so they never pass through ``openFile``'s error path.
    /// That is what made them silent: macOS plays its accept animation the moment the drop is taken, so a
    /// file refused a few milliseconds later looked exactly like a file that opened and did nothing.
    ///
    /// This is the record, not the message. The app shell shows the refusal as a sheet on the window the
    /// file was dropped onto, because that is where the gesture happened.
    ///
    /// Deliberately does **not** set ``errorMessage`` or move ``phase`` to `.failed`. Nothing about the
    /// Windows runtime broke — one file was not accepted and the app is still running. `errorMessage` is
    /// rendered as an "Agent Unavailable" panel in the Agent tab, so putting a drop refusal there would
    /// report the wrong problem in the wrong place.
    public func recordFileDropRefusal(_ refusal: WindowsAppFileDropRefusal) {
        lastFileDropRefusal = refusal
    }

    @discardableResult
    public func openFile(appId: String, fileName: String, contentBase64: String) async -> WindowsAppLaunchResult? {
        // Restored on failure. A drop that Windows refuses must not leave the launcher parked in
        // `.launching` forever, and must not claim `.failed` either — see the catch below.
        let phaseBeforeOpen = phase
        phase = .launching
        errorMessage = nil
        // A drop that got this far passed every host-side check, so the previous refusal is history and must
        // not keep showing up as the current state of drag-and-drop.
        lastFileDropRefusal = nil

        do {
            let result = try await service.openFile(appId: appId, fileName: fileName, contentBase64: contentBase64)
            return try await applyWindowsAppLaunchResult(result)
        } catch {
            // Recorded as a drop refusal, not a runtime failure. The guest returns structured reasons here
            // (`invalid_file_name`, `file_too_large`, `file_write_failed`, `file_open_failed`, ...), and the
            // previous code turned every one of them into `phase = .failed` plus a message in
            // `errorMessage`. That claimed the whole Windows runtime broke because one file did not open,
            // and `errorMessage` has no display surface in the one-screen launcher, so the explanation was
            // lost as well. The app the user dropped onto is still running.
            lastFileDropRefusal = .guestRejected(fileName: fileName, detail: userMessage(for: error))
            phase = phaseBeforeOpen
            return nil
        }
    }

    private func applyWindowsAppLaunchResult(_ result: WindowsAppLaunchResult) async throws -> WindowsAppLaunchResult {
        health = result.health
        apps = result.apps
        connectionMode = result.connectionMode
        connectionDetail = result.connectionDetail
        agentDiagnostic = result.connectionMode == .agent
            ? AgentConnectionDiagnostic.connected(endpoint: "configured Windows agent", health: result.health)
            : agentDiagnostic
        selectedAppId = result.window.appId
        lastLaunch = result
        if pendingLaunchAppId == result.window.appId {
            await clearPendingLaunchIntent()
        }
        storeActiveWindow(result.window)
        storeMirrorSession(
            window: result.window,
            connectionMode: result.connectionMode,
            supportsCapture: result.health.capabilities.windowCapture
        )
        await refreshRestoreIntentFromOpenWindows()
        if result.connectionMode == .agent,
           result.health.capabilities.windowCapture {
            try await service.subscribeWindowFrames(windowId: result.window.windowId)
        }
        phase = .connected
        return result
    }
}
