import CoreGraphics
import Foundation
import Observation

public enum WindowCaptureState: String, Codable, Equatable, Sendable {
    case unavailable
    case pending
    case streaming
}

public enum WindowFrameStreamStatus: String, Codable, Equatable, Sendable {
    case unavailable
    case waitingForFirstFrame
    case fresh
    case delayed
    case stale
}

public struct WindowFrameTiming: Codable, Equatable, Sendable {
    public var firstFrameReceivedAt: Date
    /// When the currently displayed image arrived.
    ///
    /// Deliberately *not* advanced by an unchanged-frame heartbeat: the proof artifacts and the
    /// frame-latency budget both mean "how old is the picture on screen", and a liveness ping does not
    /// make the picture newer.
    public var latestFrameReceivedAt: Date
    /// When the guest last proved this stream is alive, whether or not it had anything new to draw.
    ///
    /// Freshness is derived from this instead of `latestFrameReceivedAt`, which is what lets the guest
    /// stop re-encoding identical pixels. Without the split, an idle window would be marked stale and
    /// escalated into subscription restart, capture recovery, and app reopen.
    public var latestActivityAt: Date
    public var latestFrameIntervalMilliseconds: Int?
    public var receivedFrameCount: Int
    /// Heartbeats received since this stream started. A high count next to a low `receivedFrameCount`
    /// is a healthy idle window, not a degraded one.
    public var unchangedHeartbeatCount: Int

    public init(
        firstFrameReceivedAt: Date,
        latestFrameReceivedAt: Date,
        latestActivityAt: Date? = nil,
        latestFrameIntervalMilliseconds: Int? = nil,
        receivedFrameCount: Int = 1,
        unchangedHeartbeatCount: Int = 0
    ) {
        self.firstFrameReceivedAt = firstFrameReceivedAt
        self.latestFrameReceivedAt = latestFrameReceivedAt
        // Defaults to the frame time so a guest that never sends heartbeats behaves exactly as before.
        self.latestActivityAt = latestActivityAt ?? latestFrameReceivedAt
        self.latestFrameIntervalMilliseconds = latestFrameIntervalMilliseconds
        self.receivedFrameCount = receivedFrameCount
        self.unchangedHeartbeatCount = unchangedHeartbeatCount
    }
}

public struct WindowFrameStreamAssessment: Equatable, Sendable {
    public static let freshFrameAgeThresholdMilliseconds = 1_000
    public static let delayedFrameAgeThresholdMilliseconds = 5_000
    public static let firstFrameTimeoutThresholdMilliseconds = 8_000
    public static let recoveryEscalationRestartThreshold = 2
    public static let reopenEscalationRestartThreshold = 3

    public var status: WindowFrameStreamStatus
    public var latestFrameAgeMilliseconds: Int?
    /// Age of the last liveness signal, frame or heartbeat. This is what `status` is derived from.
    public var latestActivityAgeMilliseconds: Int?
    public var latestFrameIntervalMilliseconds: Int?
    public var waitingForFirstFrameMilliseconds: Int?
    public var receivedFrameCount: Int
    public var unchangedHeartbeatCount: Int
    public var recommendedAction: String
    public var recoveryEscalated: Bool
    public var reopenEscalated: Bool

    public init(
        status: WindowFrameStreamStatus,
        latestFrameAgeMilliseconds: Int? = nil,
        latestActivityAgeMilliseconds: Int? = nil,
        latestFrameIntervalMilliseconds: Int? = nil,
        waitingForFirstFrameMilliseconds: Int? = nil,
        receivedFrameCount: Int = 0,
        unchangedHeartbeatCount: Int = 0,
        recommendedAction: String,
        recoveryEscalated: Bool = false,
        reopenEscalated: Bool = false
    ) {
        self.status = status
        self.latestFrameAgeMilliseconds = latestFrameAgeMilliseconds
        self.latestActivityAgeMilliseconds = latestActivityAgeMilliseconds ?? latestFrameAgeMilliseconds
        self.latestFrameIntervalMilliseconds = latestFrameIntervalMilliseconds
        self.waitingForFirstFrameMilliseconds = waitingForFirstFrameMilliseconds
        self.receivedFrameCount = receivedFrameCount
        self.unchangedHeartbeatCount = unchangedHeartbeatCount
        self.recommendedAction = recommendedAction
        self.recoveryEscalated = recoveryEscalated
        self.reopenEscalated = reopenEscalated
    }

