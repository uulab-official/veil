import AppKit
import VeilHostCore

@MainActor
enum WindowsAppFirstFrameReadiness {
    static let defaultPollInterval: Duration = .milliseconds(100)

    static func resolve(
        session: WindowMirrorSession?,
        compositedImage: CGImage?
    ) -> OneClickAppFrameReadiness {
        guard let session else {
            return .waiting
        }
        guard session.captureState != .unavailable else {
            return .unavailable
        }
        guard let frame = session.latestFrame else {
            return .waiting
        }
        if frame.isCompositedSurface {
            return compositedImage == nil ? .waiting : .ready
        }
        guard frame.format == "png",
              let payload = frame.encodedPayloadData,
              !payload.isEmpty,
              NSImage(data: payload) != nil else {
            return .waiting
        }
        return .ready
    }

    static func wait(
        timeoutSeconds: Int,
        pollInterval: Duration = defaultPollInterval,
        sessionProvider: () -> WindowMirrorSession?,
        compositedImageProvider: (String) -> CGImage?
    ) async -> OneClickAppFrameReadiness {
        let deadline = ContinuousClock.now + .seconds(max(0, timeoutSeconds))
        while true {
            let session = sessionProvider()
            let readiness = resolve(
                session: session,
                compositedImage: session.map { compositedImageProvider($0.id) } ?? nil
            )
            guard readiness == .waiting,
                  ContinuousClock.now < deadline,
                  !Task.isCancelled else {
                return readiness
            }
            try? await Task.sleep(for: pollInterval)
        }
    }
}

enum WindowsAppWindowPresentationFailure: Equatable, Sendable {
    case mirrorSessionMissing
    case captureUnavailable
    case firstFramePending
    case firstFrameTimedOut

    func userMessage(appName: String) -> String {
        switch self {
        case .mirrorSessionMissing:
            return "\(appName) opened in Windows, but its app screen closed before Veil could show it. Open \(appName) again to retry."
        case .captureUnavailable:
            return "\(appName) opened in Windows, but app screen sharing is unavailable. Open recovery to check the Windows app connection."
        case .firstFramePending:
            return "\(appName) is not ready to show its screen yet. Use Refresh App Screen to reconnect it."
        case .firstFrameTimedOut:
            return "\(appName) did not send its screen in time. Try Refresh App Screen again or open recovery to check the connection."
        }
    }
}

enum WindowsAppWindowPresentationDecision: Equatable, Sendable {
    case ready
    case blocked(WindowsAppWindowPresentationFailure)
}

@MainActor
enum WindowsAppWindowPresentationReadiness {
    static func wait(
        timeoutSeconds: Int,
        pollInterval: Duration = WindowsAppFirstFrameReadiness.defaultPollInterval,
        sessionProvider: () -> WindowMirrorSession?,
        compositedImageProvider: (String) -> CGImage?
    ) async throws -> WindowsAppWindowPresentationDecision {
        let deadline = ContinuousClock.now + .seconds(max(0, timeoutSeconds))
        while true {
            try Task.checkCancellation()
            let session = sessionProvider()
            let decision = resolve(
                session: session,
                compositedImage: session.map { compositedImageProvider($0.id) } ?? nil
            )
            guard decision == .blocked(.firstFramePending) else { return decision }
            let remaining = ContinuousClock.now.duration(to: deadline)
            guard remaining > .zero else { return .blocked(.firstFrameTimedOut) }
            try await Task.sleep(for: min(max(.milliseconds(1), pollInterval), remaining))
        }
    }

    static func resolve(
        session: WindowMirrorSession?,
        compositedImage: CGImage?
    ) -> WindowsAppWindowPresentationDecision {
        guard session != nil else {
            return .blocked(.mirrorSessionMissing)
        }

        switch WindowsAppFirstFrameReadiness.resolve(
            session: session,
            compositedImage: compositedImage
        ) {
        case .ready:
            return .ready
        case .unavailable:
            return .blocked(.captureUnavailable)
        case .waiting:
            return .blocked(.firstFramePending)
        }
    }
}

extension OneClickAppLaunchStage {
    func userMessage(appName: String) -> String {
        switch self {
        case .preparingApp: "Preparing \(appName)."
        case .startingOrResumingWindows: "Starting Windows for \(appName)."
        case .connectingAppBridge: "Connecting Windows apps for \(appName)."
        case .recoveringRuntime: "Restoring the Windows connection for \(appName)."
        case .repairingAppBridge(let attempt): "Repairing the Windows app connection for \(appName) (\(attempt)/2)."
        case .openingApp: "Opening \(appName) in Windows."
        case .waitingForFirstFrame: "Opening \(appName) screen."
        case .restartingFrameStream: "Refreshing \(appName) screen once."
        case .ready: "\(appName) is ready."
        }
    }
}
