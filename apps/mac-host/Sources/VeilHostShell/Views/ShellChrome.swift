import SwiftUI
import VeilHostCore

struct VeilAppMark: View {
    var size: CGFloat = 34

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: size * 0.22, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [
                            Color(red: 0.08, green: 0.09, blue: 0.11),
                            Color(red: 0.18, green: 0.18, blue: 0.22)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )

            RoundedRectangle(cornerRadius: size * 0.13, style: .continuous)
                .fill(.cyan.opacity(0.92))
                .frame(width: size * 0.44, height: size * 0.44)
                .offset(x: -size * 0.12, y: -size * 0.07)

            RoundedRectangle(cornerRadius: size * 0.13, style: .continuous)
                .fill(.orange.opacity(0.95))
                .frame(width: size * 0.44, height: size * 0.44)
                .offset(x: size * 0.12, y: size * 0.07)

            Text("V")
                .font(.system(size: size * 0.42, weight: .bold, design: .rounded))
                .foregroundStyle(.white)
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }
}

enum ShellSection: String, CaseIterable, Hashable {
    case apps
    case agent
    case vm
    case launch

    static var sidebarOrder: [ShellSection] {
        [.vm]
    }

    var title: String {
        switch self {
        case .apps:
            "Windows Apps"
        case .agent:
            "Agent"
        case .vm:
            "Windows 11 Arm"
        case .launch:
            "Last Launch"
        }
    }

    var subtitle: String {
        switch self {
        case .apps:
            "Run Windows apps from the Mac shell"
        case .agent:
            "Connection, session, and protocol capabilities"
        case .vm:
            "Virtual machine"
        case .launch:
            "Most recent host-to-agent launch result"
        }
    }

    var sidebarDetail: String {
        switch self {
        case .apps:
            "Launch and mirror"
        case .agent:
            "Protocol status"
        case .vm:
            "Stopped"
        case .launch:
            "Recent result"
        }
    }

    var symbolName: String {
        switch self {
        case .apps:
            "square.grid.2x2"
        case .agent:
            "network"
        case .vm:
            "display"
        case .launch:
            "macwindow.on.rectangle"
        }
    }
}

struct ShellPanel<Content: View>: View {
    var spacing: CGFloat = 14
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: spacing) {
            content
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .strokeBorder(.quaternary, lineWidth: 1)
        }
    }
}

struct ShellPanelHeader: View {
    var title: String
    var subtitle: String?
    var symbolName: String?

    var body: some View {
        HStack(alignment: .center, spacing: 10) {
            if let symbolName {
                Image(systemName: symbolName)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(.blue)
                    .frame(width: 30, height: 30)
                    .background(.blue.opacity(0.12), in: RoundedRectangle(cornerRadius: 7, style: .continuous))
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.headline)
                if let subtitle {
                    Text(subtitle)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
            }
        }
    }
}

struct ShellMetricRow: View {
    var label: String
    var value: String
    var monospaced: Bool = false

    var body: some View {
        GridRow {
            Text(label)
                .foregroundStyle(.secondary)
                .frame(minWidth: 118, alignment: .leading)

            Text(value)
                .font(monospaced ? .system(.callout, design: .monospaced) : .callout)
                .textSelection(.enabled)
                .lineLimit(2)
        }
    }
}

struct StatusPill: View {
    var title: String
    var symbolName: String
    var tint: Color

    var body: some View {
        Label(title, systemImage: symbolName)
            .font(.caption.weight(.semibold))
            .labelStyle(.titleAndIcon)
            .padding(.horizontal, 9)
            .padding(.vertical, 5)
            .foregroundStyle(tint)
            .background(tint.opacity(0.12), in: Capsule())
    }
}

struct CapabilityPill: View {
    var title: String
    var isEnabled: Bool

    var body: some View {
        Label(title, systemImage: isEnabled ? "checkmark.circle.fill" : "xmark.circle")
            .font(.caption)
            .foregroundStyle(isEnabled ? .green : .secondary)
            .padding(.horizontal, 9)
            .padding(.vertical, 5)
            .background(.thinMaterial, in: Capsule())
            .overlay {
                Capsule()
                    .strokeBorder(.quaternary, lineWidth: 1)
            }
    }
}

struct DashboardStat: View {
    var title: String
    var value: String
    var symbolName: String
    var tint: Color = .blue

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: symbolName)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(tint)
                .frame(width: 28, height: 28)
                .background(tint.opacity(0.12), in: RoundedRectangle(cornerRadius: 7, style: .continuous))

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text(value)
                    .font(.callout.weight(.semibold))
                    .lineLimit(1)
            }
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .strokeBorder(Color.secondary.opacity(0.16), lineWidth: 1)
        }
    }
}

