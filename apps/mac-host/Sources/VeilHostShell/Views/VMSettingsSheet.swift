import SwiftUI
import VeilHostCore

enum VMRuntimeSheetDestination: String, Identifiable, Equatable {
    case settings
    case windowsDownload

    var id: String { rawValue }
}

struct VMSettingsAccessPolicy: Equatable {
    var canChangeResources: Bool
    var guidance: String?

    static func resolve(
        runtimeState: VMRuntimeState,
        isLoading: Bool
    ) -> VMSettingsAccessPolicy {
        if isLoading {
            return VMSettingsAccessPolicy(
                canChangeResources: false,
                guidance: "Wait for the current Windows operation to finish before changing VM resources."
            )
        }

        switch runtimeState {
        case .running, .starting:
            return VMSettingsAccessPolicy(
                canChangeResources: false,
                guidance: "Stop Windows before changing installer, driver, or virtual disk resources."
            )
        case .suspended:
            return VMSettingsAccessPolicy(
                canChangeResources: false,
                guidance: "Resume and stop Windows before changing resources so the suspended session stays consistent."
            )
        case .unsupported:
            return VMSettingsAccessPolicy(
                canChangeResources: false,
                guidance: "VM resources cannot be changed because this Mac does not support the current runtime."
            )
        case .notConfigured, .stopped, .failed:
            return VMSettingsAccessPolicy(canChangeResources: true, guidance: nil)
        }
    }
}

/// Parallels-style machine configuration: one tab per area instead of one long settings page.
struct VMSettingsSheet<Content: View>: View {
    @Environment(\.dismiss) private var dismiss
    @Bindable var model: VMRuntimeModel
    @Binding var selectedTab: MachineConfigurationTab
    private let content: (VMRuntimeSnapshot, VMSettingsAccessPolicy, MachineConfigurationTab) -> Content

    init(
        model: VMRuntimeModel,
        selectedTab: Binding<MachineConfigurationTab>,
        @ViewBuilder content: @escaping (VMRuntimeSnapshot, VMSettingsAccessPolicy, MachineConfigurationTab) -> Content
    ) {
        self.model = model
        self._selectedTab = selectedTab
        self.content = content
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()

            if let snapshot = model.snapshot {
                let policy = VMSettingsAccessPolicy.resolve(
                    runtimeState: snapshot.state,
                    isLoading: model.phase == .loading
                )

                ScrollView {
                    VStack(alignment: .leading, spacing: 14) {
                        if let guidance = policy.guidance,
                           selectedTab == .hardware || selectedTab == .installation {
                            Label(guidance, systemImage: "lock.fill")
                                .font(.callout.weight(.medium))
                                .foregroundStyle(.orange)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(12)
                                .background(.orange.opacity(0.10), in: RoundedRectangle(cornerRadius: 10))
                        }

                        content(snapshot, policy, selectedTab)
                    }
                    .padding(20)
                }
            } else {
                ContentUnavailableView(
                    "Configuration Unavailable",
                    systemImage: "gearshape",
                    description: Text("Refresh Windows status and open Configuration again.")
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .frame(minWidth: 760, idealWidth: 820, minHeight: 560, idealHeight: 640)
        .background(Color(nsColor: .windowBackgroundColor))
    }

    private var header: some View {
        VStack(spacing: 12) {
            HStack {
                Text("\(model.snapshot?.profileName ?? "Windows 11") – Configuration")
                    .font(.headline)

                Spacer()

                Button("Done") {
                    dismiss()
                }
                .keyboardShortcut(.cancelAction)
            }

            HStack(spacing: 4) {
                ForEach(MachineConfigurationTab.allCases) { tab in
                    ConfigurationTabButton(tab: tab, isSelected: selectedTab == tab) {
                        selectedTab = tab
                    }
                }
            }
        }
        .padding(.horizontal, 20)
        .padding(.top, 14)
        .padding(.bottom, 10)
    }
}

/// An icon-over-title tab like the toolbar tabs of a macOS preferences window.
private struct ConfigurationTabButton: View {
    var tab: MachineConfigurationTab
    var isSelected: Bool
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 4) {
                Image(systemName: tab.symbolName)
                    .font(.system(size: 18, weight: .regular))
                    .frame(height: 22)
                Text(tab.title)
                    .font(.caption)
                    .lineLimit(1)
            }
            .foregroundStyle(isSelected ? Color.accentColor : .secondary)
            .frame(width: 104, height: 52)
            .background(
                isSelected ? Color.primary.opacity(0.08) : Color.clear,
                in: RoundedRectangle(cornerRadius: 8, style: .continuous)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(tab.title)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}
