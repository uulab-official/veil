import Foundation

/// How a live, writable folder is shared between macOS and the Windows guest.
///
/// Most of the obvious answers do not work on this host, so the choice here is narrower than it
/// looks:
///
/// - **virtio-9p / virtfs** has no Windows guest driver at all. The 9p client inside WSL is not a
///   mountable filesystem driver for ordinary Windows.
/// - **virtio-fs** has a good Windows guest driver (WinFsp-based, from the virtio-win project) but
///   needs a `virtiofsd` host daemon that has not been ported to QEMU on macOS.
/// - **QEMU's built-in usermode SMB** (`-netdev user,smb=...`) shells out to `/usr/sbin/smbd`, which
///   on macOS is Apple's SIP-protected binary rather than Samba's, and current Samba refuses to run
///   as the non-root user QEMU invokes it as.
///
/// What is left is the transport where Veil controls both ends and neither end needs anything
/// installed: Windows ships an SMB *server*, macOS ships an SMB *client*, and QEMU usermode
/// networking already forwards a host port into the guest for the guest agent.
///
/// The consequence is that the shared folder physically lives **in the guest** and appears on the
/// Mac, which is the opposite of the naive expectation. The other direction -- a Mac folder appearing
/// inside Windows -- requires an SMB server on the host and is modelled as ``hostSMB`` so it can be
/// reported as a distinct, currently-unavailable capability instead of being quietly conflated with
/// the one that works.
public enum QEMUWindowsSharedFolderTransport: String, Codable, CaseIterable, Equatable, Sendable {
    /// Windows hosts the share; macOS mounts it over a loopback port forward. No host prerequisites.
    case guestSMB = "guest-smb"
    /// macOS hosts the share; Windows mounts it from the usermode gateway. Requires the user to turn
    /// on macOS File Sharing, which exposes the share on every interface rather than only to the
    /// guest, so it is never selected automatically.
    case hostSMB = "host-smb"
    /// Named `disabled` rather than `none` so it can never be confused with `Optional.none` at a call
    /// site. The wire and environment value stays `none`.
    case disabled = "none"

    public static let environmentVariableName = "VEIL_QEMU_SHARED_FOLDER"

    /// Share name, guest directory, and ports.
    ///
    /// `guestDirectoryPath` is `C:\VeilShared` rather than somewhere under `%LOCALAPPDATA%` because
    /// the default ACL on `C:\` already lets a standard user create a directory there, so the agent
    /// can create the folder without elevation while still giving the user a path they can type.
    /// Creating the SMB *share* still needs elevation; that is reported, not worked around.
    public static let shareName = "VeilShared"
    public static let guestDirectoryPath = #"C:\VeilShared"#
    public static let hostForwardAddress = "127.0.0.1"
    public static let guestSMBHostPort = 18_445
    public static let guestSMBGuestPort = 445
    /// Address the guest reaches the host on under QEMU usermode (slirp) networking.
    public static let usermodeHostGatewayAddress = "10.0.2.2"

    public struct Selection: Equatable, Sendable {
        public var transport: QEMUWindowsSharedFolderTransport
        public var warning: String?
        public var isExplicit: Bool

        public init(transport: QEMUWindowsSharedFolderTransport, warning: String?, isExplicit: Bool) {
            self.transport = transport
            self.warning = warning
            self.isExplicit = isExplicit
        }
    }

    public var isEnabled: Bool {
        self != .disabled
    }

    /// Slirp port-forward clause appended to the existing `-netdev user,id=net0` value.
    ///
    /// Appended to the existing netdev rather than adding a second one, so the guest keeps exactly one
    /// NIC. Bound to `127.0.0.1` explicitly: an empty host address in a `hostfwd` clause binds every
    /// interface, which would put the guest's SMB server on the local network.
    public var hostForwardClause: String? {
        switch self {
        case .guestSMB:
            "hostfwd=tcp:\(Self.hostForwardAddress):\(Self.guestSMBHostPort)-:\(Self.guestSMBGuestPort)"
        case .hostSMB, .disabled:
            nil
        }
    }

    /// URL that mounts the share on macOS, for the transports where macOS is the client.
    public var hostMountURL: String? {
        switch self {
        case .guestSMB:
            "smb://\(Self.hostForwardAddress):\(Self.guestSMBHostPort)/\(Self.shareName)"
        case .hostSMB, .disabled:
            nil
        }
    }