struct ControlActionTile: View {
    var title: String
    var detail: String
    var symbolName: String
    var tint: Color
    var state: IntegrationState
    var action: () -> Void = {}

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 10) {
                HStack(alignment: .center, spacing: 10) {
                    Image(systemName: symbolName)
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(state == .blocked || state == .planned ? .secondary : tint)
                        .frame(width: 30, height: 30)
                        .background((state == .blocked || state == .planned ? Color.secondary : tint).opacity(0.12), in: RoundedRectangle(cornerRadius: 7, style: .continuous))

                    VStack(alignment: .leading, spacing: 2) {
                        Text(title)
                            .font(.callout.weight(.semibold))
                            .foregroundStyle(.primary)
                        Text(detail)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(2)
                    }
                }

                StatusPill(title: state.title, symbolName: state.symbolName, tint: state.tint)
            }
            .padding(12)
            .frame(maxWidth: .infinity, minHeight: 104, alignment: .topLeading)
            .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .strokeBorder(Color.secondary.opacity(0.16), lineWidth: 1)
            }
        }
        .buttonStyle(.plain)
        .disabled(state == .blocked || state == .planned)
    }
}

struct ResourcePlanRow: View {
    var title: String
    var value: String
    var symbolName: String
    var state: IntegrationState

    var body: some View {
        HStack(alignment: .center, spacing: 10) {
            Image(systemName: symbolName)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(state.tint)
                .frame(width: 28, height: 28)
                .background(state.tint.opacity(0.12), in: RoundedRectangle(cornerRadius: 7, style: .continuous))

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.callout.weight(.semibold))
                Text(value)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }

            Spacer()

            StatusPill(title: state.title, symbolName: state.symbolName, tint: state.tint)
        }
    }
}

struct SetupProgressBar: View {
    var completed: Int
    var total: Int

    private var fraction: Double {
        guard total > 0 else {
            return 0
        }

        return Double(completed) / Double(total)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("Setup Progress")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                Spacer()
                Text("\(completed)/\(total)")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
            }

            GeometryReader { proxy in
                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(.secondary.opacity(0.16))
                    Capsule()
                        .fill(fraction == 1 ? Color.green : Color.blue)
                        .frame(width: max(8, proxy.size.width * fraction))
                }
            }
            .frame(height: 7)
        }
    }
}

struct IntegrationStatusRow: View {
    var title: String
    var detail: String
    var symbolName: String
    var state: IntegrationState

    var body: some View {
        HStack(alignment: .center, spacing: 10) {
            Image(systemName: symbolName)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(state.tint)
                .frame(width: 28, height: 28)
                .background(state.tint.opacity(0.12), in: RoundedRectangle(cornerRadius: 7, style: .continuous))

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.callout.weight(.semibold))
                Text(detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }

            Spacer()

            StatusPill(title: state.title, symbolName: state.symbolName, tint: state.tint)
        }
        .padding(.vertical, 2)
    }
}

enum IntegrationState {
    case ready
    case partial
    case planned
    case blocked

    var title: String {
        switch self {
        case .ready:
            "Ready"
        case .partial:
            "Partial"
        case .planned:
            "Planned"
        case .blocked:
            "Blocked"
        }
    }

    var symbolName: String {
        switch self {
        case .ready:
            "checkmark.circle.fill"
        case .partial:
            "circle.lefthalf.filled"
        case .planned:
            "clock"
        case .blocked:
            "exclamationmark.circle"
        }
    }

    var tint: Color {
        switch self {
        case .ready:
            .green
        case .partial:
            .blue
        case .planned:
            .secondary
        case .blocked:
            .orange
        }
    }
}

extension HostDashboardPhase {
    var displayTitle: String {
        switch self {
        case .idle:
            "Idle"
        case .loading:
            "Loading"
        case .connected:
            "Connected"
        case .launching:
            "Launching"
        case .failed:
            "Failed"
        case .reconnecting:
            "Reconnecting"
        }
    }

    var symbolName: String {
        switch self {
        case .idle:
            "circle"
        case .loading:
            "arrow.triangle.2.circlepath"
        case .connected:
            "checkmark.circle.fill"
        case .launching:
            "play.circle"
        case .failed:
            "exclamationmark.triangle.fill"
        case .reconnecting:
            "arrow.triangle.2.circlepath"
        }
    }

    var tint: Color {
        switch self {
        case .idle:
            .secondary
        case .loading:
            .blue
        case .connected:
            .green
        case .launching:
            .blue
        case .failed:
            .orange
        case .reconnecting:
            .yellow
        }
    }
}
