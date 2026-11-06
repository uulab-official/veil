import Foundation
import Testing
import VeilHostCore
@testable import VeilHostShell

struct WindowsRuntimeReadinessTests {
    @Test("stopped configured runtime points to starting Windows")
    func stoppedConfiguredRuntime() {
        let snapshot = Self.snapshot(
            state: .stopped,
            profileName: "Windows 11",
            bootReady: true,
            windowsInstalled: true
        )

        let steps = WindowsRuntimeReadiness.resolve(
            snapshot: snapshot,
            agentDiagnostic: nil,
            hasDisplay: false
        )

        #expect(steps.map(\.id) == ["profile", "boot", "windows", "display", "apps"])
        #expect(steps[0].state == .complete)
        #expect(steps[1].state == .complete)
        #expect(steps[2].state == .current)
        #expect(steps[3].state == .pending)
        #expect(steps[4].state == .current)
    }

    @Test("running runtime promotes display and connected apps")
    func runningConnectedRuntime() {
        let snapshot = Self.snapshot(
            state: .running,
            profileName: "Windows 11",
            bootReady: true,
            windowsInstalled: true
        )
        let steps = WindowsRuntimeReadiness.resolve(
            snapshot: snapshot,
            agentDiagnostic: AgentConnectionDiagnostic(
                status: .connected,
                endpoint: "test",
                nextActions: []
            ),
            hasDisplay: true
        )

        #expect(steps[2].state == .complete)
        #expect(steps[2].detail == "Windows runtime is running")
        #expect(steps[3].state == .complete)
        #expect(steps[4].state == .complete)
    }

    @Test("failed runtime exposes an actionable attention state")
    func failedRuntime() {
        let snapshot = Self.snapshot(
            state: .failed,
            profileName: "Windows 11",
            bootReady: true,
            windowsInstalled: true
        )

        let steps = WindowsRuntimeReadiness.resolve(
            snapshot: snapshot,
            agentDiagnostic: .unavailable(endpoint: "test", errorMessage: "offline"),
            hasDisplay: false
        )

        #expect(steps[2].state == .attention)
        #expect(steps[2].detail.contains("failed"))
        #expect(steps[4].state == .current)
    }

    @Test("running installed runtime without agent points to app repair")
    func runningWithoutAgent() {
        let snapshot = Self.snapshot(
            state: .running,
            profileName: "Windows 11",
            bootReady: true,
            windowsInstalled: true
        )

        let steps = WindowsRuntimeReadiness.resolve(
            snapshot: snapshot,
            agentDiagnostic: .unavailable(endpoint: "test", errorMessage: "offline"),
            hasDisplay: true
        )

        #expect(steps[4].state == .attention)
        #expect(steps[4].detail.contains("Repair"))
    }

    @Test("starting runtime waits for the app connection before suggesting repair")
    func startingWithoutAgent() {
        let snapshot = Self.snapshot(
            state: .starting,
            profileName: "Windows 11",
            bootReady: true,
            windowsInstalled: true
        )

        let steps = WindowsRuntimeReadiness.resolve(
            snapshot: snapshot,
            agentDiagnostic: .unavailable(endpoint: "test", errorMessage: "offline"),
            hasDisplay: false
        )

        #expect(steps[4].state == .current)
        #expect(steps[4].detail == "Waiting for the app connection")
    }

    @Test("live guest evidence wins over a stale snapshot install flag")
    func liveGuestEvidenceWins() {
        let snapshot = Self.snapshot(
            state: .running,
            profileName: "Windows 11",
            bootReady: true,
            windowsInstalled: false
        )

        let steps = WindowsRuntimeReadiness.resolve(
            snapshot: snapshot,
            installEvidence: VMInstallEvidenceSummary(
                kind: .guestAgent,
                isInstalled: true,
                title: "Guest agent",
                detail: "live"
            ),
            agentDiagnostic: AgentConnectionDiagnostic(
                status: .connected,
                endpoint: "test",
                nextActions: []
            ),
            hasDisplay: true
        )

        #expect(steps[4].state == .complete)
        #expect(steps[4].detail == "Windows apps are connected")
    }

    @Test("stalled boot marks Windows and screen as attention without suggesting agent repair")
    func stalledBootNeedsDisplayRecovery() {
        let snapshot = Self.snapshot(
            state: .running,
            profileName: "Windows 11",
            bootReady: true,
            windowsInstalled: true,
            latestConsoleLaunch: Self.stalledLaunch
        )

        let steps = WindowsRuntimeReadiness.resolve(
            snapshot: snapshot,
            agentDiagnostic: .unavailable(endpoint: "test", errorMessage: "offline"),
            hasDisplay: true,
            asOf: Self.now
        )

        #expect(steps.first(where: { $0.id == "windows" })?.state == .attention)
        #expect(steps.first(where: { $0.id == "windows" })?.detail.contains("stalled") == true)
        #expect(steps.first(where: { $0.id == "display" })?.state == .attention)
        #expect(steps.first(where: { $0.id == "display" })?.detail.contains("180") == true)
        #expect(steps.first(where: { $0.id == "apps" })?.detail.contains("repair") == false)
    }

