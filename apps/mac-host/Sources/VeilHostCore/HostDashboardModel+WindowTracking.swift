import CoreGraphics
import Foundation
import Observation

extension HostDashboardModel {
    public func receiveProtocolMessage(
        _ message: Data,
        decoder: JSONDecoder = .veilProtocol
    ) async throws -> HostProtocolMessageResult {
        let envelope = try decoder.decode(ProtocolMessageEnvelope.self, from: message)

        switch envelope.type {
        case .windowCreated:
            // Clamped immediately after decode, before anything stores it or hands it to AppKit.
            let event = Self.sanitizedGuestWindow(try decoder.decode(WindowCreatedEvent.self, from: message))
            // Discovery is guest-owned and can enumerate every tracked process after reconnect.
            // The normal app-first path only opens macOS windows from an explicit host launch or
            // restore response. A later event may refresh an already-owned HWND, but it cannot
            // create another macOS window by itself.
            guard shouldAcceptTrackedWindowEvent(event) else {
                return .ignored
            }
            storeActiveWindow(event)
            storeMirrorSession(
                window: event,
                connectionMode: connectionMode,
                supportsCapture: hasLiveAgentConnection && health?.capabilities.windowCapture == true
            )
            await refreshRestoreIntentFromOpenWindows()
            // A reconnect can enumerate a HWND that is already mirrored. Keep a minimized window
            // paused across that discovery pass: re-subscribing here would make the guest capture a
            // surface the user deliberately hid and would race the next restore transition.
            if hasLiveAgentConnection,
               health?.capabilities.windowCapture == true,
               !pausedFrameStreamWindowIds.contains(event.windowId) {
                do {
                    try await service.subscribeWindowFrames(windowId: event.windowId)
                } catch {
                    errorMessage = userMessage(for: error)
                    phase = .failed
                }
            }
            return .handledWindowCreated(windowId: event.windowId)
        case .windowUpdated:
            let event = try decoder.decode(WindowUpdatedEvent.self, from: message)
            // `window.updated` matters more than `window.created` here: it is re-applied to a live NSWindow's
            // constraints on every arrival, so this is the path a guest would use to keep handing AppKit
            // absurd values.
            let window = Self.sanitizedGuestWindow(WindowCreatedEvent(updated: event))
            guard updateWindowState(window) else {
                return .ignored
            }

            return .handledWindowUpdated(windowId: event.windowId)
        case .windowFrame:
            let frame = try decoder.decode(WindowFrameEvent.self, from: message)
            receiveWindowFrame(frame)
            return mirrorSessions.contains(where: { $0.id == frame.windowId && $0.latestFrame == frame })
                ? .handledWindowFrame(windowId: frame.windowId)
                : .ignored
        case .windowClosed:
            let event = try decoder.decode(WindowClosedEvent.self, from: message)
            guard activeWindows.contains(where: { $0.windowId == event.windowId })
                    || mirrorSessions.contains(where: { $0.id == event.windowId }) else {
                return .ignored
            }

            await removeWindowState(windowId: event.windowId)
            return .handledWindowClosed(windowId: event.windowId)
        case .clipboardTextSet:
            let clipboard = try decoder.decode(ClipboardTextSet.self, from: message)
            return receiveClipboardText(clipboard)
                ? .handledClipboardText(sequence: clipboard.sequence)
                : .ignored
        case .windowFrameUnchanged:
            let event = try decoder.decode(WindowFrameUnchangedEvent.self, from: message)
            return receiveWindowFrameUnchanged(event)
                ? .handledWindowFrameUnchanged(windowId: event.windowId)
                : .ignored
        case .notificationReceived:
            let notification = try decoder.decode(WindowsNotificationReceivedEvent.self, from: message)
            return receiveWindowsNotification(notification)
                ? .handledWindowsNotification(notificationId: notification.notificationId)
                : .ignored
        default:
            return .ignored
        }
    }

