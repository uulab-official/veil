import SwiftUI
import VeilHostCore

struct DetailView: View {
    @Bindable var model: HostDashboardModel
    var selectedSection: ShellSection

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HeaderView(model: model)

            Divider()

            switch selectedSection {
            case .apps:
                AppsView(apps: model.apps)
            case .agent:
                AgentView(health: model.health, errorMessage: model.errorMessage)
            case .launch:
                LaunchView(result: model.lastLaunch)
            }

            Spacer(minLength: 0)
        }
        .padding(24)
    }
}

private struct HeaderView: View {
    @Bindable var model: HostDashboardModel

    var body: some View {
        HStack(alignment: .center) {
            VStack(alignment: .leading, spacing: 6) {
                Text("Veil Host")
                    .font(.title2.weight(.semibold))
                Text(model.statusText)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            PhaseBadge(phase: model.phase)
        }
    }
}

private struct PhaseBadge: View {
    var phase: HostDashboardPhase

    var body: some View {
        Label(title, systemImage: symbol)
            .labelStyle(.titleAndIcon)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 8))
    }

    private var title: String {
        switch phase {
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

    private var symbol: String {
        switch phase {
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
}