    @Test("a connected app link overrides a stale stalled-boot verdict")
    func connectedAgentClearsStall() {
        let snapshot = Self.snapshot(
            state: .running,
            profileName: "Windows 11",
            bootReady: true,
            windowsInstalled: true,
            latestConsoleLaunch: Self.stalledLaunch
        )

        let steps = WindowsRuntimeReadiness.resolve(
            snapshot: snapshot,
            agentDiagnostic: AgentConnectionDiagnostic(
                status: .connected,
                endpoint: "test",
                nextActions: []
            ),
            hasDisplay: true,
            asOf: Self.now
        )

        #expect(steps.first(where: { $0.id == "windows" })?.state == .complete)
        #expect(steps.first(where: { $0.id == "display" })?.state == .complete)
        #expect(steps.first(where: { $0.id == "apps" })?.state == .complete)
        #expect(!WindowsRuntimeReadiness.shouldBlockAgentRepair(
            snapshot: snapshot,
            agentConnected: true,
            asOf: Self.now
        ))
    }

    @Test("a recent blank boot remains a wait state")
    func recentBlankBootWaits() {
        let snapshot = Self.snapshot(
            state: .starting,
            profileName: "Windows 11",
            bootReady: true,
            windowsInstalled: true,
            latestConsoleLaunch: Self.recentLaunch
        )

        let steps = WindowsRuntimeReadiness.resolve(
            snapshot: snapshot,
            agentDiagnostic: .unavailable(endpoint: "test", errorMessage: "offline"),
            hasDisplay: true,
            asOf: Self.now
        )

        #expect(steps.first(where: { $0.id == "windows" })?.state == .current)
        #expect(steps.first(where: { $0.id == "display" })?.state == .current)
    }

    @Test("stalled boot blocks guest-agent repair")
    func stalledBootBlocksAgentRepair() {
        #expect(WindowsRuntimeReadiness.shouldBlockAgentRepair(
            snapshot: Self.snapshotWithStalledLaunch,
            asOf: Self.now
        ))
        #expect(!WindowsRuntimeReadiness.shouldBlockAgentRepair(
            snapshot: Self.snapshotWithRecentLaunch,
            asOf: Self.now
        ))
    }

    private static let now = Date(timeIntervalSince1970: 2_000)

    private static let stalledLaunch = VMConsoleLaunchEvidence(
        provider: "qemu",
        pid: 1,
        processLogPath: "/tmp/qemu.log",
        monitorSocketPath: "/tmp/qemu.sock",
        vncHost: "127.0.0.1",
        vncPort: 5900,
        consoleScreenshotPath: "/tmp/blank.png",
        consoleVisualState: .blank,
        consoleVisualStateAt: Date(timeIntervalSince1970: 1_900),
        previewStatus: .stale,
        startedAt: Date(timeIntervalSince1970: 1_700)
    )

    private static let recentLaunch = VMConsoleLaunchEvidence(
        provider: "qemu",
        pid: 1,
        processLogPath: "/tmp/qemu.log",
        monitorSocketPath: "/tmp/qemu.sock",
        vncHost: "127.0.0.1",
        vncPort: 5900,
        consoleScreenshotPath: "/tmp/blank.png",
        consoleVisualState: .blank,
        consoleVisualStateAt: Date(timeIntervalSince1970: 1_950),
        previewStatus: .stale,
        startedAt: Date(timeIntervalSince1970: 1_900)
    )

    private static var snapshotWithStalledLaunch: VMRuntimeSnapshot {
        snapshot(
            state: .running,
            profileName: "Windows 11",
            bootReady: true,
            windowsInstalled: true,
            latestConsoleLaunch: stalledLaunch
        )
    }

    private static var snapshotWithRecentLaunch: VMRuntimeSnapshot {
        snapshot(
            state: .starting,
            profileName: "Windows 11",
            bootReady: true,
            windowsInstalled: true,
            latestConsoleLaunch: recentLaunch
        )
    }

    private static func snapshot(
        state: VMRuntimeState,
        profileName: String?,
        bootReady: Bool,
        windowsInstalled: Bool,
        latestConsoleLaunch: VMConsoleLaunchEvidence? = nil
    ) -> VMRuntimeSnapshot {
        VMRuntimeSnapshot(
            state: state,
            virtualizationAvailable: true,
            architecture: "arm64",
            minimumOSSupported: true,
            profileName: profileName,
            latestConsoleLaunch: latestConsoleLaunch,
            installEvidence: VMInstallEvidenceSummary(
                kind: windowsInstalled ? .guestAgent : .setupReady,
                isInstalled: windowsInstalled,
                title: windowsInstalled ? "Windows installed" : "Windows setup",
                detail: "test"
            ),
            bootReady: bootReady,
            windowsInstalled: windowsInstalled,
            detail: "test"
        )
    }
}
