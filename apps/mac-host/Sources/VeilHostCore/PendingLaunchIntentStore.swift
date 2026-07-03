import Foundation

public struct PendingLaunchIntent: Codable, Equatable, Sendable {
    public var appId: String?

    public init(appId: String?) {
        self.appId = appId
    }
}

public protocol PendingLaunchIntentStore: Sendable {
    func load() async throws -> PendingLaunchIntent?
    func save(_ intent: PendingLaunchIntent) async throws
}

public struct JSONPendingLaunchIntentStore: PendingLaunchIntentStore {
    private let directory: URL
    private let fileName: String
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder

    public init(
        directory: URL = JSONWindowRestoreIntentStore.defaultDirectory,
        fileName: String = "pending-launch-intent.json"
    ) {
        self.directory = directory
        self.fileName = fileName

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        self.encoder = encoder
        self.decoder = JSONDecoder()
    }

    public func load() async throws -> PendingLaunchIntent? {
        let url = intentURL
        guard FileManager.default.fileExists(atPath: url.path) else {
            return nil
        }

        let data = try Data(contentsOf: url)
        return try decoder.decode(PendingLaunchIntent.self, from: data)
    }

    public func save(_ intent: PendingLaunchIntent) async throws {
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
}
