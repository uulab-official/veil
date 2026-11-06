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
        /// Windows was asked but was still running at the deadline.
        case timedOut
        /// Neither the tools nor the power button could be reached.
        case notRequested

        public var poweredOff: Bool {
            self == .poweredOffViaTools || self == .poweredOffViaPowerButton
        }
    }

    /// Windows that accepted a tools shutdown may install updates first; waiting is safer than
    /// cutting power partway through.
    public static let toolsShutdownSeconds: TimeInterval = 600
    /// Without the tools, Windows may leave the power button unanswered.
    public static let powerButtonSeconds: TimeInterval = 90

    /// Main-actor bound because its callers drive main-actor models.
    @MainActor
    public static func run(
        requestToolsShutdown: () async -> Bool,
        pressPowerButton: () async -> Bool,
        isStillRunning: () async -> Bool,
        toolsTimeout: TimeInterval = toolsShutdownSeconds,
        powerButtonTimeout: TimeInterval = powerButtonSeconds,
        pollInterval: Duration = .seconds(2),
        now: () -> Date = Date.init
    ) async -> Outcome {
        let viaTools = await requestToolsShutdown()
        if !viaTools, !(await pressPowerButton()) {
            return .notRequested
        }

        let deadline = now().addingTimeInterval(viaTools ? toolsTimeout : powerButtonTimeout)
        repeat {
            try? await Task.sleep(for: pollInterval)
            if !(await isStillRunning()) {
                return viaTools ? .poweredOffViaTools : .poweredOffViaPowerButton
            }
        } while now() < deadline
        return .timedOut
    }
}
