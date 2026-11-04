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

        let priorTiming = mirrorSessions[index].frameTiming
        mirrorSessions[index].latestFrame = frame
        mirrorSessions[index].captureState = .streaming
        mirrorSessions[index].frameTiming = WindowFrameTiming(
            firstFrameReceivedAt: priorTiming?.firstFrameReceivedAt ?? receivedAt,
            latestFrameReceivedAt: receivedAt,
            latestActivityAt: receivedAt,
            latestFrameIntervalMilliseconds: priorTiming.map {
                max(0, Int((receivedAt.timeIntervalSince($0.latestFrameReceivedAt) * 1000).rounded()))
            },
            receivedFrameCount: (priorTiming?.receivedFrameCount ?? 0) + 1,
            unchangedHeartbeatCount: priorTiming?.unchangedHeartbeatCount ?? 0
        )
    }

    /// Composited surface for a mirrored window, or `nil` until a key frame establishes one.
    public func compositedFrameImage(for windowId: String) -> CGImage? {
        frameCompositor.image(for: windowId)
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
            mirrorSessions[index].compositedFrameGeneration = generation
            mirrorSessions[index].awaitingKeyFrameReason = nil
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
            mirrorSessions[index].awaitingKeyFrameReason = reason.rawValue
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
              let priorTiming = mirrorSessions[index].frameTiming else {
            return false
        }

        mirrorSessions[index].frameTiming = WindowFrameTiming(
            firstFrameReceivedAt: priorTiming.firstFrameReceivedAt,
            latestFrameReceivedAt: priorTiming.latestFrameReceivedAt,
            latestActivityAt: receivedAt,
            latestFrameIntervalMilliseconds: priorTiming.latestFrameIntervalMilliseconds,
            receivedFrameCount: priorTiming.receivedFrameCount,
            unchangedHeartbeatCount: priorTiming.unchangedHeartbeatCount + 1
        )
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

        do {
            try await service.unsubscribeWindowFrames(windowId: windowId)
            try await service.subscribeWindowFrames(windowId: windowId)
        } catch {
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

        mirrorSessions[index].captureState = .pending
        mirrorSessions[index].frameTiming = nil
        mirrorSessions[index].latestFrame = nil
        mirrorSessions[index].frameStreamRequestedAt = restartedAt
        mirrorSessions[index].frameStreamRestartCount += 1
        mirrorSessions[index].latestFrameStreamRestartedAt = restartedAt
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
              hasLiveAgentConnection else {
            return false
        }

        do {
            try await service.unsubscribeWindowFrames(windowId: windowId)
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
        mirrorSessions[index].frameStreamRequestedAt = pausedAt
        return true
    }

    /// Resubscribes a window whose stream was paused because it was not visible.
    ///
    /// Setting `frameStreamRequestedAt` here is what restarts the normal first-frame timeout, so a window that
    /// comes back and then genuinely fails to draw is still caught.
    @discardableResult
    public func resumeFrameStream(windowId: String, resumedAt: Date = Date()) async -> Bool {
        guard pausedFrameStreamWindowIds.contains(windowId),
              mirrorSessions.contains(where: { $0.id == windowId }),
              hasLiveAgentConnection else {
            return false
        }

        do {
            try await service.subscribeWindowFrames(windowId: windowId)
        } catch {
            // Left in the paused set so a later resume can try again, rather than being remembered as live
            // while no frames are coming.
            return false
        }

        guard let index = resolvedMirrorSessionIndex(for: windowId) else {
            return false
        }

        pausedFrameStreamWindowIds.remove(windowId)
        mirrorSessions[index].captureState = .pending
        mirrorSessions[index].frameStreamRequestedAt = resumedAt
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
