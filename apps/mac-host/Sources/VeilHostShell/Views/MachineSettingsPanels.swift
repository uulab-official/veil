import AppKit
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
            Text("When suspend is off, Veil asks whether to suspend Windows or keep it running when it quits.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

/// Whether Windows draws on the Mac's GPU. Experimental: turning it on backs Windows up first, and turning
/// it off offers to go back to that copy, since a Windows with the GPU driver has no picture without it.
struct GraphicsAccelerationPanel: View {
    var snapshot: VMRuntimeSnapshot
    var canChangeResources: Bool
    var driverStatus: GuestGPUDriverStatus? = nil
    var installDriverAction: () -> Void = {}
    var applyAction: (_ value: VMGraphicsAcceleration, _ restoringBackup: Bool) async -> String?

    @State private var isWorking = false
    @State private var refusal: String?

    var body: some View {
        ShellPanel(spacing: 12) {
            ShellPanelHeader(
                title: "Graphics",
                subtitle: "Experimental. Windows uses this the next time it starts.",
                symbolName: "cpu.fill"
            )

            Toggle("Draw Windows on the Mac's GPU", isOn: Binding(
                get: { snapshot.graphicsAcceleration == .gpu },
                set: { change(to: $0 ? .gpu : .software) }
            ))
            .disabled(!canChangeResources || isWorking || !(snapshot.isGPURuntimeAvailable ?? false) && snapshot.graphicsAcceleration != .gpu)

            Text(caption)
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            if let refusal {
                Text(refusal)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if snapshot.graphicsAcceleration == .gpu, snapshot.state == .running, let driverStatus {
                Divider()
                HStack(alignment: .firstTextBaseline) {
                    Label(
                        GPUDriverStatusCopy.title(driverStatus),
                        systemImage: driverStatus.installed ? "checkmark.circle" : "exclamationmark.circle"
                    )
                    Spacer()
                    if !driverStatus.installed {
                        Button("Install GPU Driver", action: installDriverAction)
                            .disabled(driverStatus.installing == true)
                    }
                }
                if let detail = GPUDriverStatusCopy.detail(driverStatus) {
                    Text(detail)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }

    private var caption: String {
        if !(snapshot.isGPURuntimeAvailable ?? false) {
            return String(localized: "This copy of Veil does not include the GPU runtime.")
        }
        if !canChangeResources {
            return String(localized: "Shut down Windows to change this.")
        }
        return String(localized: "Uses UTM's Triton DirectX 11 driver. Apps draw about three times as fast, but the driver is new, suspend is not available, and Windows needs its GPU driver installed once. Veil keeps a copy of Windows from before, so you can go back.")
    }

    private func change(to value: VMGraphicsAcceleration) {
        let restoring: Bool
        switch value {
        case .gpu:
            guard confirm(
                title: String(localized: "Turn On GPU Acceleration?"),
                message: String(localized: "Veil first keeps a copy of Windows as it is now. GPU acceleration is experimental: once Windows installs the GPU driver, Windows shows nothing without GPU acceleration, and turning it off goes back to that copy."),
                button: String(localized: "Turn On")
            ) == .alertFirstButtonReturn else {
                return
            }
            restoring = false
        case .software:
            if snapshot.hasGraphicsBackup == true {
                let answer = confirm(
                    title: String(localized: "Go Back to Windows from Before GPU Acceleration?"),
                    message: String(localized: "Windows with the GPU driver shows nothing without GPU acceleration. Going back restores the copy Veil kept when you turned it on; files and apps changed in Windows since then are lost. Keep the current Windows only if it never installed the GPU driver."),
                    button: String(localized: "Go Back"),
                    alternate: String(localized: "Keep Current Windows")
                )
                switch answer {
                case .alertFirstButtonReturn:
                    restoring = true
                case .alertSecondButtonReturn:
                    restoring = false
                default:
                    return
                }
            } else {
                restoring = false
            }
        }
        isWorking = true
        refusal = nil
        Task { @MainActor in
            refusal = await applyAction(value, restoring)
            isWorking = false
        }
    }

    private func confirm(title: String, message: String, button: String, alternate: String? = nil) -> NSApplication.ModalResponse {
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = message
        alert.addButton(withTitle: button)
        if let alternate {
            alert.addButton(withTitle: alternate)
        }
        alert.addButton(withTitle: String(localized: "Cancel"))
        return alert.runModal()
    }
}

/// What the Graphics panel says about Triton's driver in Windows.
enum GPUDriverStatusCopy {
    static func title(_ status: GuestGPUDriverStatus) -> String {
        if status.installed {
            return String(localized: "GPU driver installed in Windows")
        }
        if status.installing == true {
            return String(localized: "Waiting for Windows approval…")
        }
        return String(localized: "GPU driver not installed in Windows")
    }

    static func detail(_ status: GuestGPUDriverStatus) -> String? {
        guard !status.installed else {
            return nil
        }
        switch status.lastInstall?.outcome {
        case "declined":
            return String(localized: "The Windows approval prompt was declined. Install again and choose Yes.")
        case "rejected-package":
            return String(localized: "Windows refused the driver package because it is not the one Veil ships.")
        case "failed":
            return String(localized: "The driver could not be installed: \(status.lastInstall?.message ?? String(localized: "unknown error"))")
        default:
            return String(localized: "Until it is installed, Windows still draws on the CPU. Installing asks for Windows approval once.")
        }
    }
}