    /// Where macOS mounts the share once the user accepts the connection. macOS mounts SMB volumes
    /// under `/Volumes` named after the share.
    public var expectedHostMountPath: String? {
        switch self {
        case .guestSMB:
            "/Volumes/\(Self.shareName)"
        case .hostSMB, .disabled:
            nil
        }
    }

    /// Guest-side path that holds the shared files, for the transports where the guest is the server.
    ///
    /// This is Veil's *intent*. The guest agent reports the path it actually used, and a mismatch
    /// between the two is visible in the report rather than hidden.
    public var expectedGuestDirectoryPath: String? {
        switch self {
        case .guestSMB:
            Self.guestDirectoryPath
        case .hostSMB, .disabled:
            nil
        }
    }

    /// Command a user runs inside Windows to mount a host-served share.
    public var guestMountCommand: String? {
        switch self {
        case .hostSMB:
            #"net use Z: \\\#(Self.usermodeHostGatewayAddress)\<your-mac-short-username> /persistent:yes"#
        case .guestSMB, .disabled:
            nil
        }
    }

    /// Whether this transport needs an SMB server running on the macOS host.
    public var requiresHostSMBServer: Bool {
        self == .hostSMB
    }

    public var summary: String {
        switch self {
        case .guestSMB:
            "Windows shares \(Self.guestDirectoryPath) as \(Self.shareName); macOS mounts it over a loopback port forward."
        case .hostSMB:
            "macOS shares a folder over its own SMB server; Windows mounts it from \(Self.usermodeHostGatewayAddress)."
        case .disabled:
            "No live shared folder. Files reach Windows only through drag-and-drop file open."
        }
    }

    public static func selected(from rawValue: String?) -> Selection {
        guard let rawValue,
              !rawValue.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return Selection(transport: .guestSMB, warning: nil, isExplicit: false)
        }

        let normalizedValue = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
        if let transport = QEMUWindowsSharedFolderTransport(rawValue: normalizedValue) {
            return Selection(transport: transport, warning: nil, isExplicit: true)
        }

        let supportedValues = QEMUWindowsSharedFolderTransport.allCases
            .map(\.rawValue)
            .joined(separator: ", ")
        return Selection(
            transport: .guestSMB,
            warning: "Ignoring unsupported \(environmentVariableName)=\(normalizedValue). Supported values: \(supportedValues).",
            isExplicit: true
        )
    }
}

// MARK: - Capability

public enum VMSharedFolderSupportState: String, Codable, Equatable, Sendable {
    case supported
    /// The transport cannot work without something Veil does not install for the user.
    case unsupportedTransport
    case disabled
    /// The host port the transport needs is already taken, so the forward was left out of the boot
    /// plan rather than allowed to stop QEMU from starting.
    case hostPortUnavailable
    /// The plan carries no forward and the port is free, so the reason is something other than a port
    /// conflict -- most often a VM started before folder sharing was turned on. Kept distinct from
    /// ``hostPortUnavailable`` so the report never asserts a cause it did not observe.
    case forwardMissingFromPlan
    case notConfigured
}

/// Whether a live shared folder can work on this host, and if not, exactly why.
public struct VMSharedFolderCapability: Codable, Equatable, Sendable {
    public var state: VMSharedFolderSupportState
    public var isSupported: Bool
    public var transport: QEMUWindowsSharedFolderTransport
    /// True when the running boot plan actually carries the port forward this transport needs. A
    /// supported transport that is not wired means the VM has to be restarted before the share works.
    public var isWiredIntoBootPlan: Bool
    public var shareName: String?
    public var expectedGuestDirectoryPath: String?
    public var hostMountURL: String?
    public var expectedHostMountPath: String?
    public var hostForwardClause: String?
    public var overrideEnvironmentVariable: String
    public var detail: String

