import Foundation

public struct VMResourcePlan: Codable, Equatable, Sendable {
    public var cpuCount: Int
    public var memoryMB: Int
    public var diskGB: Int

    public init(cpuCount: Int, memoryMB: Int, diskGB: Int) {
        self.cpuCount = cpuCount
        self.memoryMB = memoryMB
        self.diskGB = diskGB
    }
}

public enum VMResourcePolicy {
    public static func automatic(
        processorCount: Int,
        physicalMemoryBytes: UInt64
    ) -> VMResourcePlan {
        let processorCount = max(1, processorCount)
        let hostAwareCPUCap = max(2, min(8, processorCount - 1))
        let cpuCount = min(max(2, processorCount / 2), hostAwareCPUCap)

        let physicalMemoryMB = Int(physicalMemoryBytes / 1_024 / 1_024)
        let quarterMemoryMB = (physicalMemoryMB / 4 / 1_024) * 1_024
        let memoryMB = min(max(quarterMemoryMB, 4_096), 16_384)

        return VMResourcePlan(cpuCount: cpuCount, memoryMB: memoryMB, diskGB: 128)
    }

    public static func currentHostPlan() -> VMResourcePlan {
        automatic(
            processorCount: ProcessInfo.processInfo.processorCount,
            physicalMemoryBytes: ProcessInfo.processInfo.physicalMemory
        )
    }
}

/// The CPU and memory range a user may give Windows on this Mac. Windows 11 needs at least two
/// cores and 4 GB; the Mac keeps one core and a quarter of its memory (at least 4 GB) for itself.
public struct VMResourceLimits: Equatable, Sendable {
    public static let minimumCPUCount = 2
    public static let minimumMemoryMB = 4_096
    public static let memoryStepMB = 1_024

    public var maximumCPUCount: Int
    public var maximumMemoryMB: Int

    public init(processorCount: Int, physicalMemoryBytes: UInt64) {
        maximumCPUCount = max(Self.minimumCPUCount, processorCount - 1)
        let physicalMemoryMB = Int(physicalMemoryBytes / 1_024 / 1_024)
        let reservedMB = max(4_096, physicalMemoryMB / 4)
        let available = (physicalMemoryMB - reservedMB) / Self.memoryStepMB * Self.memoryStepMB
        maximumMemoryMB = max(Self.minimumMemoryMB, available)
    }

    public static func currentHost() -> VMResourceLimits {
        VMResourceLimits(
            processorCount: ProcessInfo.processInfo.processorCount,
            physicalMemoryBytes: ProcessInfo.processInfo.physicalMemory
        )
    }

    public func clampedCPUCount(_ count: Int) -> Int {
        min(max(count, Self.minimumCPUCount), maximumCPUCount)
    }

    /// Rounds to whole gigabytes so QEMU and Windows see the same size the settings show.
    public func clampedMemoryMB(_ memoryMB: Int) -> Int {
        let rounded = Int((Double(memoryMB) / Double(Self.memoryStepMB)).rounded()) * Self.memoryStepMB
        return min(max(rounded, Self.minimumMemoryMB), maximumMemoryMB)
    }
}

public struct VMProfile: Codable, Equatable, Identifiable, Sendable {
    public var id: String
    public var name: String
    public var os: String
    public var cpuCount: Int
    public var memoryMB: Int
    public var diskGB: Int
    public var autoStart: Bool
    public var suspendOnQuit: Bool
    public var sharedFolderPath: String
    public var installerMediaPath: String?
    public var installerMediaBookmarkData: Data?
    public var driverMediaPath: String?
    public var driverMediaBookmarkData: Data?
    public var virtualDiskPath: String?
    public var virtualDiskBookmarkData: Data?
    public var windowsInstalled: Bool?
    public var guestAgentVersion: String?
    public var guestAgentConnectedAt: Date?
    /// The local Windows account the next install creates; nil follows this Mac's user name.
    public var windowsAccountName: String?
    public var createdAt: Date

    public init(
        id: String,
        name: String,
        os: String,
        cpuCount: Int,
        memoryMB: Int,
        diskGB: Int,
        autoStart: Bool,
        suspendOnQuit: Bool,
        sharedFolderPath: String,
        installerMediaPath: String? = nil,
        installerMediaBookmarkData: Data? = nil,
        driverMediaPath: String? = nil,
        driverMediaBookmarkData: Data? = nil,
        virtualDiskPath: String? = nil,
        virtualDiskBookmarkData: Data? = nil,
        windowsInstalled: Bool? = nil,
        guestAgentVersion: String? = nil,
        guestAgentConnectedAt: Date? = nil,
        windowsAccountName: String? = nil,
        createdAt: Date
    ) {
        self.id = id
        self.name = name
        self.os = os
        self.cpuCount = cpuCount
        self.memoryMB = memoryMB
        self.diskGB = diskGB
        self.autoStart = autoStart
        self.suspendOnQuit = suspendOnQuit
        self.sharedFolderPath = sharedFolderPath
        self.installerMediaPath = installerMediaPath
        self.installerMediaBookmarkData = installerMediaBookmarkData
        self.driverMediaPath = driverMediaPath
        self.driverMediaBookmarkData = driverMediaBookmarkData
        self.virtualDiskPath = virtualDiskPath
        self.virtualDiskBookmarkData = virtualDiskBookmarkData
        self.windowsInstalled = windowsInstalled
        self.guestAgentVersion = guestAgentVersion
        self.guestAgentConnectedAt = guestAgentConnectedAt
        self.windowsAccountName = windowsAccountName
        self.createdAt = createdAt
    }

    public static func defaultWindows11Arm(
        createdAt: Date = Date(),
        homeDirectory: URL = FileManager.default.homeDirectoryForCurrentUser
    ) -> VMProfile {
        VMProfile(
            id: "vm_default_windows11",
            name: "Windows 11 Arm",
            os: "windows-arm64",
            cpuCount: 4,
            memoryMB: 8192,
            diskGB: 128,
            autoStart: true,
            suspendOnQuit: true,
            sharedFolderPath: homeDirectory.appendingPathComponent("Veil Shared").path,
            createdAt: createdAt
        )
    }

    public func withoutSecurityScopedBookmarks() -> VMProfile {
        var profile = self
        profile.installerMediaBookmarkData = nil
        profile.driverMediaBookmarkData = nil
        profile.virtualDiskBookmarkData = nil
        return profile
    }
}

public protocol VMProfileStore: Sendable {
    func load() async throws -> VMProfile?
    func save(_ profile: VMProfile) async throws
}

public struct JSONVMProfileStore: VMProfileStore {
    private let directory: URL
    private let fileName: String
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder

    public init(
        directory: URL = Self.defaultDirectory,
        fileName: String = "default-vm-profile.json"
    ) {
        self.directory = directory
        self.fileName = fileName

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        self.encoder = encoder

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        self.decoder = decoder
    }

    public func load() async throws -> VMProfile? {
        let url = profileURL
        guard FileManager.default.fileExists(atPath: url.path) else {
            return nil
        }

        let data = try Data(contentsOf: url)
        return try decoder.decode(VMProfile.self, from: data)
    }

    public func save(_ profile: VMProfile) async throws {
        try FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true
        )
        let data = try encoder.encode(profile)
        try data.write(to: profileURL, options: [.atomic])
    }

    private var profileURL: URL {
        directory.appendingPathComponent(fileName)
    }

    public static var defaultDirectory: URL {
        VeilApplicationSupport.directory
            .appendingPathComponent("Profiles", isDirectory: true)
    }
}