    public func consumeProtocolMessages(
        from source: any HostEventSource,
        onMessageHandled: @MainActor (HostProtocolMessageResult) -> Void = { _ in }
    ) async {
        var consecutiveUndecodableMessages = 0
        do {
            for try await message in source.eventMessages() {
                // Only ever transitions .reconnecting -> .connected here, never touching .loading/
                // .launching/.idle/.failed -- those are driven by unrelated user-triggered flows
                // sharing this same `phase` property, and this background pump must not clobber them.
                if phase == .reconnecting {
                    phase = .connected
                }

                // Per-message, so one undecodable message no longer ends the connection. Before this, the
                // only `do/catch` was outside the loop: a single `sequence` that overflowed `Int`, or any
                // missing field, dropped the host to `.reconnecting` and cost a backoff. Sent repeatedly, the
                // host never held a stable event connection and lost window updates, clipboard, and
                // notifications for as long as it continued.
                //
                // Everything `receiveProtocolMessage` can throw is a decode failure -- the handlers
                // themselves do not throw -- so tolerating these is tolerating malformed guest input, not
                // swallowing host errors.
                do {
                    let result = try await receiveProtocolMessage(message)
                    consecutiveUndecodableMessages = 0
                    onMessageHandled(result)
                } catch {
                    consecutiveUndecodableMessages += 1
                    VeilLog.agent.error(
                        "Discarding an undecodable control message: \(String(describing: error))"
                    )
                    // A persistent framing disagreement still has to surface rather than looping forever on
                    // garbage. Same tolerance and same reasoning as the binary frame channel.
                    if consecutiveUndecodableMessages >= Self.undecodableControlMessageTolerance {
                        VeilLog.agent.error(
                            "Ending the control connection after \(consecutiveUndecodableMessages, privacy: .public) consecutive undecodable messages."
                        )
                        break
                    }
                }
            }
        } catch {
            // Callers run this in a `while !Task.isCancelled` retry loop, so a dropped connection
            // recovers on its own -- but a silent `return` here leaves zero trace of *why* window
            // updates or clipboard sync briefly stopped, which is exactly the failure class that
            // masked a real crash on the guest-agent side earlier the same day this was written.
            // Not `.public`: this error can originate from a disk-backed transport/decoding path and
            // os.Logger's default `.private` redaction is the same protection `exportDiagnostics`
            // applies to on-disk paths elsewhere in this codebase -- a log line is not the place to
            // reintroduce an unredacted host path into Console.app/sysdiagnose output.
            VeilLog.agent.notice("consumeProtocolMessages stopped: \(String(describing: error))")
        }

        // The event stream just ended, whether via the catch above or by completing normally --
        // either way the live pump is no longer running. Only flip .connected -> .reconnecting (see
        // the guard at loop entry above for why other phases are left alone); the caller's retry loop
        // will call this again, which flips back to .connected once a message actually arrives.
        if phase == .connected {
            phase = .reconnecting
        }
    }

    func storeActiveWindow(_ window: WindowCreatedEvent) {
        if let index = activeWindows.firstIndex(where: { $0.windowId == window.windowId }) {
            activeWindows[index] = window
            return
        }

        activeWindows.append(window)
    }

    private func shouldAcceptTrackedWindowEvent(_ event: WindowCreatedEvent) -> Bool {
        if activeWindows.contains(where: { $0.windowId == event.windowId })
            || mirrorSessions.contains(where: { $0.id == event.windowId }) {
            return true
        }

        return shouldAdoptAdditionalWindow(event)
    }

    /// Whether a window Veil never launched should still become a macOS window.
    ///
    /// There are two kinds of window Veil did not launch and they are not the same. A window of an app
    /// the user **already has open here** is the app doing what they asked — they opened Word, Word
    /// opened a second document — and their act of opening the app is the consent. A window of an app
    /// never opened in this session is a leftover process or something Windows started on its own, and an
    /// unrequested window appearing on screen is worse than a missing one.
    ///
    /// The guest enumerates every tracked process after a reconnect, so this distinction is what keeps
    /// discovery from materializing windows nobody asked for.
    func shouldAdoptAdditionalWindow(_ event: WindowCreatedEvent) -> Bool {
        Self.shouldAdoptAdditionalWindow(
            event,
            openWindowCountForApp: openWindowCount(forAppId: event.appId)
        )
    }

