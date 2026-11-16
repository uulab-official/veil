import AppKit
import SwiftUI
import UniformTypeIdentifiers
import VeilHostCore
import Virtualization

struct WindowsLogoMark: View {
    var size: CGFloat

    var body: some View {
        Grid(horizontalSpacing: 3, verticalSpacing: 3) {
            GridRow {
                Rectangle().fill(Color(red: 0.03, green: 0.47, blue: 0.95))
                Rectangle().fill(Color(red: 0.03, green: 0.47, blue: 0.95))
            }
            GridRow {
                Rectangle().fill(Color(red: 0.03, green: 0.47, blue: 0.95))
                Rectangle().fill(Color(red: 0.03, green: 0.47, blue: 0.95))
            }
        }
        .frame(width: size, height: size)
        .clipShape(RoundedRectangle(cornerRadius: 5, style: .continuous))
        .accessibilityHidden(true)
    }
}

struct WindowsDisplayGrid: View {
    var body: some View {
        GeometryReader { proxy in
            Path { path in
                let spacing: CGFloat = 42
                var x: CGFloat = spacing
                while x < proxy.size.width {
                    path.move(to: CGPoint(x: x, y: 0))
                    path.addLine(to: CGPoint(x: x, y: proxy.size.height))
                    x += spacing
                }

                var y: CGFloat = spacing
                while y < proxy.size.height {
                    path.move(to: CGPoint(x: 0, y: y))
                    path.addLine(to: CGPoint(x: proxy.size.width, y: y))
                    y += spacing
                }
            }
            .stroke(.white.opacity(0.45), lineWidth: 1)
        }
        .allowsHitTesting(false)
    }
}

struct AssistantProgressStrip: View {
    var simulation: InstallSimulationState

    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack {
                Label(simulation.currentStep, systemImage: "arrow.triangle.2.circlepath")
                    .font(.callout.weight(.semibold))
                Spacer()
                Text("\(Int(simulation.progress * 100))%")
                    .font(.caption.monospacedDigit().weight(.semibold))
                    .foregroundStyle(.secondary)
            }

            ProgressView(value: simulation.progress)
                .tint(.blue)
        }
        .padding(12)
        .background(.blue.opacity(0.08), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
    }
}

struct AppRuntimeProgressStrip: View {
    var items: [InstallFlowItem]

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            ForEach(items) { item in
                HStack(spacing: 7) {
                    Image(systemName: item.symbolName)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(tint(for: item.state))
                        .frame(width: 22, height: 22)
                        .background(tint(for: item.state).opacity(0.16), in: Circle())

                    VStack(alignment: .leading, spacing: 1) {
                        Text(localized: item.title)
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(.white.opacity(0.62))
                        Text(localized: item.detail)
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.white.opacity(0.88))
                            // Two lines instead of middle truncation: "Create a lo…VM profile"
                            // hid the one word that told the user what the step was.
                            .lineLimit(2)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .frame(minWidth: 0, maxWidth: .infinity, alignment: .leading)
                }
                .padding(.horizontal, 9)
                .padding(.vertical, 8)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
                .background(.white.opacity(backgroundOpacity(for: item.state)), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .strokeBorder(.white.opacity(0.12), lineWidth: 1)
                }
            }
        }
        .fixedSize(horizontal: false, vertical: true)
    }

    private func tint(for state: InstallFlowState) -> Color {
        switch state {
        case .complete:
            return .green
        case .current:
            return .blue
        case .pending:
            return .white.opacity(0.58)
        }
    }

    private func backgroundOpacity(for state: InstallFlowState) -> Double {
        switch state {
        case .complete:
            return 0.14
        case .current:
            return 0.18
        case .pending:
            return 0.08
        }
    }
}

struct RuntimeReadinessTimeline: View {
    var steps: [WindowsRuntimeReadinessStep]

    var body: some View {
        LazyVGrid(
            columns: [GridItem(.adaptive(minimum: 150), spacing: 7)],
            alignment: .leading,
            spacing: 7
        ) {
            ForEach(steps) { step in
                HStack(spacing: 7) {
                    Image(systemName: step.symbolName)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(tint(for: step.state))
                        .frame(width: 22, height: 22)
                        .background(tint(for: step.state).opacity(0.16), in: Circle())

                    VStack(alignment: .leading, spacing: 1) {
                        Text(localized: step.title)
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(.white.opacity(0.62))
                        Text(localized: step.detail)
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.white.opacity(0.88))
                            .lineLimit(2)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .frame(minWidth: 0, maxWidth: .infinity, alignment: .leading)
                }
                .padding(.horizontal, 9)
                .padding(.vertical, 8)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
                .background(.white.opacity(backgroundOpacity(for: step.state)), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .strokeBorder(tint(for: step.state).opacity(0.24), lineWidth: 1)
                }
                .accessibilityElement(children: .combine)
                .accessibilityLabel("\(step.title): \(step.detail)")
                .accessibilityValue(accessibilityValue(for: step.state))
            }
        }
    }

