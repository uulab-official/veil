import CoreGraphics
import Foundation
import Observation

extension HostDashboardModel {
    public func receiveWindowFrame(_ frame: WindowFrameEvent, receivedAt: Date = Date()) {
        guard let index = mirrorSessions.firstIndex(where: { $0.id == frame.windowId }) else {
            return
        }

        // The binary frame channel bounds surface dimensions in its codec; the JSON path had no bound
        // anywhere. A `window.frame` declaring 30000x30000 is a ~110 KB message on the wire and a
        // multi-gigabyte `NSImage` decode on the main thread when the view renders it. Rejected here so the
        // implausible frame is never stored, rather than at each place that might draw it.
        guard Self.isPlausibleFrameSize(width: frame.width, height: frame.height) else {
            VeilLog.agent.notice(
                "Rejected a window.frame for \(frame.windowId, privacy: .public) declaring an implausible \(frame.width, privacy: .public)x\(frame.height, privacy: .public) size."
            )
            return
        }

        if mirrorSessionStorage[index].awaitingKeyFrameReason != nil, !frame.isCompositedSurface {
            // JSON and binary delivery can coexist. A real JSON full image can restore the missing
            // base, but merely plausible metadata (or another broken PNG) cannot prove recovery.
            guard let tile = frame.asKeyFrameTile(),
                  case .composited(let generation) = frameCompositor.apply(tile) else {
                return
            }
            mirrorSessionStorage[index].compositedFrameGeneration = generation
            mirrorSessionStorage[index].awaitingKeyFrameReason = nil
        }

        let priorTiming = mirrorSessionStorage[index].frameTiming
        mirrorSessionStorage[index].latestFrame = frame
        mirrorSessionStorage[index].captureState = .streaming
        mirrorSessionStorage[index].frameTiming = WindowFrameTiming(
            firstFrameReceivedAt: priorTiming?.firstFrameReceivedAt ?? receivedAt,
            latestFrameReceivedAt: receivedAt,
            latestActivityAt: receivedAt,
            latestFrameIntervalMilliseconds: priorTiming.map {
                max(0, Int((receivedAt.timeIntervalSince($0.latestFrameReceivedAt) * 1000).rounded()))
            },
            receivedFrameCount: (priorTiming?.receivedFrameCount ?? 0) + 1,
            unchangedHeartbeatCount: priorTiming?.unchangedHeartbeatCount ?? 0
        )
        forgiveFrameStreamRestartsIfRecovered(at: index, receivedAt: receivedAt)
        publishFrameChurnSoon()
    }

    /// Clears the restart ladder once a restarted stream has stayed alive long enough to count as recovered.
    private func forgiveFrameStreamRestartsIfRecovered(at index: Int, receivedAt: Date) {
        guard mirrorSessionStorage[index].frameStreamRestartCount > 0,
              let restartedAt = mirrorSessionStorage[index].latestFrameStreamRestartedAt,
              receivedAt.timeIntervalSince(restartedAt) >= WindowFrameStreamAssessment.restartLadderResetSeconds else {
            return
        }
        mirrorSessionStorage[index].frameStreamRestartCount = 0
    }

    /// Lets status views see frame bookkeeping without recomputing for every frame; see `mirrorSessions`.
    func publishFrameChurnSoon() {
        guard !frameChurnPublishPending else {
            return
        }
        frameChurnPublishPending = true
        Task { @MainActor [weak self] in
            try? await Task.sleep(for: Self.frameChurnPublishInterval)
            guard let self else {
                return
            }
            self.frameChurnPublishPending = false
            self.mirrorSessionsRevision &+= 1
            self.activeWindowsRevision &+= 1
        }
    }

    /// Composited surface for a mirrored window, or `nil` until a key frame establishes one.
    public func compositedFrameImage(for windowId: String) -> CGImage? {
        frameCompositor.image(for: windowId)
    }

    /// Whether a dropped tile means the guest stream itself must be restarted.
    ///
    /// A malformed payload or an unkeyed resize can recover when the guest eventually emits its next
    /// key frame. A sequence gap is different: the guest may continue sending small deltas forever, and
    /// none of them can repair the missing base. The binary-channel pump uses this narrow signal to reset
    /// only this window's subscription immediately.
    public func requiresFrameStreamRestartAfterTileDrop(windowId: String) -> Bool {
        mirrorSessions.first(where: { $0.id == windowId })?.awaitingKeyFrameReason
            == WindowFrameCompositor.RejectionReason.sequenceGap.rawValue
    }