    public static func assess(
        session: WindowMirrorSession,
        generatedAt: Date = Date()
    ) -> WindowFrameStreamAssessment {
        guard session.captureState != .unavailable else {
            return WindowFrameStreamAssessment(
                status: .unavailable,
                recommendedAction: "enable-window-capture"
            )
        }

        guard let timing = session.frameTiming else {
            let waitingMilliseconds = session.frameStreamRequestedAt.map {
                max(0, Int((generatedAt.timeIntervalSince($0) * 1000).rounded()))
            }
            if let waitingMilliseconds,
               waitingMilliseconds >= firstFrameTimeoutThresholdMilliseconds {
                let reopenEscalated = session.frameStreamRestartCount >= reopenEscalationRestartThreshold
                let recoveryEscalated = !reopenEscalated
                    && session.frameStreamRestartCount >= recoveryEscalationRestartThreshold
                let recommendedAction: String
                if reopenEscalated {
                    recommendedAction = "reopen-windows-app"
                } else {
                    recommendedAction = recoveryEscalated
                        ? "recover-window-capture"
                        : "restart-frame-subscription"
                }

                return WindowFrameStreamAssessment(
                    status: .stale,
                    waitingForFirstFrameMilliseconds: waitingMilliseconds,
                    recommendedAction: recommendedAction,
                    recoveryEscalated: recoveryEscalated,
                    reopenEscalated: reopenEscalated
                )
            }

            return WindowFrameStreamAssessment(
                status: .waitingForFirstFrame,
                waitingForFirstFrameMilliseconds: waitingMilliseconds,
                recommendedAction: "wait-for-first-frame"
            )
        }

        let ageMilliseconds = max(
            0,
            Int((generatedAt.timeIntervalSince(timing.latestFrameReceivedAt) * 1000).rounded())
        )
        // Freshness follows liveness, not the age of the picture. A window nobody is touching has an
        // old image and a healthy stream at the same time, and conflating those forced the guest to
        // re-encode identical pixels forever just to look alive.
        let activityAgeMilliseconds = max(
            0,
            Int((generatedAt.timeIntervalSince(timing.latestActivityAt) * 1000).rounded())
        )
        let status: WindowFrameStreamStatus
        let recommendedAction: String
        let recoveryEscalated: Bool
        let reopenEscalated: Bool

        if activityAgeMilliseconds <= freshFrameAgeThresholdMilliseconds {
            status = .fresh
            recommendedAction = "none"
            recoveryEscalated = false
            reopenEscalated = false
        } else if activityAgeMilliseconds <= delayedFrameAgeThresholdMilliseconds {
            status = .delayed
            recommendedAction = "refresh-runtime-status"
            recoveryEscalated = false
            reopenEscalated = false
        } else {
            status = .stale
            reopenEscalated = session.frameStreamRestartCount >= reopenEscalationRestartThreshold
            recoveryEscalated = !reopenEscalated
                && session.frameStreamRestartCount >= recoveryEscalationRestartThreshold
            if reopenEscalated {
                recommendedAction = "reopen-windows-app"
            } else {
                recommendedAction = recoveryEscalated ? "recover-window-capture" : "restart-frame-subscription"
            }
        }

        return WindowFrameStreamAssessment(
            status: status,
            latestFrameAgeMilliseconds: ageMilliseconds,
            latestActivityAgeMilliseconds: activityAgeMilliseconds,
            latestFrameIntervalMilliseconds: timing.latestFrameIntervalMilliseconds,
            receivedFrameCount: timing.receivedFrameCount,
            unchangedHeartbeatCount: timing.unchangedHeartbeatCount,
            recommendedAction: recommendedAction,
            recoveryEscalated: recoveryEscalated,
            reopenEscalated: reopenEscalated
        )
    }
}