    private func tint(for state: WindowsRuntimeReadinessState) -> Color {
        switch state {
        case .complete:
            return .green
        case .current:
            return .blue
        case .pending:
            return .white.opacity(0.58)
        case .attention:
            return .orange
        }
    }

    private func backgroundOpacity(for state: WindowsRuntimeReadinessState) -> Double {
        switch state {
        case .complete:
            return 0.14
        case .current:
            return 0.18
        case .pending:
            return 0.08
        case .attention:
            return 0.18
        }
    }

    private func accessibilityValue(for state: WindowsRuntimeReadinessState) -> String {
        switch state {
        case .complete:
            return "Complete"
        case .current:
            return "Next"
        case .pending:
            return "Waiting"
        case .attention:
            return "Needs attention"
        }
    }
}

struct RuntimeFailureBanner: View {
    var presentation: WindowsRuntimeFailurePresentation
    var refreshAction: () -> Void
    var detailsAction: () -> Void
    var diagnosticsURL: URL?

    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            Label(presentation.title, systemImage: "exclamationmark.triangle.fill")
                .font(.callout.weight(.semibold))
                .foregroundStyle(.orange)

            Text(presentation.message)
                .font(.caption)
                .foregroundStyle(.white.opacity(0.84))
                .lineLimit(3)
                .multilineTextAlignment(.leading)
                .textSelection(.enabled)

            HStack(spacing: 8) {
                Button(presentation.refreshTitle, action: refreshAction)
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)

                Button(presentation.detailsTitle, action: detailsAction)
                    .buttonStyle(.bordered)
                    .controlSize(.small)

                if let diagnosticsURL {
                    Link("Open diagnostics", destination: diagnosticsURL)
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                }
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.orange.opacity(0.16), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .strokeBorder(.orange.opacity(0.30), lineWidth: 1)
        }
        .accessibilityElement(children: .contain)
    }
}

struct WindowsRuntimeWaitBanner: View {
    var context: WindowsRuntimeWaitContext
    var refreshAction: () -> Void
    @State private var now = Date()

    var body: some View {
        Group {
            if let presentation {
                WindowsRuntimeWaitBannerContent(
                    presentation: presentation,
                    refreshAction: refreshAction
                )
            }
        }
        .task {
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(1))
                guard !Task.isCancelled else { return }
                now = Date()
            }
        }
    }

    private var presentation: WindowsRuntimeWaitPresentation? {
        WindowsRuntimeWaitPresentation.resolve(
            state: .starting,
            context: context,
            now: now
        )
    }
}

struct WindowsRuntimeWaitBannerContent: View {
    var presentation: WindowsRuntimeWaitPresentation
    var refreshAction: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            ProgressView()
                .controlSize(.small)
                .tint(presentation.isLongWait ? .orange : .blue)

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 8) {
                    Text(presentation.title)
                        .font(.caption.weight(.semibold))
                    if let elapsedText = presentation.elapsedText {
                        Text(elapsedText)
                            .font(.caption.monospacedDigit())
                            .foregroundStyle(.white.opacity(0.62))
                    }
                }
                Text(presentation.detail)
                    .font(.caption2)
                    .foregroundStyle(.white.opacity(0.72))
                    .lineLimit(2)
            }

            Spacer(minLength: 8)

            if presentation.isLongWait {
                Button("Refresh status", action: refreshAction)
                    .buttonStyle(.bordered)
                    .controlSize(.small)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 9)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            (presentation.isLongWait ? Color.orange : Color.blue).opacity(0.14),
            in: RoundedRectangle(cornerRadius: 10, style: .continuous)
        )
        .overlay {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .strokeBorder(
                    (presentation.isLongWait ? Color.orange : Color.blue).opacity(0.26),
                    lineWidth: 1
                )
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(
            presentation.elapsedText.map { "\(presentation.title), elapsed \($0). \(presentation.detail)" }
                ?? "\(presentation.title). \(presentation.detail)"
        )
    }
}

enum InstallFlowState {
    case complete
    case current
    case pending
}

struct InstallFlowItem: Identifiable {
    var id: String { title }
    var title: String
    var detail: String
    var symbolName: String
    var state: InstallFlowState
}

/// The bundled tools a release ships, read once; the file never changes while the app runs.
enum ShellGuestTools {
    static let bundledVersion = GuestToolsBundle.bundledVersion
}

/// Offers the Windows tools this Veil ships when the connected agent is older, the way a VM app
/// offers its guest tools after an update.
struct GuestToolsUpdateBanner: View {
    var updateAction: () -> Void

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Label("Windows tools update available", systemImage: "arrow.down.circle.fill")
                    .font(.callout.weight(.semibold))
                    .foregroundStyle(.white)
                Text("Brings resolution that follows the window and the latest fixes. Windows asks for approval once.")
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.78))
                    .lineLimit(2)
            }
            Spacer(minLength: 8)
            Button("Update Tools", action: updateAction)
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.blue.opacity(0.18), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .strokeBorder(.blue.opacity(0.32), lineWidth: 1)
        }
        .accessibilityElement(children: .contain)
    }
}