    /// Applies a frame update that may be a dirty-rect tile rather than a whole frame.
    ///
    /// Timing, staleness, latency budgets, and proof artifacts all read exactly as they do for a
    /// JSON-delivered frame: a successfully composited tile is a received frame. A tile that cannot be
    /// composited is deliberately *not* counted, because the window did not actually update, and letting
    /// it refresh the frame clock would make a stalled surface look healthy.
    @discardableResult
    public func receiveWindowFrameTile(
        _ tile: WindowFrameTile,
        wireByteCount: Int? = nil,
        receivedAt: Date = Date()
    ) -> Bool {
        guard let index = mirrorSessions.firstIndex(where: { $0.id == tile.windowId }) else {
            return false
        }

        let compositeStartedAt = ContinuousClock.now
        let outcome = frameCompositor.apply(tile)
        let compositeDuration = ContinuousClock.now - compositeStartedAt

        switch outcome {
        case .composited(let generation):
            mirrorSessionStorage[index].compositedFrameGeneration = generation
            mirrorSessionStorage[index].awaitingKeyFrameReason = nil
            receiveWindowFrame(tile.surfaceMetadataFrameEvent(), receivedAt: receivedAt)
            framePipelineMetrics?.recordApplied(
                tile: tile,
                // Falls back to the payload size when the caller did not measure the wire size, so a
                // JSON-delivered or synthesized tile still contributes a defensible byte count.
                wireByteCount: wireByteCount ?? tile.payload.count,
                compositeDuration: TimeInterval(compositeDuration.components.seconds)
                    + TimeInterval(compositeDuration.components.attoseconds) / 1e18,
                receivedAt: receivedAt
            )
            return true
        case .needsKeyFrame(let reason):
            mirrorSessionStorage[index].awaitingKeyFrameReason = reason.rawValue
            publishFrameChurnSoon()
            framePipelineMetrics?.recordDropped(windowId: tile.windowId, reason: reason, at: receivedAt)
            VeilLog.agent.notice(
                "Dropped a frame tile for \(tile.windowId, privacy: .public); waiting for a key frame because \(reason.rawValue, privacy: .public)."
            )
            return false
        }
    }

    /// Records that a frame stream is alive with nothing new to draw.
    ///
    /// Advances liveness only. `latestFrameReceivedAt` is left alone on purpose so the frame-latency
    /// budget and saved proof artifacts keep measuring how old the displayed picture really is; a
    /// heartbeat does not make the picture newer.
    ///
    /// Ignored before the first real frame: a stream that has never produced an image is still
    /// `waitingForFirstFrame`, and letting a heartbeat satisfy that would hide capture that never
    /// started.
    @discardableResult
    public func receiveWindowFrameUnchanged(
        _ event: WindowFrameUnchangedEvent,
        receivedAt: Date = Date()
    ) -> Bool {
        guard let index = mirrorSessions.firstIndex(where: { $0.id == event.windowId }),
              // A heartbeat proves the guest is alive, not that the host has every changed pixel.
              // Keep the last successful frame's clock so ordinary stale-stream recovery can run.
              mirrorSessionStorage[index].awaitingKeyFrameReason == nil,
              let priorTiming = mirrorSessionStorage[index].frameTiming else {
            return false
        }

        mirrorSessionStorage[index].frameTiming = WindowFrameTiming(
            firstFrameReceivedAt: priorTiming.firstFrameReceivedAt,
            latestFrameReceivedAt: priorTiming.latestFrameReceivedAt,
            latestActivityAt: receivedAt,
            latestFrameIntervalMilliseconds: priorTiming.latestFrameIntervalMilliseconds,
            receivedFrameCount: priorTiming.receivedFrameCount,
            unchangedHeartbeatCount: priorTiming.unchangedHeartbeatCount + 1
        )
        forgiveFrameStreamRestartsIfRecovered(at: index, receivedAt: receivedAt)
        publishFrameChurnSoon()
        framePipelineMetrics?.recordUnchangedHeartbeat(windowId: event.windowId, at: receivedAt)
        return true
    }