    public init(
        state: VMSharedFolderSupportState,
        transport: QEMUWindowsSharedFolderTransport,
        isWiredIntoBootPlan: Bool,
        shareName: String? = nil,
        expectedGuestDirectoryPath: String? = nil,
        hostMountURL: String? = nil,
        expectedHostMountPath: String? = nil,
        hostForwardClause: String? = nil,
        overrideEnvironmentVariable: String = QEMUWindowsSharedFolderTransport.environmentVariableName,
        detail: String
    ) {
        self.state = state
        self.isSupported = state == .supported
        self.transport = transport
        self.isWiredIntoBootPlan = isWiredIntoBootPlan
        self.shareName = shareName
        self.expectedGuestDirectoryPath = expectedGuestDirectoryPath
        self.hostMountURL = hostMountURL
        self.expectedHostMountPath = expectedHostMountPath
        self.hostForwardClause = hostForwardClause
        self.overrideEnvironmentVariable = overrideEnvironmentVariable
        self.detail = detail
    }
}

public enum VMSharedFolderCapabilityFactory {
    /// - Parameter isHostPortAvailable: Whether the host forward port is currently free. Pass `nil`
    ///   when it was not probed; the capability then reports that the forward is missing without
    ///   claiming to know why.
    public static func make(
        transport: QEMUWindowsSharedFolderTransport,
        planArguments: [String]?,
        isHostPortAvailable: Bool? = nil
    ) -> VMSharedFolderCapability {
        switch transport {
        case .disabled:
            return VMSharedFolderCapability(
                state: .disabled,
                transport: transport,
                isWiredIntoBootPlan: false,
                detail: "Live folder sharing is turned off by \(QEMUWindowsSharedFolderTransport.environmentVariableName)=\(transport.rawValue)."
            )

        case .hostSMB:
            return VMSharedFolderCapability(
                state: .unsupportedTransport,
                transport: transport,
                isWiredIntoBootPlan: false,
                detail: "Sharing a macOS folder into Windows needs an SMB server on the Mac. Veil does not turn on macOS File Sharing for you, because it publishes the share on every network interface rather than only to the guest."
            )

        case .guestSMB:
            guard let planArguments else {
                return VMSharedFolderCapability(
                    state: .notConfigured,
                    transport: transport,
                    isWiredIntoBootPlan: false,
                    detail: "No QEMU boot plan is available, so Veil cannot tell whether the shared folder port forward is configured. Run veil-vmctl prepare first."
                )
            }

            let clause = transport.hostForwardClause
            let isWired = clause.map { candidate in
                planArguments.contains { $0.contains(candidate) }
            } ?? false

            let state: VMSharedFolderSupportState
            let detail: String
            if isWired {
                state = .supported
                detail = transport.summary
            } else if isHostPortAvailable == false {
                state = .hostPortUnavailable
                detail = "Host port \(QEMUWindowsSharedFolderTransport.guestSMBHostPort) is already in use, so the forward was left out of the boot plan instead of stopping QEMU from starting."
            } else {
                state = .forwardMissingFromPlan
                detail = "The boot plan does not carry \(clause ?? "the shared folder port forward"), and host port \(QEMUWindowsSharedFolderTransport.guestSMBHostPort) is not the reason. The running VM was most likely started before folder sharing was turned on."
            }

            return VMSharedFolderCapability(
                state: state,
                transport: transport,
                isWiredIntoBootPlan: isWired,
                shareName: QEMUWindowsSharedFolderTransport.shareName,
                expectedGuestDirectoryPath: transport.expectedGuestDirectoryPath,
                hostMountURL: transport.hostMountURL,
                expectedHostMountPath: transport.expectedHostMountPath,
                hostForwardClause: clause,
                detail: detail
            )
        }
    }
}

// MARK: - Host mount status

/// Whether macOS currently has the guest-served share mounted.
public struct VMSharedFolderHostMountStatus: Codable, Equatable, Sendable {
    public var isMounted: Bool
    public var mountPath: String?
    public var detail: String

    public init(isMounted: Bool, mountPath: String? = nil, detail: String) {
        self.isMounted = isMounted
        self.mountPath = mountPath
        self.detail = detail
    }
}

