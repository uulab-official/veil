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

struct VMSettingsSheet<Content: View>: View {
    @Environment(\.dismiss) private var dismiss
    @Bindable var model: VMRuntimeModel
    private let content: (VMRuntimeSnapshot, VMSettingsAccessPolicy) -> Content

    init(
        model: VMRuntimeModel,
        @ViewBuilder content: @escaping (VMRuntimeSnapshot, VMSettingsAccessPolicy) -> Content
    ) {
        self.model = model
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
                        if let guidance = policy.guidance {
                            Label(guidance, systemImage: "lock.fill")
                                .font(.callout.weight(.medium))
                                .foregroundStyle(.orange)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(12)
                                .background(.orange.opacity(0.10), in: RoundedRectangle(cornerRadius: 10))
                        }

                        content(snapshot, policy)
                    }
                    .padding(18)
                }
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

    private var header: some View {
        HStack(spacing: 12) {
            Image(systemName: "gearshape.fill")
                .font(.title2)
                .foregroundStyle(.tint)

            VStack(alignment: .leading, spacing: 2) {
                Text("Windows Settings")
                    .font(.title2.weight(.semibold))
                Text("Installation media, local runtime, resources, and Mac integration")
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
