import AppKit
import SwiftUI
import VeilHostCore

struct WindowsAppFrameSurface: View {
    var presentedSession: WindowMirrorSession
    var cornerRadius: CGFloat = 0
    var restartFrameStreamAction: ((String) -> Void)? = nil
    /// Reads the composited surface for a window from the host compositor.
    ///
    /// Injected rather than reached for directly so this view stays testable and so composited pixels are
    /// never copied into the observable session value on every frame.
    var compositedImageProvider: ((String) -> CGImage?)? = nil
    /// Reads the model's current session. A mirrored window's view is rebuilt only for frames and window
    /// updates, so the session it was handed misses `window.frame.unchanged` heartbeats; judging liveness
    /// from that copy showed an idle app as paused while its stream was healthy.
    var sessionProvider: ((String) -> WindowMirrorSession?)? = nil

    init(
        session: WindowMirrorSession,
        cornerRadius: CGFloat = 0,
        restartFrameStreamAction: ((String) -> Void)? = nil,
        compositedImageProvider: ((String) -> CGImage?)? = nil,
        sessionProvider: ((String) -> WindowMirrorSession?)? = nil
    ) {
        self.presentedSession = session
        self.cornerRadius = cornerRadius
        self.restartFrameStreamAction = restartFrameStreamAction
        self.compositedImageProvider = compositedImageProvider
        self.sessionProvider = sessionProvider
    }