public enum VMSharedFolderHostMountProbe {
    /// Checks for the mount by looking for the volume directory macOS creates for it.
    ///
    /// Injectable rather than calling `getmntinfo` directly so the readiness rules stay testable
    /// without mounting anything.
    public static func read(
        transport: QEMUWindowsSharedFolderTransport,
        directoryExists: (String) -> Bool = { path in
            var isDirectory: ObjCBool = false
            let exists = FileManager.default.fileExists(atPath: path, isDirectory: &isDirectory)
            return exists && isDirectory.boolValue
        }
    ) -> VMSharedFolderHostMountStatus {
        guard let expectedPath = transport.expectedHostMountPath else {
            return VMSharedFolderHostMountStatus(
                isMounted: false,
                detail: "This transport does not mount anything on the Mac."
            )
        }

        guard directoryExists(expectedPath) else {
            return VMSharedFolderHostMountStatus(
                isMounted: false,
                detail: "\(expectedPath) is not present, so the share is not mounted on this Mac."
            )
        }

        return VMSharedFolderHostMountStatus(
            isMounted: true,
            mountPath: expectedPath,
            detail: "The share is mounted at \(expectedPath)."
        )
    }
}

// MARK: - Report

public enum VMSharedFolderReadiness: String, Codable, Equatable, Sendable {
    case ready
    case awaitingVM
    case awaitingGuestAgent
    case awaitingGuestShare
    case awaitingHostMount
    case unavailable
}

public struct VMSharedFolderReport: Codable, Equatable, Sendable {
    public var kind: String
    public var generatedAt: Date
    public var provider: String
    public var vmState: VMRuntimeState
    public var readiness: VMSharedFolderReadiness
    public var capability: VMSharedFolderCapability
    /// What the guest says. Absent when the guest agent is unreachable or predates this protocol.
    public var guest: WindowsSharedFolderStatus?
    public var hostMount: VMSharedFolderHostMountStatus
    /// The host staging folder that holds `VeilAutoInstall.iso`. Reported alongside the live share
    /// because the two are easy to confuse, and this one is *not* shared with the guest.
    public var hostStagingFolderPath: String?
    public var nextActions: [String]

    public init(
        kind: String = "vmSharedFolderStatus",
        generatedAt: Date,
        provider: String,
        vmState: VMRuntimeState,
        readiness: VMSharedFolderReadiness,
        capability: VMSharedFolderCapability,
        guest: WindowsSharedFolderStatus? = nil,
        hostMount: VMSharedFolderHostMountStatus,
        hostStagingFolderPath: String? = nil,
        nextActions: [String]
    ) {
        self.kind = kind
        self.generatedAt = generatedAt
        self.provider = provider
        self.vmState = vmState
        self.readiness = readiness
        self.capability = capability
        self.guest = guest
        self.hostMount = hostMount
        self.hostStagingFolderPath = hostStagingFolderPath
        self.nextActions = nextActions
    }
}

public enum VMSharedFolderReportFactory {
    public static func make(
        generatedAt: Date,
        provider: String = "QEMU/HVF",
        vmState: VMRuntimeState,
        capability: VMSharedFolderCapability,
        guest: WindowsSharedFolderStatus?,
        hostMount: VMSharedFolderHostMountStatus,
        hostStagingFolderPath: String? = nil
    ) -> VMSharedFolderReport {
        let resolvedReadiness = readiness(
            capability: capability,
            vmState: vmState,
            guest: guest,
            hostMount: hostMount
        )

        return VMSharedFolderReport(
            generatedAt: generatedAt,
            provider: provider,
            vmState: vmState,
            readiness: resolvedReadiness,
            capability: capability,
            guest: guest,
            hostMount: hostMount,
            hostStagingFolderPath: hostStagingFolderPath,
            nextActions: nextActions(
                readiness: resolvedReadiness,
                capability: capability,
                guest: guest
            )
        )
    }

    /// Whether the guest published the share Veil actually asked for.
    ///
    /// ``QEMUWindowsSharedFolderTransport/expectedGuestDirectoryPath`` has always documented that "the guest
    /// agent reports the path it actually used, and a mismatch between the two is visible in the report rather
    /// than hidden". Nothing compared them. This is that comparison.
    ///
    /// Case-insensitive because Windows share names and paths are.
    static func guestSharesRequestedFolder(
        capability: VMSharedFolderCapability,
        guest: WindowsSharedFolderStatus
    ) -> Bool {
        if let expectedShareName = capability.shareName,
           guest.shareName.caseInsensitiveCompare(expectedShareName) != .orderedSame {
            return false
        }
        if let expectedGuestDirectoryPath = capability.expectedGuestDirectoryPath,
           guest.guestDirectoryPath.caseInsensitiveCompare(expectedGuestDirectoryPath) != .orderedSame {
            return false
        }
        return true
    }

