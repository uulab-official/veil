import SwiftUI
import VeilHostCore

enum VMRuntimeSheetDestination: String, Identifiable, Equatable {
    case settings

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

enum VMSettingsSection: String, CaseIterable, Identifiable {
    case setup
    case runtime
    case integration

    var id: String { rawValue }

    var title: String {
        switch self {
        case .setup:
            return "Setup"
        case .runtime:
            return "Runtime"
        case .integration:
            return "Integration"
        }
    }

    var symbolName: String {
        switch self {
        case .setup:
            return "wand.and.stars"
        case .runtime:
            return "desktopcomputer"
        case .integration:
            return "macwindow.on.rectangle"
        }
    }

    var subtitle: String {
        switch self {
        case .setup:
            return "Installation media and the shortest path to Windows"
        case .runtime:
            return "Local VM engine, machine status, and hardware plan"
        case .integration:
            return "Mac app windows, devices, and readiness checks"
        }
    }
}

struct VMSettingsSheet<SetupContent: View, RuntimeContent: View, IntegrationContent: View>: View {
    @Environment(\.dismiss) private var dismiss
    @Bindable var model: VMRuntimeModel
    @State private var selectedSection = VMSettingsSection.setup
    private let setupContent: (VMRuntimeSnapshot, VMSettingsAccessPolicy) -> SetupContent
    private let runtimeContent: (VMRuntimeSnapshot, VMSettingsAccessPolicy) -> RuntimeContent
    private let integrationContent: (VMRuntimeSnapshot, VMSettingsAccessPolicy) -> IntegrationContent

    init(
        model: VMRuntimeModel,
        @ViewBuilder setupContent: @escaping (VMRuntimeSnapshot, VMSettingsAccessPolicy) -> SetupContent,
        @ViewBuilder runtimeContent: @escaping (VMRuntimeSnapshot, VMSettingsAccessPolicy) -> RuntimeContent,
        @ViewBuilder integrationContent: @escaping (VMRuntimeSnapshot, VMSettingsAccessPolicy) -> IntegrationContent
    ) {
        self.model = model
        self.setupContent = setupContent
        self.runtimeContent = runtimeContent
        self.integrationContent = integrationContent
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

                sectionPicker
                Divider()

                ScrollView {
                    VStack(alignment: .leading, spacing: 14) {
                        if let guidance = policy.guidance {
                            Label(guidance, systemImage: "lock.fill")
                                .font(.callout.weight(.medium))
                                .foregroundStyle(.orange)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(12)
                                .background(.orange.opacity(0.10), in: RoundedRectangle(cornerRadius: 10))
                        }

                        selectedContent(snapshot, policy: policy)
                            .transition(.opacity.combined(with: .move(edge: .trailing)))
                    }
                    .padding(18)
                }
                .animation(.easeInOut(duration: 0.18), value: selectedSection)
            } else {
                ContentUnavailableView(
                    "Windows Settings Unavailable",
                    systemImage: "gearshape",
                    description: Text("Refresh Windows status and open settings again.")
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .frame(minWidth: 900, minHeight: 620)
        .background(Color(nsColor: .windowBackgroundColor))
    }

    @ViewBuilder
    private func selectedContent(
        _ snapshot: VMRuntimeSnapshot,
        policy: VMSettingsAccessPolicy
    ) -> some View {
        switch selectedSection {
        case .setup:
            setupContent(snapshot, policy)
        case .runtime:
            runtimeContent(snapshot, policy)
        case .integration:
            integrationContent(snapshot, policy)
        }
    }

    private var sectionPicker: some View {
        HStack {
            Picker("Settings Section", selection: $selectedSection) {
                ForEach(VMSettingsSection.allCases) { section in
                    Label(section.title, systemImage: section.symbolName)
                        .tag(section)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .accessibilityLabel("Settings Section")
            .frame(maxWidth: 520)

            Spacer()

            Text(selectedSection.subtitle)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 10)
        .accessibilityElement(children: .contain)
    }

    private var header: some View {
        HStack(spacing: 12) {
            Image(systemName: "gearshape.fill")
                .font(.title2)
                .foregroundStyle(.tint)

            VStack(alignment: .leading, spacing: 2) {
                Text("Windows Settings")
                    .font(.title2.weight(.semibold))
                Text("Choose a category to keep advanced controls focused")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Button("Done") {
                dismiss()
            }
            .keyboardShortcut(.cancelAction)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 14)
    }
}
