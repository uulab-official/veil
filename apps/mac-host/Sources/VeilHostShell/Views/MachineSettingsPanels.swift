import SwiftUI
import VeilHostCore

/// CPU and memory for the next start, like the Hardware pane of a Parallels or UTM VM. Changes wait
/// for Apply so a half-dragged value never reaches the profile.
struct HardwareEditorPanel: View {
    var snapshot: VMRuntimeSnapshot
    var canChangeResources: Bool
    var limits: VMResourceLimits = .currentHost()
    var applyAction: (_ cpuCount: Int, _ memoryMB: Int) -> Void

    @State private var cpuCount = VMResourceLimits.minimumCPUCount
    @State private var memoryGB = VMResourceLimits.minimumMemoryMB / 1_024

    var body: some View {
        ShellPanel(spacing: 12) {
            ShellPanelHeader(
                title: "Processors and Memory",
                subtitle: "Windows uses these the next time it starts.",
                symbolName: "cpu"
            )

            Grid(alignment: .leading, horizontalSpacing: 18, verticalSpacing: 12) {
                GridRow {
                    Text("Processors")
                    Stepper(value: $cpuCount, in: VMResourceLimits.minimumCPUCount...limits.maximumCPUCount) {
                        Text("\(cpuCount) cores")
                            .monospacedDigit()
                    }
                    .accessibilityLabel("Processors")
                    .accessibilityValue("\(cpuCount) cores")
                    Text("Up to \(limits.maximumCPUCount)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                GridRow {
                    Text("Memory")
                    Stepper(value: $memoryGB, in: minimumMemoryGB...maximumMemoryGB) {
                        Text("\(memoryGB) GB")
                            .monospacedDigit()
                    }
                    .accessibilityLabel("Memory")
                    .accessibilityValue("\(memoryGB) gigabytes")
                    Text("Up to \(maximumMemoryGB) GB")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .disabled(!canChangeResources)

            HStack {
                if snapshot.cpuCount != nil, isChanged {
                    Text("Was \(snapshot.cpuCount ?? 0) cores and \((snapshot.memoryMB ?? 0) / 1_024) GB.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button("Revert", action: loadFromSnapshot)
                    .disabled(!isChanged)
                Button("Apply") {
                    applyAction(cpuCount, memoryGB * 1_024)
                }
                .buttonStyle(.borderedProminent)
                .disabled(!canChangeResources || !isChanged)
            }
        }
        .onAppear(perform: loadFromSnapshot)
        .onChange(of: snapshot.cpuCount) { _, _ in loadFromSnapshot() }
        .onChange(of: snapshot.memoryMB) { _, _ in loadFromSnapshot() }
    }

    private var minimumMemoryGB: Int { VMResourceLimits.minimumMemoryMB / 1_024 }
    private var maximumMemoryGB: Int { limits.maximumMemoryMB / 1_024 }

    private var isChanged: Bool {
        cpuCount != limits.clampedCPUCount(snapshot.cpuCount ?? cpuCount)
            || memoryGB * 1_024 != limits.clampedMemoryMB(snapshot.memoryMB ?? memoryGB * 1_024)
    }

    private func loadFromSnapshot() {
        cpuCount = limits.clampedCPUCount(snapshot.cpuCount ?? VMResourceLimits.minimumCPUCount)
        memoryGB = limits.clampedMemoryMB(snapshot.memoryMB ?? VMResourceLimits.minimumMemoryMB) / 1_024
    }
}

/// What Veil does with Windows when it opens and quits.
struct StartupBehaviorPanel: View {
    var snapshot: VMRuntimeSnapshot
    var applyAction: (_ autoStart: Bool, _ suspendOnQuit: Bool) -> Void

    var body: some View {
        ShellPanel(spacing: 12) {
            ShellPanelHeader(
                title: "Startup and Shutdown",
                subtitle: "Applies to the installed Windows on this Mac.",
                symbolName: "power"
            )

            Toggle("Start Windows when Veil opens", isOn: Binding(
                get: { snapshot.autoStart ?? false },
                set: { applyAction($0, snapshot.suspendOnQuit ?? false) }
            ))
            Toggle("Suspend Windows when Veil quits", isOn: Binding(
                get: { snapshot.suspendOnQuit ?? false },
                set: { applyAction(snapshot.autoStart ?? false, $0) }
            ))
            Text("When suspend is off, Windows keeps running in the background after Veil quits.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}
