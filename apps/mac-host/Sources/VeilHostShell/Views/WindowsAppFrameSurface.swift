import AppKit
import SwiftUI
import VeilHostCore

struct WindowsAppFrameSurface: View {
    var session: WindowMirrorSession
    var cornerRadius: CGFloat = 0

    var body: some View {
        ZStack {
            if let latestFrameImage {
                Color.black
                    .overlay {
                        Image(nsImage: latestFrameImage)
                            .interpolation(.high)
                            .resizable()
                            .scaledToFit()
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                    }
            } else {
                statusSurface
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
        .help(frameStatusHelp)
        .accessibilityLabel(accessibilityLabel)
    }

    private var latestFrameImage: NSImage? {
        guard let frame = session.latestFrame,
              frame.format == "png",
              let data = frame.encodedPayloadData else {
            return nil
        }

        return NSImage(data: data)
    }

    private var statusSurface: some View {
        ZStack {
            Color.black

            VStack(spacing: 16) {
                Image(systemName: statusSymbolName)
                    .font(.system(size: 46, weight: .semibold))
                    .foregroundStyle(statusTint)

                if session.captureState == .pending {
                    ProgressView()
                        .controlSize(.small)
                        .tint(.white.opacity(0.88))
                }

                VStack(spacing: 6) {
                    Text(statusTitle)
                        .font(.callout.weight(.semibold))
                        .foregroundStyle(.white.opacity(0.92))
                        .lineLimit(1)
                    Text(statusDetail)
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

    private var statusSymbolName: String {
        switch session.captureState {
        case .pending:
            return "macwindow.badge.plus"
        case .streaming:
            return "exclamationmark.triangle"
        case .unavailable:
            return "display"
        }
    }

    private var statusTint: Color {
        switch session.captureState {
        case .pending:
            return .white.opacity(0.9)
        case .streaming:
            return .orange
        case .unavailable:
            return .white.opacity(0.62)
        }
    }

    private var statusTitle: String {
        switch session.captureState {
        case .pending:
            return "Opening \(session.window.title)"
        case .streaming:
            return "App image could not be displayed"
        case .unavailable:
            return "App screen unavailable"
        }
    }

    private var statusDetail: String {
        switch session.captureState {
        case .pending:
            return "Waiting for the Windows app screen."
        case .streaming:
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

    private var frameTimingSummary: String? {
        guard let timing = session.frameTiming else {
            return nil
        }

        if let interval = timing.latestFrameIntervalMilliseconds {
            return "\(timing.receivedFrameCount) frames, latest interval \(interval) ms"
        }

        return "First frame received"
    }

    private var frameStatusHelp: String {
        [
            session.window.title,
            frameTimingSummary,
            session.latestFrame.map { "Frame \($0.sequence), \($0.width)x\($0.height), \($0.format.uppercased())" }
        ]
        .compactMap { $0 }
        .joined(separator: "\n")
    }

    private var accessibilityLabel: String {
        if session.captureState == .unavailable {
            return "\(session.window.title) app screen unavailable"
        }

        if hasUndisplayableFrame {
            return "\(session.window.title) app image could not be displayed"
        }

        if session.latestFrame == nil {
            return "Waiting for \(session.window.title) app screen"
        }

        if let frameTimingSummary {
            return "\(session.window.title) Windows app screen, \(frameTimingSummary)"
        }

        return "\(session.window.title) Windows app screen"
    }
}
