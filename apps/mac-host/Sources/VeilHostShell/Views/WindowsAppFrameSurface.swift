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
                pendingSurface
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
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

    private var pendingSurface: some View {
        ZStack {
            Color(nsColor: .textBackgroundColor)

            VStack(spacing: 14) {
                Image(systemName: "note.text")
                    .font(.system(size: 42, weight: .semibold))
                    .foregroundStyle(.secondary)
                ProgressView()
                    .controlSize(.small)
                Text("Opening \(session.window.title)")
                    .font(.callout.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private var accessibilityLabel: String {
        if session.latestFrame == nil {
            return "Waiting for \(session.window.title) frame"
        }

        return "\(session.window.title) mirrored Windows app frame"
    }
}
