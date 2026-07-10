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
                actionId: "runtime.startWindowsForApp",
                command: nil
            ) == .startWindowsForApp
        )
        #expect(
            LauncherPrimaryNextActionRoute.resolve(
                actionId: "runtime.prepareWindows",
                command: nil
            ) == .prepareWindows
        )
        #expect(
            LauncherPrimaryNextActionRoute.resolve(
                actionId: "runtime.prepareSparsePackage",
                command: nil
            ) == .preparePackageIdentity
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
                actionId: "windowsApps.reconnectRestore",
                command: nil
            ) == .reconnectPreviousApps
        )
        #expect(
            LauncherPrimaryNextActionRoute.resolve(
                actionId: "runtime.quietWhenIdle",
                command: nil
            ) == .quietWindows
        )
        #expect(
            LauncherPrimaryNextActionRoute.resolve(
                actionId: "proof.recommended",
                command: nil
            ) == .runRecommendedProof
        )
        #expect(
            LauncherPrimaryNextActionRoute.resolve(
                actionId: "dailyUse.verifyIntegrations",
                command: nil
            ) == .runRecommendedProof
        )
        #expect(
            LauncherPrimaryNextActionRoute.resolve(
                actionId: "dailyUse.verifyWindowCapture",
                command: nil
            ) == .refreshRuntimeStatus
        )
        #expect(
            LauncherPrimaryNextActionRoute.resolve(
                actionId: "windowsApps.restartFrameStream",
                command: nil
            ) == .restartFrameStream
        )
        #expect(
            LauncherPrimaryNextActionRoute.resolve(
                actionId: "windowsApps.recoverWindowCapture",
                command: nil
            ) == .recoverWindowCapture
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
                actionId: "openWindowsApp",
                command: "veil-vmctl app-runtime-action --json --action repair-agent --wait-seconds 120"
            ) == .repairAppConnection
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
                actionId: "openWindowsApp",
                command: "veil-vmctl app-runtime-action --json --action restart-frame-stream"
            ) == .restartFrameStream
        )
        #expect(
            LauncherPrimaryNextActionRoute.resolve(
                actionId: "openWindowsApp",
                command: "veil-vmctl app-runtime-action --json --action recover-window-capture"
            ) == .recoverWindowCapture
        )
        #expect(
            LauncherPrimaryNextActionRoute.resolve(
                actionId: "closeOrRestore",
                command: "veil-vmctl app-runtime-action --json --action stop-runtime"
            ) == .quietWindows
        )
        #expect(
            LauncherPrimaryNextActionRoute.resolve(
                actionId: "appCheckEvidence",
                command: "veil-vmctl app-runtime-action --json --action proof-recommended"
            ) == .runRecommendedProof
        )
        #expect(
            LauncherPrimaryNextActionRoute.resolve(
                actionId: "dailyUse",
                command: "veil-vmctl app-runtime-action --json --action prepare-sparse-package --wait-seconds 120"
            ) == .preparePackageIdentity
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
                actionId: "openWindowsApp",
                command: "veil-vmctl qemu-start --json --wait-seconds 30"
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
                actionId: "windowsSetup",
                command: "veil-vmctl qemu-prepare-sparse-package --json --wait-seconds 120"
            ) == .preparePackageIdentity
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

    @Test("requires in app contract before showing a launcher button")
    func requiresInAppContractBeforeShowingLauncherButton() {
        #expect(
            LauncherPrimaryNextActionRoute.resolve(
                actionId: "windowsApps.launchSelected",
                command: "veil-vmctl app-runtime-action --json --action launch --app-id winapp_notepad",
                runsInApp: true
            ) == .launchSelectedApp
        )
        #expect(
            LauncherPrimaryNextActionRoute.resolve(
                actionId: "windowsApps.launchSelected",
                command: "veil-vmctl app-runtime-action --json --action launch --app-id winapp_notepad",
                runsInApp: false
            ) == nil
        )
        #expect(
            LauncherPrimaryNextActionRoute.resolve(
                actionId: "appCheckEvidence",
                command: "veil-vmctl mvp-proof --json --app-id winapp_notepad --require-proved",
                runsInApp: false
            ) == nil
        )
    }
}