    @discardableResult
    public func focusMirrorSession(windowId: String) async -> WindowFocusResponse? {
        guard canFocusMirrorSession(windowId: windowId) else {
            return nil
        }

        do {
            let response: WindowFocusResponse
            if hasLiveAgentConnection {
                response = try await service.focusWindow(windowId: windowId)
            } else {
                response = WindowFocusResponse(
                    requestId: "local_focus_window",
                    windowId: windowId,
                    accepted: true
                )
            }

            if response.accepted {
                markFocusedWindow(windowId: windowId)
            }
            return response
        } catch {
            errorMessage = userMessage(for: error)
            phase = .failed
            return nil
        }
    }

    @discardableResult
    public func closeMirrorSession(windowId: String) async -> WindowCloseResponse? {
        guard canCloseMirrorSession(windowId: windowId) else {
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

    @discardableResult
    public func restartFrameSubscription(windowId: String, restartedAt: Date = Date()) async -> Bool {
        guard let startingIndex = mirrorSessions.firstIndex(where: { $0.id == windowId }),
              mirrorSessions[startingIndex].captureState != .unavailable,
              hasLiveAgentConnection else {
            return false
        }
        guard frameStreamRestartInFlightWindowIds.insert(windowId).inserted else {
            return false
        }
        defer { frameStreamRestartInFlightWindowIds.remove(windowId) }

        do {
            try Task.checkCancellation()
            try await service.unsubscribeWindowFrames(windowId: windowId)
            try Task.checkCancellation()
            guard prepareFrameSubscription(windowId: windowId, requestedAt: restartedAt) else {
                return false
            }
            try await service.subscribeWindowFrames(windowId: windowId)
            try Task.checkCancellation()
        } catch {
            // The guest untracks an HWND the moment its window closes inside Windows, while the
            // host only learns about it through a `window.closed` event on the separate event
            // connection. An agent with acknowledgements can now say so directly: `window_not_tracked`
            // means the window is gone, so dropping the mirror session stops the staleness ladder
            // from escalating into offering to relaunch an app that no longer exists.
            if await dropMirrorSessionIfUntracked(windowId: windowId, error: error) {
                return false
            }

            // Background frame-stream maintenance, not a user action. `.failed` is documented as reserved
            // for "a user-triggered action that failed outright" and renders as "Connection failed", so a
            // retry loop that could not resubscribe must not put the whole model there. Returning `false`
            // already tells the caller to try again.
            errorMessage = userMessage(for: error)
            return false
        }

        guard let index = resolvedMirrorSessionIndex(for: windowId) else {
            return false
        }

        // The independent event/frame channel may already have delivered the new image
        // while subscribe awaited its acknowledgement. Never reset that image here.
        mirrorSessions[index].frameStreamRestartCount += 1
        mirrorSessions[index].latestFrameStreamRestartedAt = restartedAt
        return true
    }

    /// Starts a new frame epoch locally before the guest can deliver its first frame.
    /// Re-resolving here also prevents a close received during unsubscribe from being
    /// followed by a subscribe for the removed window.
    private func prepareFrameSubscription(windowId: String, requestedAt: Date) -> Bool {
        guard let index = resolvedMirrorSessionIndex(for: windowId) else { return false }
        frameCompositor.forget(windowId: windowId)
        mirrorSessions[index].captureState = .pending
        mirrorSessions[index].latestFrame = nil
        mirrorSessions[index].frameTiming = nil
        mirrorSessions[index].compositedFrameGeneration = 0
        mirrorSessions[index].awaitingKeyFrameReason = nil
        mirrorSessions[index].frameStreamRequestedAt = requestedAt
        return true
    }

    /// Stops paying for a window nobody can see.
    ///
    /// A minimized mirrored window still had the guest capturing its pixels, comparing them, PNG-encoding
    /// them, and sending them, and the host still decoded and composited every one — for a window collapsed
    /// into the Dock. This unsubscribes instead.
    ///
    /// The subtle part is not the unsubscribe, it is not tripping the staleness ladder. A stream with no frames
    /// arriving normally escalates `restart-frame-subscription` → `recover-window-capture` →
    /// `reopen-windows-app`, so a naive pause would offer to relaunch the user's app seconds after they
    /// minimized it. That ladder is climbed by `frameStreamRestartCount`, which only the automatic sweeps
    /// increment — so paused windows are excluded from those sweeps and the count never rises.
    ///
    /// `frameStreamRestartCount` is deliberately neither incremented nor reset: minimizing is not a restart
    /// attempt, and restoring is not evidence that an underlying capture problem went away.
    @discardableResult
    public func pauseFrameStream(windowId: String, pausedAt: Date = Date()) async -> Bool {
        guard let startingIndex = mirrorSessions.firstIndex(where: { $0.id == windowId }),
              mirrorSessions[startingIndex].captureState != .unavailable,
              !pausedFrameStreamWindowIds.contains(windowId),
              pendingFrameStreamVisibility[windowId] != true,
              hasLiveAgentConnection else {
            return false
        }

        pendingFrameStreamVisibility[windowId] = true
        return await enqueueFrameStreamVisibility(
            windowId: windowId,
            shouldPause: true,
            requestedAt: pausedAt
        )
    }

    /// Resubscribes a window whose stream was paused because it was not visible.
    ///
    /// Setting `frameStreamRequestedAt` here is what restarts the normal first-frame timeout, so a window that
    /// comes back and then genuinely fails to draw is still caught.
    @discardableResult
    public func resumeFrameStream(windowId: String, resumedAt: Date = Date()) async -> Bool {
        guard pausedFrameStreamWindowIds.contains(windowId)
                || pendingFrameStreamVisibility[windowId] == true,
              pendingFrameStreamVisibility[windowId] != false,
              mirrorSessions.contains(where: { $0.id == windowId }),
              hasLiveAgentConnection else {
            return false
        }

        pendingFrameStreamVisibility[windowId] = false
        return await enqueueFrameStreamVisibility(
            windowId: windowId,
            shouldPause: false,
            requestedAt: resumedAt
        )
    }

    /// Adds a visibility transition to the per-window tail. AppKit can deliver a restore before the guest has
    /// acknowledged the preceding unsubscribe; serializing the tail keeps stream ownership in the same order
    /// as the user's final window state.
    private func enqueueFrameStreamVisibility(
        windowId: String,
        shouldPause: Bool,
        requestedAt: Date
    ) async -> Bool {
        let operationID = UUID()
        let predecessor = frameStreamVisibilityTasks[windowId]
        frameStreamVisibilityOperationIDs[windowId] = operationID
        let task = Task { @MainActor [weak self] in
            if let predecessor {
                _ = await predecessor.value
            }
            guard let self, !Task.isCancelled else {
                return false
            }

            return await self.applyFrameStreamVisibility(
                windowId: windowId,
                shouldPause: shouldPause,
                requestedAt: requestedAt
            )
        }
        frameStreamVisibilityTasks[windowId] = task

        let result = await task.value
        if frameStreamVisibilityOperationIDs[windowId] == operationID {
            frameStreamVisibilityTasks.removeValue(forKey: windowId)
            frameStreamVisibilityOperationIDs.removeValue(forKey: windowId)
            pendingFrameStreamVisibility.removeValue(forKey: windowId)
        }
        return result
    }

    private func applyFrameStreamVisibility(
        windowId: String,
        shouldPause: Bool,
        requestedAt: Date
    ) async -> Bool {
        guard hasLiveAgentConnection else {
            return false
        }

        if shouldPause {
            guard let startingIndex = mirrorSessions.firstIndex(where: { $0.id == windowId }),
                  mirrorSessions[startingIndex].captureState != .unavailable,
                  !pausedFrameStreamWindowIds.contains(windowId) else {
                return false
            }

            do {
                try Task.checkCancellation()
                try await service.unsubscribeWindowFrames(windowId: windowId)
                try Task.checkCancellation()
            } catch {
                return false
            }

            guard let index = resolvedMirrorSessionIndex(for: windowId) else {
                return false
            }

            pausedFrameStreamWindowIds.insert(windowId)
            mirrorSessions[index].captureState = .pending
            mirrorSessions[index].frameTiming = nil
            mirrorSessions[index].latestFrame = nil
            // Kept, not cleared. `harness/app-runtime-status` requires `frameStreamRequestedAt` on any capture
            // session with no received frames, so clearing it would make every paused window fail the report
            // contract. Escalation is prevented by excluding paused windows from the automatic sweeps instead,
            // which is what actually drives `frameStreamRestartCount` upward.
            mirrorSessions[index].frameStreamRequestedAt = requestedAt
            return true
        }

        guard pausedFrameStreamWindowIds.contains(windowId) else {
            // The window may have been restored before the queued pause actually started. It never lost its
            // subscription, so treating this as a successful no-op leaves the final visible state correct.
            return true
        }

        do {
            try Task.checkCancellation()
            guard prepareFrameSubscription(windowId: windowId, requestedAt: requestedAt) else {
                return false
            }
            try await service.subscribeWindowFrames(windowId: windowId)
            try Task.checkCancellation()
        } catch {
            // Left in the paused set so a later resume can try again, rather than being remembered as live
            // while no frames are coming.
            return false
        }

        guard resolvedMirrorSessionIndex(for: windowId) != nil else {
            return false
        }

        pausedFrameStreamWindowIds.remove(windowId)
        return true
    }

    /// Whether this window's frame stream is paused because nothing on screen can show it.
    public func isFrameStreamPaused(windowId: String) -> Bool {
        pausedFrameStreamWindowIds.contains(windowId)
    }

    /// Consecutive undecodable control messages tolerated before the connection is ended.
    ///
    /// Mirrors `HostFrameChannel.malformedFrameTolerance`. One bad message should not cost a reconnect; a
    /// guest that only ever sends garbage still has to be given up on.
    nonisolated static let undecodableControlMessageTolerance = 8

    /// Longest guest clipboard update the host will accept, in UTF-16 code units.
    ///
    /// Deliberately far above the 4096-unit bound on the host's own committed *text input*: people legitimately
    /// copy whole documents, and a clipboard is not a keystroke. 4 million units is roughly 800 pages of prose,
    /// so nothing real is refused, while a single message can no longer be unbounded.
    ///
    /// This bounds one message. It does **not** bound the rate — see
    /// `docs/checklists/2026-08-16-guest-to-host-trust.md`.
    nonisolated static let maximumGuestClipboardUTF16Length = 4 * 1_024 * 1_024

    /// Longest window title the host will carry.
    ///
    /// The title flows into an `NSWindow`, dock menu items, menu bar items, and status reports, none of which
    /// bounded it. A megabyte title, re-sent on every `window.updated`, is a layout cost in several places at
    /// once. No real window title is close to this.
    /// `nonisolated` so `sanitizedWindowTitle` can read it: that function is a pure rule about guest data, and
    /// tying it to the main actor would be a property of the enclosing model rather than of the rule.
    nonisolated static let maximumWindowTitleLength = 256
}

extension HostDashboardModel {
    /// Tells the agent which windows the host shows by cropping the guest framebuffer, so it captures
    /// them only about once a second (`window.crop.set`). A failure only costs guest CPU, so it is logged
    /// rather than shown.
    public func setCroppedWindows(windowIds: [String], hidesDesktop: Bool = false) async {
        guard hasLiveAgentConnection, health?.capabilities.windowLayout == true else {
            return
        }
        do {
            try await service.setCroppedWindows(windowIds: windowIds, hidesDesktop: hidesDesktop)
        } catch {
            VeilLog.window.error("Failed to report cropped windows: \(String(describing: error), privacy: .public)")
        }
    }
}

extension HostDashboardModel {
    /// Moves a mirrored window in Windows to where its Mac window is (`window.move.request`). A failure
    /// only means the guest layout lags, so it is logged rather than shown.
    public func moveMirrorSession(windowId: String, x: Int, y: Int) async {
        guard hasLiveAgentConnection,
              health?.capabilities.windowLayout == true,
              mirrorSessions.contains(where: { $0.id == windowId }) else {
            return
        }
        do {
            try await service.moveWindow(windowId: windowId, x: x, y: y)
        } catch {
            VeilLog.window.error("Failed to move window \(windowId, privacy: .public): \(String(describing: error), privacy: .public)")
        }
    }
}