    var session: WindowMirrorSession {
        sessionProvider?(presentedSession.id) ?? presentedSession
    }

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1.0)) { timeline in
            let assessment = WindowFrameStreamAssessment.assess(
                session: session,
                generatedAt: timeline.date
            )

            ZStack(alignment: .topTrailing) {
                if presentedSession.window.isPopup {
                    // A popup is an overlay: no backdrop, no status badges, and its transparent surroundings,
                    // captured as black, cleared so only the popup itself shows over its owner.
                    if let frame = session.latestFrame,
                       let popupImage = latestFrameImage.flatMap(PopupFrameTransparency.clearingBackdrop(of:)) {
                        FrameLayerView(
                            image: popupImage,
                            pointsPerPixel: WindowFrameViewport.pointsPerPixel(forWindowsScale: frame.scale),
                            backdrop: .clear
                        )
                    } else {
                        Color.clear
                    }
                } else if let latestFrameImage, let frame = session.latestFrame {
                    // Unscaled and pinned to the top-left, like a Windows window whose edge is being dragged:
                    // while the guest redraws at a new size, existing content stays put and the newly exposed
                    // area takes the app's edge color. Scaling the old bitmap to the new shape made every
                    // control and line of text swell and shrink during a resize. Input maps the same way;
                    // see `WindowFrameViewport.anchoredPointsPerPixel`.
                    FrameLayerView(
                        image: latestFrameImage,
                        pointsPerPixel: WindowFrameViewport.pointsPerPixel(forWindowsScale: frame.scale),
                        backdrop: Self.edgeColor(of: latestFrameImage)
                    )

                    frameQualityOverlay(assessment)
                        .padding(14)
                } else {
                    statusSurface(assessment)
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
            .help(frameStatusHelp(assessment))
            .accessibilityLabel(accessibilityLabel(assessment))
        }
    }

    @ViewBuilder
    private func frameQualityOverlay(_ assessment: WindowFrameStreamAssessment) -> some View {
        switch assessment.status {
        case .delayed, .stale:
            HStack(spacing: 8) {
                Image(systemName: assessment.status == .stale ? "pause.circle.fill" : "clock.badge.exclamationmark")
                    .foregroundStyle(assessment.status == .stale ? .orange : .yellow)
                Text(frameQualityTitle(assessment))
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.white)
                    .lineLimit(1)

                if assessment.status == .stale,
                   let restartFrameStreamAction {
                    Divider()
                        .frame(height: 14)
                        .overlay(.white.opacity(0.28))
                    Button {
                        restartFrameStreamAction(session.id)
                    } label: {
                        Text(frameRecoveryButtonTitle(assessment))
                            .font(.caption.weight(.semibold))
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(.white)
                    .help(frameRecoveryButtonHelp(assessment))
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .background(.black.opacity(0.66), in: Capsule())
        case .fresh, .waitingForFirstFrame, .unavailable:
            EmptyView()
        }
    }

    /// The color just inside the frame's bottom-right corner, which fills area the guest has not drawn yet.
    /// One pixel is read, so this stays cheap at frame rate.
    static func edgeColor(of image: CGImage) -> CGColor {
        guard image.width > 2,
              image.height > 2,
              let pixel = image.cropping(to: CGRect(x: image.width - 3, y: image.height - 3, width: 1, height: 1)),
              let context = CGContext(
                data: nil,
                width: 1,
                height: 1,
                bitsPerComponent: 8,
                bytesPerRow: 4,
                space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
              ) else {
            return CGColor(gray: 0, alpha: 1)
        }

        context.draw(pixel, in: CGRect(x: 0, y: 0, width: 1, height: 1))
        guard let bytes = context.data?.assumingMemoryBound(to: UInt8.self) else {
            return CGColor(gray: 0, alpha: 1)
        }
        return CGColor(
            red: CGFloat(bytes[0]) / 255,
            green: CGFloat(bytes[1]) / 255,
            blue: CGFloat(bytes[2]) / 255,
            alpha: 1
        )
    }

    /// Displayable image for this window.
    ///
    /// A composited surface takes priority: when the guest is sending dirty-rect tiles, `latestFrame`
    /// carries only metadata and the pixels live in the host compositor. Decoding `encodedData` is the
    /// fallback for the legacy JSON path, where every frame is self-contained.
    ///
    /// `session.compositedFrameGeneration` is read here purely so SwiftUI re-renders when the compositor's
    /// surface changes. Without that read the view would have no observable dependency on it.
    private var latestFrameImage: CGImage? {
        guard let frame = session.latestFrame else {
            return nil
        }

        if frame.isCompositedSurface {
            _ = session.compositedFrameGeneration
            return compositedImageProvider?(session.id)
        }

        guard frame.format == "png",
              let data = frame.encodedPayloadData else {
            return nil
        }

        return WindowFrameCompositor.decodePNG(data)
    }

    private func statusSurface(_ assessment: WindowFrameStreamAssessment) -> some View {
        ZStack {
            Color.black

            VStack(spacing: 16) {
                Image(systemName: statusSymbolName(assessment))
                    .font(.system(size: 46, weight: .semibold))
                    .foregroundStyle(statusTint(assessment))

                if assessment.status == .waitingForFirstFrame {
                    ProgressView()
                        .controlSize(.small)
                        .tint(.white.opacity(0.88))
                }

                VStack(spacing: 6) {
                    Text(statusTitle(assessment))
                        .font(.callout.weight(.semibold))
                        .foregroundStyle(.white.opacity(0.92))
                        .lineLimit(1)
                    Text(statusDetail(assessment))
                        .font(.caption)
                        .foregroundStyle(.white.opacity(0.58))
                        .multilineTextAlignment(.center)
                        .lineLimit(2)
                }
                .frame(maxWidth: 360)
            }
            .padding(24)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private func statusSymbolName(_ assessment: WindowFrameStreamAssessment) -> String {
        switch assessment.status {
        case .waitingForFirstFrame:
            return "macwindow.badge.plus"
        case .delayed, .stale:
            return "exclamationmark.triangle"
        case .fresh, .unavailable:
            return "display"
        }
    }

    private func statusTint(_ assessment: WindowFrameStreamAssessment) -> Color {
        switch assessment.status {
        case .waitingForFirstFrame:
            return .white.opacity(0.9)
        case .delayed, .stale:
            return .orange
        case .fresh, .unavailable:
            return .white.opacity(0.62)
        }
    }

    private func statusTitle(_ assessment: WindowFrameStreamAssessment) -> String {
        switch assessment.status {
        case .waitingForFirstFrame:
            return String(localized: "Opening \(session.window.title)")
        case .fresh, .delayed, .stale:
            return String(localized: "App image could not be displayed")
        case .unavailable:
            return String(localized: "App screen unavailable")
        }
    }

    private func statusDetail(_ assessment: WindowFrameStreamAssessment) -> String {
        switch assessment.status {
        case .waitingForFirstFrame:
            return String(localized: "Waiting for the Windows app screen.")
        case .fresh, .delayed, .stale:
            guard let latestFrame = session.latestFrame else {
                return String(localized: "Waiting for the next app screen update.")
            }

            return String(localized: "Received screen update \(latestFrame.sequence), but it could not be shown.")
        case .unavailable:
            if session.connectionMode == .demo {
                return String(localized: "Connect Windows to open this app as a Mac window.")
            }

            return String(localized: "Windows is connected, but app screen sharing is not available yet.")
        }
    }

    private var hasRenderableFrame: Bool {
        latestFrameImage != nil
    }

    private var hasUndisplayableFrame: Bool {
        session.latestFrame != nil && !hasRenderableFrame
    }

    private func frameQualityTitle(_ assessment: WindowFrameStreamAssessment) -> String {
        guard let ageMilliseconds = assessment.latestFrameAgeMilliseconds else {
            return String(localized: "Waiting for screen")
        }

        let seconds = max(1, Int((Double(ageMilliseconds) / 1_000.0).rounded()))
        switch assessment.status {
        case .fresh:
            return String(localized: "Live")
        case .delayed:
            return String(localized: "Screen delayed \(seconds)s")
        case .stale:
            if assessment.reopenEscalated {
                return String(localized: "App window needs reopen")
            }
            if assessment.recoveryEscalated {
                return String(localized: "Screen recovery needed")
            }
            return String(localized: "Screen paused \(seconds)s")
        case .waitingForFirstFrame:
            return String(localized: "Waiting for screen")
        case .unavailable:
            return String(localized: "Screen unavailable")
        }
    }

    private func frameQualityDetail(_ assessment: WindowFrameStreamAssessment) -> String? {
        switch assessment.status {
        case .fresh:
            guard let interval = assessment.latestFrameIntervalMilliseconds else {
                return String(localized: "Live app screen.")
            }
            return String(localized: "Live app screen, latest interval \(interval) ms.")
        case .delayed:
            return String(localized: "The latest app screen update is delayed. Refresh status if it keeps lagging.")
        case .stale:
            if assessment.reopenEscalated {
                return String(localized: "The app screen is still paused after capture recovery. Reopen this Windows app window.")
            }
            if assessment.recoveryEscalated {
                return String(localized: "The app screen is still paused after \(session.frameStreamRestartCount) restart attempts. Reopen the app window or run diagnostics.")
            }
            return String(localized: "The app screen has stopped updating. Restart the screen stream.")
        case .waitingForFirstFrame:
            return String(localized: "Waiting for the first Windows app screen.")
        case .unavailable:
            return String(localized: "App screen sharing is unavailable.")
        }
    }

    private func frameTimingSummary(_ assessment: WindowFrameStreamAssessment) -> String? {
        guard assessment.receivedFrameCount > 0 else {
            return nil
        }

        if let interval = assessment.latestFrameIntervalMilliseconds {
            return String(localized: "\(assessment.receivedFrameCount) frames, latest interval \(interval) ms")
        }

        return String(localized: "First frame received")
    }

    private func frameStatusHelp(_ assessment: WindowFrameStreamAssessment) -> String {
        [
            session.window.title,
            frameQualityDetail(assessment),
            frameTimingSummary(assessment),
            session.latestFrame.map { "Frame \($0.sequence), \($0.width)x\($0.height), \($0.format.uppercased())" }
        ]
        .compactMap { $0 }
        .joined(separator: "\n")
    }

    private func frameRecoveryButtonTitle(_ assessment: WindowFrameStreamAssessment) -> String {
        if assessment.reopenEscalated {
            return String(localized: "Reopen")
        }

        return assessment.recoveryEscalated ? String(localized: "Recover") : String(localized: "Restart")
    }

    private func frameRecoveryButtonHelp(_ assessment: WindowFrameStreamAssessment) -> String {
        if assessment.reopenEscalated {
            return String(localized: "Close and reopen this Windows app window.")
        }

        return assessment.recoveryEscalated
            ? String(localized: "Recover this app screen stream.")
            : String(localized: "Restart this app screen stream.")
    }

    private func accessibilityLabel(_ assessment: WindowFrameStreamAssessment) -> String {
        if session.captureState == .unavailable {
            return String(localized: "\(session.window.title) app screen unavailable")
        }

        if hasUndisplayableFrame {
            return String(localized: "\(session.window.title) app image could not be displayed")
        }

        if session.latestFrame == nil {
            return String(localized: "Waiting for \(session.window.title) app screen")
        }

        if let frameTimingSummary = frameTimingSummary(assessment) {
            return String(localized: "\(session.window.title) Windows app screen, \(assessment.status.rawValue), \(frameTimingSummary)")
        }

        return String(localized: "\(session.window.title) Windows app screen")
    }
}
