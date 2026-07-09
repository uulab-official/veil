import Foundation

public struct WindowRestoreIntent: Codable, Equatable, Sendable {
    public var appIds: [String]
    public var appWindowCounts: [String: Int]?

    public init(appIds: [String], appWindowCounts: [String: Int]? = nil) {
        self.appIds = appIds
        self.appWindowCounts = appWindowCounts
    }

    public var appIdsForRestoreLaunches: [String] {
        appIds.flatMap { appId in
            Array(repeating: appId, count: max(1, appWindowCounts?[appId] ?? 1))
        }
    }

    public var normalizedAppWindowCounts: [String: Int] {
        Dictionary(uniqueKeysWithValues: appIds.map { appId in
            (appId, max(1, appWindowCounts?[appId] ?? 1))
        })
    }
}

public protocol WindowRestoreIntentStore: Sendable {
    func load() async throws -> WindowRestoreIntent?
    func save(_ intent: WindowRestoreIntent) async throws
}

public struct JSONWindowRestoreIntentStore: WindowRestoreIntentStore {
    private let directory: URL
    private let fileName: String
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder

    public init(
        directory: URL = Self.defaultDirectory,
        fileName: String = "window-restore-intent.json"
    ) {
        self.directory = directory
        self.fileName = fileName

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        self.encoder = encoder
        self.decoder = JSONDecoder()
    }

    public func load() async throws -> WindowRestoreIntent? {
        let url = intentURL
        guard FileManager.default.fileExists(atPath: url.path) else {
            return nil
        }

        let data = try Data(contentsOf: url)
        return try decoder.decode(WindowRestoreIntent.self, from: data)
    }

    public func save(_ intent: WindowRestoreIntent) async throws {
        try FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true
        )
        let data = try encoder.encode(intent)
        try data.write(to: intentURL, options: [.atomic])
    }

    private var intentURL: URL {
        directory.appendingPathComponent(fileName)
    }

    public static var defaultDirectory: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.homeDirectoryForCurrentUser
                .appendingPathComponent("Library", isDirectory: true)
                .appendingPathComponent("Application Support", isDirectory: true)
        return base
            .appendingPathComponent("Veil", isDirectory: true)
            .appendingPathComponent("Windows Apps", isDirectory: true)
    }
}