    /// The adoption decision as a pure function of the event and how many windows the app already has.
    ///
    /// Separated from the model so every branch — including the per-app bound, which is otherwise only
    /// reachable after opening eight windows — is testable without driving the guest protocol.
    static func shouldAdoptAdditionalWindow(
        _ event: WindowCreatedEvent,
        openWindowCountForApp: Int
    ) -> Bool {
        // A zero-sized or untitled top-level window is far more likely a tooltip, splash, or transient
        // shell window than a document.
        guard !event.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              event.bounds.width > 0,
              event.bounds.height > 0 else {
            return false
        }

        // Zero means this app has no window here, so the window belongs to something the user never
        // opened in this session.
        guard openWindowCountForApp > 0 else {
            return false
        }

        // Bounds guest-driven creation, which the host does not control. Not a judgement about how many
        // windows a user should have: deliberate document windows will not reach it, while a misdetected
        // transient window or a runaway enumeration loop would otherwise open macOS windows without
        // limit. Distinct from a cap on *total* windows, which Veil refuses, because every window from an
        // explicit launch is one the host asked for.
        return openWindowCountForApp < maximumAdoptedWindowsPerApp
    }

    func openWindowCount(forAppId appId: String) -> Int {
        mergedOpenWindows().filter { $0.appId == appId }.count
    }

    func storeMirrorSession(
        window: WindowCreatedEvent,
        connectionMode: HostConnectionMode,
        supportsCapture: Bool
    ) {
        let captureState: WindowCaptureState = connectionMode == .agent && supportsCapture ? .pending : .unavailable
        hasOpenedAppWindowThisSession = true
        let session = WindowMirrorSession(
            window: window,
            connectionMode: connectionMode,
            captureState: captureState,
            frameStreamRequestedAt: captureState == .pending ? Date() : nil
        )

        if let index = mirrorSessions.firstIndex(where: { $0.id == session.id }) {
            // `window.created` is both a launch response and the guest's reconnect enumeration
            // event. It is therefore normal to see it more than once for one HWND. Replacing the
            // value object here used to erase the last frame, timing evidence, compositor generation,
            // and recovery count before the new subscription acknowledgement arrived. Preserve the
            // live stream state and only refresh guest-owned metadata; a session that was unavailable
            // may still be promoted when a later event proves capture is available.
            var existing = mirrorSessions[index]
            existing.window = window
            existing.connectionMode = connectionMode
            if existing.captureState == .unavailable, captureState != .unavailable {
                existing.captureState = captureState
                existing.frameStreamRequestedAt = session.frameStreamRequestedAt
            }
            mirrorSessions[index] = existing
            return
        }

        mirrorSessions.append(session)
    }

    private func updateWindowState(_ window: WindowCreatedEvent) -> Bool {
        let isTracked = activeWindows.contains { $0.windowId == window.windowId }
            || mirrorSessions.contains { $0.id == window.windowId }
        guard isTracked else {
            return false
        }

        storeActiveWindow(window)

        guard let index = mirrorSessions.firstIndex(where: { $0.id == window.windowId }) else {
            return true
        }

        mirrorSessions[index].window = window
        return true
    }

    func markFocusedWindow(windowId: String) {
        activeWindows = activeWindows.map { window in
            var focusedWindow = window
            focusedWindow.focused = window.windowId == windowId
            return focusedWindow
        }

        mirrorSessions = mirrorSessions.map { session in
            var focusedSession = session
            focusedSession.window.focused = session.id == windowId
            return focusedSession
        }
    }

