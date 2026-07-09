import Testing

@testable import VeilHostShell

struct LauncherPrimaryNextActionRouteTests {
    @Test("routes structured action ids before command fallback")
    func routesStructuredActionIdsBeforeCommandFallback() {
        #expect(
            LauncherPrimaryNextActionRoute.resolve(
                actionId: "windowsApps.launchSelected",
                command: nil
            ) == .launchSelectedApp
        )
        #expect(
            LauncherPrimaryNextActionRoute.resolve(
                actionId: "runtime.repairGuestAgentForApp",
                command: nil
            ) == .repairAppConnection
        )
        #expect(
            LauncherPrimaryNextActionRoute.resolve(
                actionId: "runtime.prepareWindows",
                command: nil
            ) == .prepareWindows
        )
        #expect(
            LauncherPrimaryNextActionRoute.resolve(
                actionId: "runtime.refreshStatus",
                command: nil
            ) == .refreshRuntimeStatus
        )
        #expect(
            LauncherPrimaryNextActionRoute.resolve(
                actionId: "windowsApps.closeAll",
                command: nil
            ) == .closeAllWindowsApps
        )
        #expect(
            LauncherPrimaryNextActionRoute.resolve(
                actionId: "proof.recommended",
                command: nil
            ) == .runRecommendedProof
        )
    }

    @Test("routes app runtime commands to launcher actions")
    func routesAppRuntimeCommandsToLauncherActions() {
        #expect(
            LauncherPrimaryNextActionRoute.resolve(
                actionId: "openWindowsApp",
                command: "veil-vmctl app-runtime-action --json --action launch --app-id winapp_notepad"
            ) == .launchSelectedApp
        )
        #expect(
            LauncherPrimaryNextActionRoute.resolve(
                actionId: "openWindowsApp",
                command: "veil-vmctl app-runtime-action --json --action fulfill-pending"
            ) == .fulfillPendingLaunch
        )
        #expect(
            LauncherPrimaryNextActionRoute.resolve(
                actionId: "openWindowsApp",
                command: "veil-vmctl app-runtime-action --json --action recover-display"
            ) == .recoverDisplay
        )
        #expect(
            LauncherPrimaryNextActionRoute.resolve(
                actionId: "openWindowsApp",
                command: "veil-vmctl app-runtime-action --json --action wait-agent"
            ) == .waitForAgent
        )
        #expect(
            LauncherPrimaryNextActionRoute.resolve(
                actionId: "closeOrRestore",
                command: "veil-vmctl app-runtime-action --json --action reconnect-restore"
            ) == .reconnectPreviousApps
        )
        #expect(
            LauncherPrimaryNextActionRoute.resolve(
                actionId: "closeOrRestore",
                command: "veil-vmctl app-runtime-action --json --action close-all"
            ) == .closeAllWindowsApps
        )
        #expect(
            LauncherPrimaryNextActionRoute.resolve(
                actionId: "closeOrRestore",
                command: "veil-vmctl app-runtime-action --json --action stop-runtime"
            ) == .quietWindows
        )
    }

    @Test("routes setup and app check commands")
    func routesSetupAndAppCheckCommands() {
        #expect(
            LauncherPrimaryNextActionRoute.resolve(
                actionId: "windowsSetup",
                command: "veil-vmctl prepare --installer /tmp/Windows.iso"
            ) == .prepareWindows
        )
        #expect(
            LauncherPrimaryNextActionRoute.resolve(
                actionId: "windowsSetup",
                command: "veil-vmctl qemu-start --json"
            ) == .startWindows
        )
        #expect(
            LauncherPrimaryNextActionRoute.resolve(
                actionId: "windowsSetup",
                command: "veil-vmctl qemu-install-status --json"
            ) == .refreshRuntimeStatus
        )
        #expect(
            LauncherPrimaryNextActionRoute.resolve(
                actionId: "appCheckEvidence",
                command: "veil-vmctl mvp-proof --json --app-id winapp_notepad --require-proved"
            ) == .runRecommendedProof
        )
    }

    @Test("keeps unsupported commands out of the launcher button")
    func keepsUnsupportedCommandsOutOfLauncherButton() {
        #expect(
            LauncherPrimaryNextActionRoute.resolve(
                actionId: "ready-for-release-card",
                command: "veil-vmctl app-runtime-review --json"
            ) == nil
        )
        #expect(
            LauncherPrimaryNextActionRoute.resolve(
                actionId: "unknown",
                command: nil
            ) == nil
        )
    }
}
