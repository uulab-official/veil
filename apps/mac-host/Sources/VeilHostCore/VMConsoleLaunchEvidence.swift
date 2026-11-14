import Foundation

public struct VMConsoleLaunchEvidence: Codable, Equatable, Sendable {
    public var provider: String
    public var pid: Int32?
    public var processLogPath: String
    public var monitorSocketPath: String
    public var qmpSocketPath: String?
    public var vncHost: String?
    public var vncPort: Int?
    /// QEMU's display server on a Unix socket; see `QEMULaunchRecord.vncSocketPath`.
    public var vncSocketPath: String?
    public var consoleScreenshotPath: String?
    public var consoleScreenshotRefreshedAt: Date?
    /// The most recent live VNC classification. A recent blank frame means Windows is still
    /// booting (or its graphics head is unavailable); it must not be presented as a healthy console
    /// merely because a screenshot file exists.
    public var consoleVisualState: QEMUConsoleVisualState?
    public var consoleVisualStateAt: Date?
    public var previewStatus: VMConsolePreviewStatus
    public var startedAt: Date

    public var displaySurface: VMConsoleDisplaySurface {
        if let endpoint = RFBEndpoint(socketPath: vncSocketPath, host: vncHost, port: vncPort)?.description {
            return VMConsoleDisplaySurface(
                kind: .vncLoopback,
                endpoint: endpoint,
                screenshotPath: consoleScreenshotPath,
                isLiveCapable: true,
                validationCommand: VMRuntimeDeviceDefaults.liveDisplayValidationCommand
            )
        }

        if let consoleScreenshotPath {
            return VMConsoleDisplaySurface(
                kind: .screenshot,
                endpoint: nil,
                screenshotPath: consoleScreenshotPath,
                isLiveCapable: false,
                validationCommand: nil
            )
        }

        return .unavailable
    }

    public init(
        provider: String,
        pid: Int32?,
        processLogPath: String,
        monitorSocketPath: String,
        qmpSocketPath: String? = nil,
        vncHost: String? = nil,
        vncPort: Int? = nil,
        vncSocketPath: String? = nil,
        consoleScreenshotPath: String?,
        consoleScreenshotRefreshedAt: Date? = nil,
        consoleVisualState: QEMUConsoleVisualState? = nil,
        consoleVisualStateAt: Date? = nil,
        previewStatus: VMConsolePreviewStatus = .unavailable,
        startedAt: Date
    ) {
        self.provider = provider
        self.pid = pid
        self.processLogPath = processLogPath
        self.monitorSocketPath = monitorSocketPath
        self.qmpSocketPath = qmpSocketPath
        self.vncHost = vncHost
        self.vncPort = vncPort
        self.vncSocketPath = vncSocketPath
        self.consoleScreenshotPath = consoleScreenshotPath
        self.consoleScreenshotRefreshedAt = consoleScreenshotRefreshedAt
        self.consoleVisualState = consoleVisualState
        self.consoleVisualStateAt = consoleVisualStateAt
        self.previewStatus = previewStatus
        self.startedAt = startedAt
    }
}

extension VMConsoleLaunchEvidence {
    private static let blankConsoleBootGraceSeconds: TimeInterval = 180

    /// Treat a just-started VM with no classified live console as boot progress. The app can start
    /// waiting before `qemu-display-smoke` has persisted its first VNC classification, so requiring
    /// `.blank` here would still let a slow first boot fall through to agent repair after 90 seconds.
    public func isRecentlyBooting(asOf date: Date) -> Bool {
        guard date >= startedAt,
              date.timeIntervalSince(startedAt) <= Self.blankConsoleBootGraceSeconds else {
            return false
        }

        return consoleVisualState == nil || consoleVisualState == .blank
    }

    /// A launch that has exceeded the boot grace without a classified usable console is no longer
    /// safe to describe as ordinary waiting. Keep this separate from guest-agent health so recovery
    /// can stop/retry the boot path instead of repeatedly reinstalling the agent.
    public func isBootStalled(asOf date: Date) -> Bool {
        guard date >= startedAt,
              date.timeIntervalSince(startedAt) > Self.blankConsoleBootGraceSeconds else {
            return false
        }

        return consoleVisualState == nil || consoleVisualState == .blank
    }

    public func isRecentlyBlankDuringBoot(asOf date: Date) -> Bool {
        guard consoleVisualState == .blank,
              let consoleVisualStateAt,
              date >= consoleVisualStateAt,
              date.timeIntervalSince(consoleVisualStateAt) <= Self.blankConsoleBootGraceSeconds else {
            return false
        }

        return isRecentlyBooting(asOf: date)
    }
}

public enum VMConsoleDisplaySurfaceKind: String, Codable, Equatable, Sendable {
    case vncLoopback
    case screenshot
    case unavailable
}

public struct VMConsoleDisplaySurface: Codable, Equatable, Sendable {
    public var kind: VMConsoleDisplaySurfaceKind
    public var endpoint: String?
    public var screenshotPath: String?
    public var isLiveCapable: Bool
    public var plannedWidthInPixels: Int
    public var plannedHeightInPixels: Int
    public var scalingMode: String
    public var dynamicResolution: String
    public var retinaScaling: String
    public var validationCommand: String?

    public init(
        kind: VMConsoleDisplaySurfaceKind,
        endpoint: String?,
        screenshotPath: String?,
        isLiveCapable: Bool,
        plannedWidthInPixels: Int = VMRuntimeDeviceDefaults.graphicsWidthInPixels,
        plannedHeightInPixels: Int = VMRuntimeDeviceDefaults.graphicsHeightInPixels,
        scalingMode: String = VMRuntimeDeviceDefaults.displayScalingMode,
        dynamicResolution: String = VMRuntimeDeviceDefaults.dynamicResolutionPolicy,
        retinaScaling: String = VMRuntimeDeviceDefaults.retinaScalingPolicy,
        validationCommand: String? = nil
    ) {
        self.kind = kind
        self.endpoint = endpoint
        self.screenshotPath = screenshotPath
        self.isLiveCapable = isLiveCapable
        self.plannedWidthInPixels = plannedWidthInPixels
        self.plannedHeightInPixels = plannedHeightInPixels
        self.scalingMode = scalingMode
        self.dynamicResolution = dynamicResolution
        self.retinaScaling = retinaScaling
        self.validationCommand = validationCommand
    }

    public static let unavailable = VMConsoleDisplaySurface(
        kind: .unavailable,
        endpoint: nil,
        screenshotPath: nil,
        isLiveCapable: false,
        validationCommand: nil
    )
}

public enum VMConsolePreviewStatus: String, Codable, Equatable, Sendable {
    case fresh
    case stale
    case unavailable
}

public enum VMInstallEvidenceKind: String, Codable, Equatable, Sendable {
    case notConfigured
    case setupBlocked
    case sparseDisk
    case setupReady
    case profileFlag
    /// Windows Setup registered "Windows Boot Manager" in the VM's UEFI variables, so a bootable
    /// Windows is on the disk even before the guest agent has ever connected.
    case windowsBootManager
    case guestAgent
}