    /// The elevated PowerShell command to publish the share, built entirely from host-owned values.
    ///
    /// **Never** `guest.shareCommand`. That field is a guest-supplied string, and this text tells the user to
    /// run it *as administrator* — so a compromised guest would have been choosing the text of an elevated
    /// command that Veil vouches for. The host does not need the guest's help here: it sent both variables in
    /// the request, so it can build the command itself.
    ///
    /// Matches `SharedFolderProbe.ShareCommand` on the guest, which is generated from the same two values.
    static func hostAuthoredShareCommand(capability: VMSharedFolderCapability) -> String {
        let shareName = safeCommandValue(capability.shareName)
            ?? QEMUWindowsSharedFolderTransport.shareName
        let guestDirectoryPath = safeCommandValue(capability.expectedGuestDirectoryPath)
            ?? QEMUWindowsSharedFolderTransport.guestDirectoryPath
        return "New-SmbShare -Name \(shareName) -Path \(guestDirectoryPath) -FullAccess $env:USERNAME"
    }

    /// Human-readable description of the share Veil asked for, from the same host-owned values.
    static func hostAuthoredShareDescription(capability: VMSharedFolderCapability) -> String {
        let shareName = safeCommandValue(capability.shareName)
            ?? QEMUWindowsSharedFolderTransport.shareName
        let guestDirectoryPath = safeCommandValue(capability.expectedGuestDirectoryPath)
            ?? QEMUWindowsSharedFolderTransport.guestDirectoryPath
        return "the share \"\(shareName)\" at \(guestDirectoryPath)"
    }

    /// Passes a value through only if it cannot be read as shell syntax.
    ///
    /// These come from host constants today, so this guards against a future change that made them
    /// configurable rather than against the guest. Cheap, and it means the safety of the displayed command does
    /// not depend on remembering why it was safe.
    static func safeCommandValue(_ value: String?) -> String? {
        guard let value,
              !value.isEmpty,
              value.count <= 128,
              value.allSatisfy({ character in
                  character.isLetter
                      || character.isNumber
                      || character == "_"
                      || character == "-"
                      || character == "."
                      || character == ":"
                      || character == "\\"
              }) else {
            return nil
        }
        return value
    }

    static func readiness(
        capability: VMSharedFolderCapability,
        vmState: VMRuntimeState,
        guest: WindowsSharedFolderStatus?,
        hostMount: VMSharedFolderHostMountStatus
    ) -> VMSharedFolderReadiness {
        guard capability.isSupported else {
            return .unavailable
        }

        // Checked before the guest, because an unreachable agent on a stopped VM is expected rather
        // than a fault, and reporting it as an agent problem would send the user diagnosing the
        // wrong thing.
        guard vmState == .running else {
            return .awaitingVM
        }

        guard let guest else {
            return .awaitingGuestAgent
        }

        guard guest.isShared, guest.isWritable, guest.serverListening else {
            return .awaitingGuestShare
        }

        // The guest echoes the share name and path it actually used, and comparing them is the entire reason
        // they are on the wire. Without this the host could report `ready` and tell the user to mount
        // `smb://127.0.0.1:18445/VeilShared` while the guest had published something else.
        guard guestSharesRequestedFolder(capability: capability, guest: guest) else {
            return .awaitingGuestShare
        }

        guard hostMount.isMounted else {
            return .awaitingHostMount
        }

        return .ready
    }