public struct WindowMirrorSession: Codable, Equatable, Identifiable, Sendable {
    public var id: String { window.windowId }
    public var window: WindowCreatedEvent
    public var connectionMode: HostConnectionMode
    public var captureState: WindowCaptureState
    public var latestFrame: WindowFrameEvent?
    public var frameTiming: WindowFrameTiming?
    public var frameStreamRequestedAt: Date?
    public var frameStreamRestartCount: Int
    public var latestFrameStreamRestartedAt: Date?
    /// Increments whenever the compositor's surface for this window changes.
    ///
    /// Exists so a SwiftUI view can re-render from the compositor without the composited pixels being
    /// copied into this value type on every frame. `latestFrame` carries only metadata for composited
    /// windows; the displayable image lives in `WindowFrameCompositor`.
    public var compositedFrameGeneration: Int
    /// Set when a tile arrived that could not be composited, so the surface is waiting for a key frame.
    public var awaitingKeyFrameReason: String?

    public init(
        window: WindowCreatedEvent,
        connectionMode: HostConnectionMode,
        captureState: WindowCaptureState,
        latestFrame: WindowFrameEvent? = nil,
        frameTiming: WindowFrameTiming? = nil,
        frameStreamRequestedAt: Date? = nil,
        frameStreamRestartCount: Int = 0,
        latestFrameStreamRestartedAt: Date? = nil,
        compositedFrameGeneration: Int = 0,
        awaitingKeyFrameReason: String? = nil
    ) {
        self.window = window
        self.connectionMode = connectionMode
        self.captureState = captureState
        self.latestFrame = latestFrame
        self.frameTiming = frameTiming
        self.frameStreamRequestedAt = frameStreamRequestedAt
        self.frameStreamRestartCount = frameStreamRestartCount
        self.latestFrameStreamRestartedAt = latestFrameStreamRestartedAt
        self.compositedFrameGeneration = compositedFrameGeneration
        self.awaitingKeyFrameReason = awaitingKeyFrameReason
    }
}

public enum HostDashboardPhase: String, Codable, Equatable, Sendable {
    case idle
    case loading
    case connected
    case launching
    case failed
    /// Distinct from `.failed`: the guest-agent connection just dropped and the background retry
    /// loop (`consumeProtocolMessages`'s caller) is actively attempting to recover, not stuck.
    /// `.failed` remains reserved for a user-triggered action that failed outright.
    case reconnecting
}

/// What happened to a host-to-guest clipboard write.
///
/// Exists because the caller has to decide whether to follow it with a paste shortcut. Sending Ctrl+V after
/// a clipboard write that never arrived does not fail — it pastes whatever Windows had before, into the
/// user's document, with no indication anything went wrong.
public enum HostClipboardSendOutcome: Equatable, Sendable {
    case sent
    /// Nothing was sent and nothing was expected to be, because this connection has no clipboard capability.
    /// A paste may still proceed: the guest's clipboard is untouched and may hold exactly what the user
    /// copied inside Windows.
    case skipped
    /// The clipboard write could not be delivered. A paste now would use stale content.
    case failed(reason: String)
}

public enum HostProtocolMessageResult: Equatable, Sendable {
    case handledWindowCreated(windowId: String)
    case handledWindowUpdated(windowId: String)
    case handledWindowFrame(windowId: String)
    case handledWindowFrameUnchanged(windowId: String)
    case handledWindowClosed(windowId: String)
    case handledClipboardText(sequence: Int)
    case handledClipboardImage(sequence: Int)
    case handledWindowsNotification(notificationId: String)
    case ignored
}
