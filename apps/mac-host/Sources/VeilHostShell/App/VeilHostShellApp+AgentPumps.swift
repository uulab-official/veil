import AppKit
import SwiftUI
import VeilHostCore

extension VeilHostShellApp {
    func recordGuestAgentInstallEvidenceIfNeeded() async {
        noteLiveAgentConnectionIfPresent()
        guard model.hasLiveAgentConnection,
              let agentVersion = model.health?.agentVersion,
              vmModel.snapshot?.profileName != nil,
              vmModel.snapshot?.installEvidence.kind != .guestAgent else {
            return
        }

        await vmModel.markGuestAgentConnected(agentVersion: agentVersion)
    }

    /// Consumes window frames from the guest's dedicated binary connection.
    ///
    /// Only started when the connected agent advertises the capability, so an older agent keeps using the
    /// JSON frame path on the control connection. Decoded frames go through the same
    /// `receiveWindowFrame` entry point, so status, timing, proof artifacts, and rendering are all
    /// unchanged by which transport delivered the frame.
    func startFrameChannelPumpIfNeeded() {
        guard agentConnectionPlan.isAvailable,
              frameChannelTask == nil,
              model.health?.capabilities.binaryFrameChannel == true,
              let url = URLSessionFrameChannel.frameChannelURL(
                  agentEndpoint: agentConnectionPlan.endpoint
              ) else {
            return
        }

        let channel = URLSessionFrameChannel(url: url)
        frameChannelTask = Task { @MainActor in
            // Same bounded-backoff discipline as the control event pump: a sustained outage must not spin
            // at the base rate forever.
            let baseRetryDelaySeconds: Double = 2
            let maxRetryDelaySeconds: Double = 10
            var retryDelaySeconds = baseRetryDelaySeconds

            while !Task.isCancelled {
                do {
                    for try await message in channel.frames() {
                        retryDelaySeconds = baseRetryDelaySeconds
                        // Routed through the compositor: a tile is not a displayable frame, and a tile that
                        // cannot be composited must not present a window.
                        let accepted = model.receiveWindowFrameTile(
                            message.tile,
                            wireByteCount: message.wireByteCount
                        )
                        if !accepted,
                           model.requiresFrameStreamRestartAfterTileDrop(windowId: message.tile.windowId) {
                            // A missing delta cannot be repaired by later small tiles. Restart only this
                            // HWND so the guest begins a fresh stream with a key frame.
                            _ = await model.restartFrameSubscription(windowId: message.tile.windowId)
                        }
                        guard accepted,
                              let session = model.mirrorSessions.first(where: { $0.id == message.tile.windowId }) else {
                            continue
                        }

                        presentWindowsAppWindowForEvent(session)
                    }
                } catch {
                    VeilLog.agent.notice(
                        "Binary frame channel stopped; retrying. \(String(describing: error))"
                    )
                    if case HostFrameChannelError.bufferOverflow(let windowId) = error {
                        // A dropped incremental tile leaves an unknown rectangle in the compositor. Reset
                        // only that HWND so unrelated mirrored apps keep their surfaces and input alive.
                        _ = await model.restartFrameSubscription(windowId: windowId)
                    }
                }

                if Task.isCancelled {
                    return
                }

                try? await Task.sleep(for: .seconds(retryDelaySeconds))
                retryDelaySeconds = min(maxRetryDelaySeconds, retryDelaySeconds * 2)
            }
        }
    }

    func startAgentEventPumpIfNeeded() {
        guard agentEventTask == nil,
              agentConnectionPlan.isAvailable,
              let agentTransport else {
            return
        }

        agentEventTask = Task { @MainActor in
            // Bounded backoff instead of a fixed 2s retry: a real, sustained guest-agent outage
            // shouldn't spin at the same high rate (and log at the same high rate, per
            // VeilLog.agent.notice in consumeProtocolMessages) forever. Resets to the base interval
            // the moment a message is actually received again.
            let baseRetryDelaySeconds: Double = 2
            let maxRetryDelaySeconds: Double = 10
            var retryDelaySeconds = baseRetryDelaySeconds

            while !Task.isCancelled {
                await model.consumeProtocolMessages(from: agentTransport) { result in
                    switch result {
                    case .handledWindowCreated(let windowId):
                        guard let session = model.mirrorSessions.first(where: { $0.id == windowId }) else {
                            return
                        }

                        // A newly created window is raised by the presenter regardless; passing true
                        // here only matters when the window already existed, which for this event means
                        // the guest re-announced a window the user already has open.
                        if presentWindowsAppWindowForEvent(session, bringToFront: true) {
                            syncLauncherWindowVisibility()
                        }
                    case .handledWindowUpdated(let windowId):
                        guard let session = model.mirrorSessions.first(where: { $0.id == windowId }) else {
                            return
                        }

                        presentWindowsAppWindowForEvent(session)
                    case .handledWindowFrame(let windowId):
                        guard let session = model.mirrorSessions.first(where: { $0.id == windowId }) else {
                            return
                        }

                        presentWindowsAppWindowForEvent(session)
                    case .handledWindowFrameUnchanged:
                        // Liveness only. Nothing new to present, and re-presenting would churn the window.
                        break
                    case .handledWindowClosed(let windowId):
                        windowsAppWindowPresenter.closeWindow(windowId: windowId)
                        scheduleAutomaticQuietRuntimeIfNeeded()
                        syncLauncherWindowVisibility()
                    case .handledClipboardText:
                        syncGuestClipboardToPasteboard()
                    case .handledWindowsNotification(let notificationId):
                        presentWindowsNotification(notificationId: notificationId)
                    case .ignored:
                        return
                    }
                }

                noteLiveAgentConnectionIfPresent()

                if model.phase == .reconnecting {
                    retryDelaySeconds = min(retryDelaySeconds * 2, maxRetryDelaySeconds)
                } else {
                    retryDelaySeconds = baseRetryDelaySeconds
                }
                try? await Task.sleep(for: .seconds(retryDelaySeconds))
            }
        }
    }

