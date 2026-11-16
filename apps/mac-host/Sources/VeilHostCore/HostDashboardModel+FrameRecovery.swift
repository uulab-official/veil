import CoreGraphics
import Foundation
import Observation

extension HostDashboardModel {
    /// Clamps a guest-reported window so its numbers and strings are safe to hand to AppKit.
    ///
    /// `WindowsAppWindowPlacement.initialFrame` already clamps bounds to the visible screen, but the clamping
    /// was never extended to `contentMinSize` and `contentAspectRatio`, which are set from the raw values on
    /// every `window.updated`. Bounds of `1 x 2000000000` handed AppKit a two-billion-point minimum size and a
    /// degenerate resize ratio.
    ///
    /// Clamped at ingest rather than at each consumer, so a future consumer cannot reintroduce the problem by
    /// reading `bounds` directly.
    nonisolated static func sanitizedGuestWindow(_ event: WindowCreatedEvent) -> WindowCreatedEvent {
        var sanitized = event
        sanitized.bounds = WindowBounds(
            x: event.bounds.x,
            y: event.bounds.y,
            width: clampedWindowExtent(event.bounds.width),
            height: clampedWindowExtent(event.bounds.height)
        )
        sanitized.title = sanitizedWindowTitle(event.title)
        return sanitized
    }

    /// Bounds a logical window extent to something a display can express.
    ///
    /// Shares the frame channel's per-axis ceiling so one number describes "the largest window Veil will deal
    /// with" rather than two that can drift.
    nonisolated static func clampedWindowExtent(_ extent: Int) -> Int {
        min(max(extent, 0), VeilFrameChannelCodec.maximumSurfaceDimension)
    }

    /// Truncates a window title and removes characters that break the surfaces it is displayed on.
    ///
    /// Newlines in particular: a title is drawn on one line in a titlebar and a menu item, so an embedded
    /// newline is a rendering defect rather than content.
    nonisolated static func sanitizedWindowTitle(_ title: String) -> String {
        let singleLine = String(
            title.map { character -> Character in
                if character.isNewline {
                    return " "
                }
                // Checked by scalar value with an explicit single-scalar guard, so a flag or skin-tone
                // sequence is never mistaken for a control character.
                if character.unicodeScalars.count == 1,
                   let scalar = character.unicodeScalars.first,
                   scalar.value < 32 {
                    return " "
                }
                return character
            }
        )
        guard singleLine.count > maximumWindowTitleLength else {
            return singleLine
        }
        // Truncated by Character so a grapheme cluster is never split, matching how dropped file names are
        // shortened.
        return String(singleLine.prefix(maximumWindowTitleLength))
    }

    /// Whether a guest-reported DPI scale is usable as a divisor.
    ///
    /// Windows display scaling runs from 100% to 500%, so anything outside `0.5...8` is not a scale the guest
    /// could legitimately be rendering at. The bound matters less for plausibility than for arithmetic: a
    /// denormal divisor produces an infinite ratio, and a non-finite `Double` cannot be JSON-encoded.
    /// `nonisolated` because it is pure arithmetic on its argument. Without it, a rule about guest data would
    /// be reachable only from the main actor, which is a property of the enclosing model rather than of the
    /// rule.
    nonisolated static func isPlausibleDisplayScale(_ scale: Double) -> Bool {
        scale.isFinite && scale >= 0.5 && scale <= 8
    }

    /// Whether a guest-declared frame size is small enough to store and eventually draw.
    ///
    /// Shares the binary frame channel's ceilings so the two delivery paths cannot disagree about what is
    /// acceptable. Bounding each axis alone is not enough: 32768 on both axes is a 4 GiB bitmap, and a 1-bit
    /// PNG of those dimensions deflates small enough to fit in one WebSocket message.
    nonisolated static func isPlausibleFrameSize(width: Int, height: Int) -> Bool {
        width > 0
            && height > 0
            && width <= VeilFrameChannelCodec.maximumSurfaceDimension
            && height <= VeilFrameChannelCodec.maximumSurfaceDimension
            && width * height <= VeilFrameChannelCodec.maximumSurfacePixelCount
    }

    /// Re-resolves a mirror session index after an `await`.
    ///
    /// `mirrorSessions` is main-actor state, which makes it tempting to capture an index once and reuse it
    /// across suspension points. An `await` still yields, though, and a `window.closed` arriving in that gap
    /// removes the session — so an index captured beforehand can be out of bounds by the time it is used,
    /// which crashes rather than producing a wrong value. A reorder is quieter and worse: it would apply the
    /// mutation to a different window.
    func resolvedMirrorSessionIndex(for windowId: String) -> Int? {
        mirrorSessions.firstIndex(where: { $0.id == windowId })
    }

    @discardableResult
    public func restartStaleFrameSubscriptions(generatedAt: Date = Date()) async -> [String] {
        let staleWindowIds = mirrorSessions
            .filter {
                // A paused window has no frames arriving because Veil asked for none. Restarting it would
                // resubscribe a window the user minimized, and each attempt raises `frameStreamRestartCount`
                // until the ladder offers to reopen an app that was never broken.
                !pausedFrameStreamWindowIds.contains($0.id)
                    && WindowFrameStreamAssessment.assess(
                        session: $0,
                        generatedAt: generatedAt
                    ).status == .stale
            }
            .map(\.id)
        var restartedWindowIds: [String] = []

        for windowId in staleWindowIds {
            if await restartFrameSubscription(windowId: windowId, restartedAt: generatedAt) {
                restartedWindowIds.append(windowId)
            }
        }

        return restartedWindowIds
    }