    func removeWindowState(windowId: String) async {
        activeWindows.removeAll { $0.windowId == windowId }
        mirrorSessions.removeAll { $0.id == windowId }
        // Otherwise a window minimized and then closed stays in the paused set forever, and a later window
        // that reused the same HWND would be treated as already paused and never resubscribed.
        pausedFrameStreamWindowIds.remove(windowId)
        pendingFrameStreamVisibility.removeValue(forKey: windowId)
        frameStreamVisibilityOperationIDs.removeValue(forKey: windowId)
        frameStreamVisibilityTasks.removeValue(forKey: windowId)?.cancel()
        // Each composited surface is a full-resolution bitmap. A closed window that kept one would hold
        // megabytes for the rest of the process's lifetime.
        frameCompositor.forget(windowId: windowId)

        if lastLaunch?.window.windowId == windowId {
            lastLaunch = nil
        }

        await refreshRestoreIntentFromOpenWindows()
    }

    func refreshRestoreIntentFromOpenWindows() async {
        let windows = mergedOpenWindows()
        restorableAppIds = orderedUniqueAppIds(from: windows)
        // The real count per app. This previously wrote 1 for every app regardless of how many windows
        // it had open, which made a field documented as "how many windows were open" a constant.
        //
        // It stays diagnostic input, not a restore queue: `restorableAppIdsForLaunches()` still issues
        // one launch per app, because a second launch of an app that already owns a window reuses that
        // HWND rather than opening another.
        restorableAppWindowCounts = windows.reduce(into: [:]) { counts, window in
            counts[window.appId, default: 0] += 1
        }
        await persistRestoreIntent()
    }

    private func persistRestoreIntent() async {
        do {
            try await restoreIntentStore.save(
                WindowRestoreIntent(
                    appIds: restorableAppIds,
                    appWindowCounts: restorableAppWindowCounts.isEmpty ? nil : restorableAppWindowCounts
                )
            )
        } catch {
            errorMessage = userMessage(for: error)
            return
        }
    }

    func restorableAppIdsForLaunches() -> [String] {
        // A persisted count records how many windows were open for diagnostics, not how many
        // launch requests a reconnect may issue. Replaying the count reopens duplicate Windows
        // instances when an app already owns the restored HWND. New document windows arrive from
        // the guest discovery stream after the first stable app window is attached.
        var seen: Set<String> = []
        return restorableAppIds.filter { seen.insert($0).inserted }
    }

    private func mergedOpenWindows() -> [WindowCreatedEvent] {
        var windowsById: [String: WindowCreatedEvent] = [:]
        var orderedWindowIds: [String] = []

        func append(_ window: WindowCreatedEvent) {
            if windowsById[window.windowId] == nil {
                orderedWindowIds.append(window.windowId)
            }
            windowsById[window.windowId] = window
        }

        activeWindows.forEach(append)
        mirrorSessions.map(\.window).forEach(append)
        return orderedWindowIds.compactMap { windowsById[$0] }
    }

    private func orderedUniqueAppIds(from windows: [WindowCreatedEvent]) -> [String] {
        var seen: Set<String> = []
        var appIds: [String] = []

        for window in windows where !seen.contains(window.appId) {
            seen.insert(window.appId)
            appIds.append(window.appId)
        }

        return appIds
    }

    func queuePendingLaunchIntent(appId: String?) async {
        pendingLaunchAppId = appId
        await persistPendingLaunchIntent()
    }

    func clearPendingLaunchIntent() async {
        pendingLaunchAppId = nil
        await persistPendingLaunchIntent()
    }

    private func persistPendingLaunchIntent() async {
        do {
            try await pendingLaunchIntentStore.save(PendingLaunchIntent(appId: pendingLaunchAppId))
        } catch {
            errorMessage = userMessage(for: error)
            return
        }
    }

    func selectDefaultAppIfNeeded() {
        if let selectedAppId, apps.contains(where: { $0.id == selectedAppId }) {
            return
        }

        selectedAppId = apps.first?.id
    }

    func userMessage(for error: any Error) -> String {
        if let localized = error as? LocalizedError,
           let description = localized.errorDescription {
            return description
        }

        return String(describing: error)
    }
}