    func startAgentReconnectPollerIfNeeded() {
        guard agentReconnectTask == nil,
              agentConnectionPlan.isAvailable else {
            return
        }

        agentReconnectTask = Task { @MainActor in
            // Same bounded-backoff reasoning as startAgentEventPumpIfNeeded(): a sustained outage
            // shouldn't poll at the base rate forever. Resets the moment there's nothing left to do
            // (either reconnected, or the VM isn't in a state that needs polling at all).
            let baseRetryDelaySeconds: Double = 5
            let maxRetryDelaySeconds: Double = 15
            var retryDelaySeconds = baseRetryDelaySeconds

            while !Task.isCancelled {
                noteLiveAgentConnectionIfPresent()
                let vmState = vmModel.snapshot?.state
                let shouldPoll = (vmState == .running || vmState == .starting) && !model.hasLiveAgentConnection
                if shouldPoll {
                    scheduleAutomaticRuntimeConnectionRecoveryIfNeeded()
                    scheduleAutomaticGuestAgentRecoveryIfNeeded()

                    let restoredLaunches = await model.restoreMirroredWindowsAfterReconnect()
                    for launch in restoredLaunches {
                        showWindowsAppWindow(for: launch)
                    }
                    syncLauncherWindowVisibility()

                    var fulfilledLaunch: NotepadLaunchResult?
                    if restoredLaunches.isEmpty {
                        fulfilledLaunch = await model.refreshLiveAgentIfNeeded()
                        if let fulfilledLaunch {
                            showWindowsAppWindow(for: fulfilledLaunch)
                            syncLauncherWindowVisibility()
                        }
                    }
                    await recordGuestAgentInstallEvidenceIfNeeded()
                    // The first overview may have raced the guest agent and started without the
                    // binary-frame capability. Once this reconnect attempt obtains fresh health,
                    // start the dedicated frame channel as well; otherwise a recovered agent would
                    // silently remain on the JSON path for the rest of the app session.
                    startFrameChannelPumpIfNeeded()

                    let madeProgress = !restoredLaunches.isEmpty || fulfilledLaunch != nil || model.hasLiveAgentConnection
                    retryDelaySeconds = madeProgress
                        ? baseRetryDelaySeconds
                        : min(retryDelaySeconds * 2, maxRetryDelaySeconds)
                } else {
                    retryDelaySeconds = baseRetryDelaySeconds
                }

                try? await Task.sleep(for: .seconds(retryDelaySeconds))
            }
        }
    }

    func restorePreviousWindowsAppWindowAfterLaunchIfNeeded() async {
        guard windowsAppWindowPresenter.visibleWindowIds.isEmpty,
              model.mirrorSessions.isEmpty,
              !model.restorableAppIds.isEmpty else {
            return
        }

        // The first health request can succeed just before the guest completes its agent-side
        // recovery. Retry a few times, always with reuseExistingWindow, so startup reaches the
        // previously open app windows without turning a temporary connection race into a launch loop.
        for attempt in 0..<automaticRestoreMaximumAttempts {
            let restoredLaunches = await model.restoreMirroredWindowsAfterReconnect()
            for launch in restoredLaunches {
                showWindowsAppWindow(for: launch)
            }

            if !restoredLaunches.isEmpty || !windowsAppWindowPresenter.visibleWindowIds.isEmpty {
                return
            }

            guard attempt + 1 < automaticRestoreMaximumAttempts else {
                VeilLog.agent.notice(
                    "Automatic app restore did not open a window after \(self.automaticRestoreMaximumAttempts, privacy: .public) attempts; live agent=\(model.hasLiveAgentConnection, privacy: .public)."
                )
                return
            }
            try? await Task.sleep(for: .seconds(1))
        }
    }
}
