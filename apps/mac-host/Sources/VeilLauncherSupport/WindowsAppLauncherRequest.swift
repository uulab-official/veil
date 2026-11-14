import Foundation

/// What a Windows app launcher asks Veil to do: open its app, optionally with Mac files.
///
/// Written by the launcher into ``WindowsAppLauncherRequestStore`` and named to Veil with
/// `veil://launcher-request?id=<uuid>`. Keeping the file list out of the URL is the point: the URL scheme
/// is open to every app and web page, the request folder is not.
public struct WindowsAppLauncherRequest: Codable, Equatable, Sendable {
    public static let currentVersion = 1

    public var version: Int
    public var appId: String
    /// Absolute POSIX paths of the files the user opened with the launcher. Empty for a plain app launch.
    public var filePaths: [String]
    public var createdAt: Date

    public init(appId: String, filePaths: [String] = [], createdAt: Date = Date()) {
        self.version = Self.currentVersion
        self.appId = appId
        self.filePaths = filePaths
        self.createdAt = createdAt
    }

    public var fileURLs: [URL] {
        filePaths.map { URL(fileURLWithPath: $0) }
    }
}

public enum WindowsAppLauncherRequestError: Error, Equatable, Sendable {
    case missing
    case unreadable
    case unsupportedVersion(Int)
    case expired
    case invalidAppId
    case relativeFilePath
}

/// The folder launchers and Veil share for requests: `~/Library/Application Support/Veil/Launcher Requests`.
///
/// A request is consumed once: ``take(id:now:)`` deletes it before returning, so replaying the same
/// `veil://launcher-request` URL does nothing. Requests older than ``maximumAge`` are refused, so a URL
/// that sat in a log or browser history cannot reopen files later.
public struct WindowsAppLauncherRequestStore: Sendable {
    public static let folderName = "Launcher Requests"
    /// Long enough to cover a cold start of Veil itself, which reads the request as soon as it can handle
    /// URLs; Windows booting afterwards is not counted against it.
    public static let maximumAge: TimeInterval = 120

    public let directory: URL

    public init(directory: URL) {
        self.directory = directory
    }

    /// The store at `<applicationSupport>/Launcher Requests`, where `applicationSupport` is Veil's own folder.
    public init(veilApplicationSupport: URL) {
        self.init(directory: veilApplicationSupport.appendingPathComponent(Self.folderName, isDirectory: true))
    }

    /// The default location, honouring `VEIL_APPLICATION_SUPPORT_DIRECTORY` the way Veil itself does.
    public static func standard(environment: [String: String] = ProcessInfo.processInfo.environment) -> Self {
        if let override = environment["VEIL_APPLICATION_SUPPORT_DIRECTORY"], !override.isEmpty {
            return Self(veilApplicationSupport: URL(fileURLWithPath: override, isDirectory: true))
        }
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.homeDirectoryForCurrentUser
                .appendingPathComponent("Library/Application Support", isDirectory: true)
        return Self(veilApplicationSupport: base.appendingPathComponent("Veil", isDirectory: true))
    }

    public func url(for id: UUID) -> URL {
        directory.appendingPathComponent("\(id.uuidString).json", isDirectory: false)
    }

    @discardableResult
    public func write(_ request: WindowsAppLauncherRequest, id: UUID = UUID()) throws -> UUID {
        try FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true,
            attributes: [.posixPermissions: 0o700]
        )
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(request)
        try data.write(to: url(for: id), options: [.atomic])
        try? FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url(for: id).path)
        return id
    }

    /// Reads and deletes a request. Every refusal also deletes it, so nothing is left to retry.
    public func take(id: UUID, now: Date = Date()) throws -> WindowsAppLauncherRequest {
        let fileURL = url(for: id)
        guard FileManager.default.fileExists(atPath: fileURL.path) else {
            throw WindowsAppLauncherRequestError.missing
        }
        defer { try? FileManager.default.removeItem(at: fileURL) }

        let request: WindowsAppLauncherRequest
        do {
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            request = try decoder.decode(WindowsAppLauncherRequest.self, from: Data(contentsOf: fileURL))
        } catch {
            throw WindowsAppLauncherRequestError.unreadable
        }

        guard request.version == WindowsAppLauncherRequest.currentVersion else {
            throw WindowsAppLauncherRequestError.unsupportedVersion(request.version)
        }
        // A little slack for clocks: the launcher and Veil read the same clock, but a request written a moment
        // "in the future" should not count as expired.
        let age = now.timeIntervalSince(request.createdAt)
        guard age <= Self.maximumAge, age >= -5 else {
            throw WindowsAppLauncherRequestError.expired
        }
        guard VeilURLRoute.isValidAppId(request.appId) else {
            throw WindowsAppLauncherRequestError.invalidAppId
        }
        guard request.filePaths.allSatisfy({ $0.hasPrefix("/") }) else {
            throw WindowsAppLauncherRequestError.relativeFilePath
        }
        return request
    }

    /// Deletes requests nobody took, for example because Veil was not installed when a launcher ran.
    public func removeExpired(now: Date = Date()) {
        guard let entries = try? FileManager.default.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: [.contentModificationDateKey]
        ) else {
            return
        }
        for entry in entries where entry.pathExtension == "json" {
            let modified = (try? entry.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate
            if let modified, now.timeIntervalSince(modified) > Self.maximumAge {
                try? FileManager.default.removeItem(at: entry)
            }
        }
    }
}
