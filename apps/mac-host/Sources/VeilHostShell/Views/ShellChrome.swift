import SwiftUI
import VeilHostCore

enum ShellSection: String, CaseIterable, Hashable {
    case apps
    case agent
    case vm
    case launch

    var title: String {
        switch self {
        case .apps:
            "Windows Apps"
        case .agent:
            "Agent"
        case .vm:
            "VM Runtime"
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
            "Windows 11 Arm profile and boot readiness"
        case .launch:
            "Most recent host-to-agent launch result"
        }
    }

    var symbolName: String {
        switch self {
        case .apps:
            "square.grid.2x2"
        case .agent:
            "network"
        case .vm:
            "desktopcomputer"
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
        }
    }
}