    @discardableResult
    public func recoverFrameCapture(windowId: String, recoveredAt: Date = Date()) async -> Bool {
        guard let startingIndex = mirrorSessions.firstIndex(where: { $0.id == windowId }),
              mirrorSessions[startingIndex].captureState != .unavailable,
              hasLiveAgentConnection else {
            return false
        }

        do {
            try Task.checkCancellation()
            let focus = try await service.focusWindow(windowId: windowId)
            try Task.checkCancellation()
            guard focus.accepted, resolvedMirrorSessionIndex(for: windowId) != nil else {
                return false
            }
            markFocusedWindow(windowId: windowId)

            // Strong recovery differs only by guest focus. Share the cancellation,
            // close handling, and pre-subscribe reset with an ordinary restart.
            return await restartFrameSubscription(windowId: windowId, restartedAt: recoveredAt)
        } catch {
            if await dropMirrorSessionIfUntracked(windowId: windowId, error: error) {
                return false
            }
            // Also reached from `recoverEscalatedFrameCaptures`, which runs automatically. `.failed` renders
            // as "Connection failed", so a recovery attempt that did not take must not report the Windows
            // connection as down — the caller retries on the next pass.
            errorMessage = userMessage(for: error)
            return false
        }
    }

    @discardableResult
    public func recoverEscalatedFrameCaptures(generatedAt: Date = Date()) async -> [String] {
        let escalatedWindowIds = mirrorSessions
            .filter {
                // Same reason as `restartStaleFrameSubscriptions`: a paused window is quiet on purpose, and
                // recovering it would focus and resubscribe a window the user deliberately minimized.
                !pausedFrameStreamWindowIds.contains($0.id)
                    && WindowFrameStreamAssessment.assess(
                        session: $0,
                        generatedAt: generatedAt
                    ).recoveryEscalated
            }
            .map(\.id)
        var recoveredWindowIds: [String] = []

        for windowId in escalatedWindowIds {
            if await recoverFrameCapture(windowId: windowId, recoveredAt: generatedAt) {
                recoveredWindowIds.append(windowId)
            }
        }

        return recoveredWindowIds
    }

    @discardableResult
    public func reopenAppWindow(windowId: String) async -> WindowsAppReopenResult? {
        guard let session = mirrorSessions.first(where: { $0.id == windowId }),
              hasLiveAgentConnection else {
            return nil
        }

        let appId = session.window.appId
        guard let close = await closeMirrorSession(windowId: windowId),
              close.accepted,
              let launch = await launchApp(appId: appId) else {
            return nil
        }

        return WindowsAppReopenResult(
            requestedWindowId: windowId,
            close: close,
            launch: launch
        )
    }

    @discardableResult
    public func reopenEscalatedAppWindows(generatedAt: Date = Date()) async -> [WindowsAppReopenResult] {
        let escalatedWindowIds = mirrorSessions
            .filter {
                WindowFrameStreamAssessment.assess(
                    session: $0,
                    generatedAt: generatedAt
                ).reopenEscalated
            }
            .map(\.id)
        var reopenedWindows: [WindowsAppReopenResult] = []

        for windowId in escalatedWindowIds {
            if let result = await reopenAppWindow(windowId: windowId) {
                reopenedWindows.append(result)
            }
        }

        return reopenedWindows
    }

    @discardableResult
    /// - Parameter reopensWindows: Whether maintenance may act on the Windows windows themselves: focus a
    ///   window to recover its capture, or close it and start its app again. Only for a request from the
    ///   person. Maintenance that runs by itself only restarts the frame subscription. Closing a window can
    ///   discard unsaved work, and a window that another window covers looked stale and was closed and
    ///   reopened every few seconds. Focusing is no better: a covered window, such as Paint's formatting
    ///   bar, was brought to the front in Windows again and again, which pushed an app that had just been
    ///   opened behind it before its first picture could be taken.
    public func maintainStaleFrameStreams(
        generatedAt: Date = Date(),
        reopensWindows: Bool = true
    ) async -> WindowsAppFrameStreamMaintenanceResult {
        let assessments = mirrorSessions.map {
            (
                windowId: $0.id,
                assessment: WindowFrameStreamAssessment.assess(session: $0, generatedAt: generatedAt)
            )
        }
        let reopenWindowIds = reopensWindows
            ? assessments.filter { $0.assessment.reopenEscalated }.map(\.windowId)
            : []
        let recoverWindowIds = reopensWindows
            ? assessments.filter { $0.assessment.recoveryEscalated }.map(\.windowId)
            : []
        let restartWindowIds = assessments
            .filter {
                $0.assessment.status == .stale
                    && (!reopensWindows || (!$0.assessment.recoveryEscalated && !$0.assessment.reopenEscalated))
            }
            .map(\.windowId)

        var result = WindowsAppFrameStreamMaintenanceResult()

        for windowId in reopenWindowIds {
            if let reopened = await reopenAppWindow(windowId: windowId) {
                result.reopenedWindows.append(reopened)
            }
        }

        for windowId in recoverWindowIds {
            if await recoverFrameCapture(windowId: windowId, recoveredAt: generatedAt) {
                result.recoveredFrameWindowIds.append(windowId)
            }
        }

        for windowId in restartWindowIds {
            if await restartFrameSubscription(windowId: windowId, restartedAt: generatedAt) {
                result.restartedFrameWindowIds.append(windowId)
            }
        }

        return result
    }
}
