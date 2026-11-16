import AppKit
import SwiftUI
import UniformTypeIdentifiers
import VeilHostCore
import Virtualization

struct RuntimeLandingPanel: View {
    var title: String
    var subtitle: String
    var primaryTitle: String
    var primarySymbol: String
    var secondaryTitle: String
    var primaryAction: () -> Void
    var secondaryAction: () -> Void

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [
                            Color(red: 0.02, green: 0.32, blue: 0.62),
                            Color(red: 0.06, green: 0.10, blue: 0.18)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )

            WindowsDisplayGrid()
                .opacity(0.16)

            VStack(spacing: 18) {
                WindowsLogoMark(size: 86)
                    .shadow(color: .black.opacity(0.22), radius: 18, y: 10)

                VStack(spacing: 6) {
                    Text(localized: title)
                        .font(.system(size: 38, weight: .semibold))
                    Text(localized: subtitle)
                        .font(.callout)
                        .foregroundStyle(.white.opacity(0.75))
                        .multilineTextAlignment(.center)
                        .lineLimit(2)
                }

                HStack(spacing: 10) {
                    Button(action: primaryAction) {
                        Label(LocalizedStringKey(primaryTitle), systemImage: primarySymbol)
                            .frame(minWidth: 150)
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)

                    Button(action: secondaryAction) {
                        Label(LocalizedStringKey(secondaryTitle), systemImage: secondaryTitle == "Refresh" ? "arrow.clockwise" : "wand.and.stars")
                    }
                    .controlSize(.large)
                }
            }
            .foregroundStyle(.white)
            .padding(32)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .overlay {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .strokeBorder(.white.opacity(0.16), lineWidth: 1)
        }
    }
}
