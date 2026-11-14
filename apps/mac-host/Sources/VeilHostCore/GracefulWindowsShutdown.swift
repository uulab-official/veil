import Foundation

/// Shuts Windows down the way the Start menu does before anything turns the VM off: through the
/// Veil tools when they can, else by pressing the ACPI power button, then waits for the VM to power
/// off. Killing QEMU first, as Stop used to, lost unsaved work and could interrupt updates Windows
/// installs while shutting down. The app's Stop and `veil-vmctl ... stop-runtime` both use this.
public enum GracefulWindowsShutdown {
    public enum Outcome: String, Equatable, Sendable {
        /// Windows powered off after the tools asked it to.
        case poweredOffViaTools
        /// Windows powered off after the power button press.
        case poweredOffViaPowerButton
        /// Windows finished shutting down after the tools asked it to, but the VM never powered off;
        /// see `settledSeconds`. The caller turns it off, which loses nothing.
        case finishedWithoutPowerOff
        /// Windows was asked but was still running at the deadline.
        case timedOut
        /// Neither the tools nor the power button could be reached.
        case notRequested

        public var poweredOff: Bool {
            self == .poweredOffViaTools || self == .poweredOffViaPowerButton || self == .finishedWithoutPowerOff
        }
    }

    /// Windows that accepted a tools shutdown may install updates first; waiting is safer than
    /// cutting power partway through.
    public static let toolsShutdownSeconds: TimeInterval = 600
    /// Without the tools, Windows may leave the power button unanswered.
    public static let powerButtonSeconds: TimeInterval = 90
    /// How long the guest must look finished (`hasFinishedShuttingDown`) before a tools shutdown counts
    /// as done although the VM is still on. Windows 11 Arm 26300 under QEMU/HVF ends its shutdown with a
    /// dark screen, its tools gone, and the vCPUs idle, but never powers off, which held Stop for the
    /// full ten minutes before Veil turned it off.
    public static let settledSeconds: TimeInterval = 20

    /// Main-actor bound because its callers drive main-actor models.
    @MainActor
    public static func run(
        requestToolsShutdown: () async -> Bool,
        pressPowerButton: () async -> Bool,
        isStillRunning: () async -> Bool,
        hasFinishedShuttingDown: () async -> Bool = { false },
        toolsTimeout: TimeInterval = toolsShutdownSeconds,
        settleTimeout: TimeInterval = settledSeconds,
        powerButtonTimeout: TimeInterval = powerButtonSeconds,
        pollInterval: Duration = .seconds(2),
        now: () -> Date = Date.init
    ) async -> Outcome {
        let viaTools = await requestToolsShutdown()
        if !viaTools, !(await pressPowerButton()) {
            return .notRequested
        }

        return await waitForPowerOff(
            viaTools: viaTools,
            isStillRunning: isStillRunning,
            hasFinishedShuttingDown: hasFinishedShuttingDown,
            timeout: viaTools ? toolsTimeout : powerButtonTimeout,
            settleTimeout: settleTimeout,
            pollInterval: pollInterval,
            now: now
        )
    }

    /// Waits for a shutdown already asked for: until the VM powers off, the guest looks finished for
    /// `settleTimeout` (tools shutdowns only), or `timeout` passes. Also used after the user chose to look
    /// at Windows instead of turning it off: the request stands, and Windows may still finish.
    @MainActor
    public static func waitForPowerOff(
        viaTools: Bool,
        isStillRunning: () async -> Bool,
        hasFinishedShuttingDown: () async -> Bool = { false },
        timeout: TimeInterval,
        settleTimeout: TimeInterval = settledSeconds,
        pollInterval: Duration = .seconds(2),
        now: () -> Date = Date.init
    ) async -> Outcome {
        let deadline = now().addingTimeInterval(timeout)
        var finishedSince: Date?
        repeat {
            try? await Task.sleep(for: pollInterval)
            if !(await isStillRunning()) {
                return viaTools ? .poweredOffViaTools : .poweredOffViaPowerButton
            }
            // Only after the tools asked: a power button press can also put Windows to sleep, which
            // looks the same from outside and must not be cut off.
            guard viaTools else {
                continue
            }
            if await hasFinishedShuttingDown() {
                let since = finishedSince ?? now()
                finishedSince = since
                if now().timeIntervalSince(since) >= settleTimeout {
                    return .finishedWithoutPowerOff
                }
            } else {
                finishedSince = nil
            }
        } while now() < deadline
        return .timedOut
    }
}
