import Foundation

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
    public var virtualDiskPath: String?
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
        virtualDiskPath: String? = nil,
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
        self.virtualDiskPath = virtualDiskPath
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
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support")
        return base
            .appendingPathComponent("Veil", isDirectory: true)
            .appendingPathComponent("Profiles", isDirectory: true)
    }
}