    static func nextActions(
        readiness: VMSharedFolderReadiness,
        capability: VMSharedFolderCapability,
        guest: WindowsSharedFolderStatus?
    ) -> [String] {
        switch readiness {
        case .ready:
            return [
                "The shared folder is live. Files written in \(capability.expectedHostMountPath ?? "the mounted volume") appear immediately at \(capability.expectedGuestDirectoryPath ?? "the guest folder") inside Windows.",
                "Prefer this over drag-and-drop file open for anything large: the shared folder has no size cap, while file.open.request is limited to 50 MB."
            ]

        case .unavailable:
            switch capability.state {
            case .disabled:
                return [
                    "Unset \(capability.overrideEnvironmentVariable) or set it to \(QEMUWindowsSharedFolderTransport.guestSMB.rawValue) to turn the live shared folder back on.",
                    "Restart the VM afterwards so the boot plan picks up the port forward."
                ]
            case .unsupportedTransport:
                return [
                    "Turn on File Sharing in System Settings > General > Sharing and share the folder you want Windows to see.",
                    "Be aware this publishes the share on every network interface, not only to the guest.",
                    "Then inside Windows run: \(capability.transport.guestMountCommand ?? "net use").",
                    "Or set \(capability.overrideEnvironmentVariable)=\(QEMUWindowsSharedFolderTransport.guestSMB.rawValue) to use the guest-hosted share instead, which needs no host setup."
                ]
            case .hostPortUnavailable:
                return [
                    "Host port \(QEMUWindowsSharedFolderTransport.guestSMBHostPort) is in use, so the forward was left out of the boot plan.",
                    "Find the listener with: lsof -nP -iTCP:\(QEMUWindowsSharedFolderTransport.guestSMBHostPort) -sTCP:LISTEN",
                    "Free the port, then restart the VM so the plan is rebuilt with the forward."
                ]
            case .forwardMissingFromPlan:
                return [
                    "Restart Windows so the boot plan is rebuilt with the shared folder port forward.",
                    "Run veil-vmctl qemu-powerdown --json, then veil-vmctl qemu-start --json.",
                    "Confirm the new plan carries the forward with: veil-vmctl qemu-plan --json"
                ]
            case .notConfigured:
                return [
                    "Run veil-vmctl prepare --installer /path/to/Windows.iso to create a VM profile first.",
                    "Then run veil-vmctl shared-folder-status --json again."
                ]
            case .supported:
                return ["Run veil-vmctl shared-folder-status --json again."]
            }

        case .awaitingVM:
            return [
                "Start Windows first. The shared folder is served by the guest, so nothing is mountable while the VM is off.",
                "Run veil-vmctl qemu-start --json, or press Start in Veil.app."
            ]

        case .awaitingGuestAgent:
            return [
                "The Windows guest agent did not answer, so Veil cannot confirm the share exists.",
                "Run veil-vmctl guest-agent-wait --json, then veil-vmctl app-runtime-action --json --action repair-agent if it stays unreachable.",
                "An agent that predates the shared folder protocol also reports as unreachable here; reinstall it with veil-vmctl qemu-install-agent --json."
            ]

        case .awaitingGuestShare:
            var actions: [String] = []
            if let guest, !guestSharesRequestedFolder(capability: capability, guest: guest) {
                // Deliberately does not quote the guest's values back. They are guest-controlled strings, and
                // this text is read as Veil's own description of the situation.
                actions.append(
                    "Windows published a different share than Veil asked for, so Veil will not tell you to mount it. Veil expects \(hostAuthoredShareDescription(capability: capability)). Reinstall the guest agent with veil-vmctl qemu-install-agent --json if this persists."
                )
            }
            if let guest, guest.requiresElevation {
                actions.append(
                    "Creating an SMB share needs an administrator. In Windows, open PowerShell as administrator and run: \(hostAuthoredShareCommand(capability: capability))"
                )
            }
            if let guest, !guest.directoryExists {
                actions.append(
                    "The guest folder \(guest.guestDirectoryPath) does not exist yet. The agent creates it on the next shared.folder.request; if it cannot, create it manually."
                )
            }
            if let guest, !guest.serverListening {
                actions.append(
                    "Windows is not accepting SMB connections. Enable the firewall rules with: Enable-NetFirewallRule -DisplayGroup \"File and Printer Sharing\""
                )
                actions.append(
                    "This only exposes SMB on the guest's isolated usermode NAT network, which nothing but this Mac can reach."
                )
            }
            if let guest, guest.requiresCredentials {
                actions.append(
                    "Give the Windows account a password. Windows refuses network sign-in for blank-password accounts, so the mount fails without one."
                )
            }
            if actions.isEmpty {
                actions.append("Run veil-vmctl shared-folder-status --json again after the guest finishes setting the share up.")
            }
            actions.append("Then mount it on the Mac with: open \(capability.hostMountURL ?? "smb://")")
            return actions

        case .awaitingHostMount:
            return [
                "The guest is sharing the folder. Mount it on the Mac with: open \(capability.hostMountURL ?? "smb://")",
                "Sign in with the Windows account name and password when macOS asks.",
                "It mounts at \(capability.expectedHostMountPath ?? "/Volumes")."
            ]
        }
    }
}
