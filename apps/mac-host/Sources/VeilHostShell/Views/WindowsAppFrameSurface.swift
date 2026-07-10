import AppKit
import SwiftUI
import VeilHostCore

struct WindowsAppFrameSurface: View {
    var session: WindowMirrorSession
    var cornerRadius: CGFloat = 0
    var restartFrameStreamAction: ((String) -> Void)? = nil

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1.0)) { timeline in
            let assessment = WindowFrameStreamAssessment.assess(
                session: session,
                generatedAt: timeline.date
            )

            ZStack(alignment: .topTrailing) {
                if let latestFrameImage {
                    Color.black
                        .overlay {
                            Image(nsImage: latestFrameImage)
                                .interpolation(.high)
                                .resizable()
                                .scaledToFit()
                                .frame(maxWidth: .infinity, maxHeight: .infinity)
                        }

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
                        Text("Restart")
                            .font(.caption.weight(.semibold))
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(.white)
                    .help("Restart this app screen stream.")
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .background(.black.opacity(0.66), in: Capsule())
        case .fresh, .waitingForFirstFrame, .unavailable:
            EmptyView()
        }
    }

    private var latestFrameImage: NSImage? {
        guard let frame = session.latestFrame,
              frame.format == "png",
              let data = frame.encodedPayloadData else {
            return nil
        }

        return NSImage(data: data)
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
            return "Opening \(session.window.title)"
        case .fresh, .delayed, .stale:
            return "App image could not be displayed"
        case .unavailable:
            return "App screen unavailable"
        }
    }

    private func statusDetail(_ assessment: WindowFrameStreamAssessment) -> String {
        switch assessment.status {
        case .waitingForFirstFrame:
            return "Waiting for the Windows app screen."
        case .fresh, .delayed, .stale:
            guard let latestFrame = session.latestFrame else {
                return "Waiting for the next app screen update."
            }

            return "Received screen update \(latestFrame.sequence), but it could not be shown."
        case .unavailable:
            if session.connectionMode == .demo {
                return "Connect Windows to open this app as a Mac window."
            }

            return "Windows is connected, but app screen sharing is not available yet."
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
            return "Waiting for screen"
        }

        let seconds = max(1, Int((Double(ageMilliseconds) / 1_000.0).rounded()))
        switch assessment.status {
        case .fresh:
            return "Live"
        case .delayed:
            return "Screen delayed \(seconds)s"
        case .stale:
            if assessment.recoveryEscalated {
                return "Screen recovery needed"
            }
            return "Screen paused \(seconds)s"
        case .waitingForFirstFrame:
            return "Waiting for screen"
        case .unavailable:
            return "Screen unavailable"
        }
    }

    private func frameQualityDetail(_ assessment: WindowFrameStreamAssessment) -> String? {
        switch assessment.status {
        case .fresh:
            guard let interval = assessment.latestFrameIntervalMilliseconds else {
                return "Live app screen."
            }
            return "Live app screen, latest interval \(interval) ms."
        case .delayed:
            return "The latest app screen update is delayed. Refresh status if it keeps lagging."
        case .stale:
            if assessment.recoveryEscalated {
                return "The app screen is still paused after \(session.frameStreamRestartCount) restart attempts. Reopen the app window or run diagnostics."
            }
            return "The app screen has stopped updating. Restart the screen stream."
        case .waitingForFirstFrame:
            return "Waiting for the first Windows app screen."
        case .unavailable:
            return "App screen sharing is unavailable."
        }
    }

    private func frameTimingSummary(_ assessment: WindowFrameStreamAssessment) -> String? {
        guard assessment.receivedFrameCount > 0 else {
            return nil
        }

        if let interval = assessment.latestFrameIntervalMilliseconds {
            return "\(assessment.receivedFrameCount) frames, latest interval \(interval) ms"
        }

        return "First frame received"
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

    private func accessibilityLabel(_ assessment: WindowFrameStreamAssessment) -> String {
        if session.captureState == .unavailable {
            return "\(session.window.title) app screen unavailable"
        }

        if hasUndisplayableFrame {
            return "\(session.window.title) app image could not be displayed"
        }

        if session.latestFrame == nil {
            return "Waiting for \(session.window.title) app screen"
        }

        if let frameTimingSummary = frameTimingSummary(assessment) {
            return "\(session.window.title) Windows app screen, \(assessment.status.rawValue), \(frameTimingSummary)"
        }

        return "\(session.window.title) Windows app screen"
    }
}
