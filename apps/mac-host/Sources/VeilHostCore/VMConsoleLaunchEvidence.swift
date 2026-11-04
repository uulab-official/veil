import Foundation

public struct VMConsoleLaunchEvidence: Codable, Equatable, Sendable {
    public var provider: String
    public var pid: Int32?
    public var processLogPath: String
    public var monitorSocketPath: String
    public var qmpSocketPath: String?
    public var vncHost: String?
    public var vncPort: Int?
    public var consoleScreenshotPath: String?
    public var consoleScreenshotRefreshedAt: Date?
    public var previewStatus: VMConsolePreviewStatus
    public var startedAt: Date

    public var displaySurface: VMConsoleDisplaySurface {
        if let vncHost, let vncPort {
            return VMConsoleDisplaySurface(
                kind: .vncLoopback,
                endpoint: "\(vncHost):\(vncPort)",
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
        consoleScreenshotPath: String?,
        consoleScreenshotRefreshedAt: Date? = nil,
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
        self.consoleScreenshotPath = consoleScreenshotPath
        self.consoleScreenshotRefreshedAt = consoleScreenshotRefreshedAt
        self.previewStatus = previewStatus
        self.startedAt = startedAt
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
    case guestAgent
}
