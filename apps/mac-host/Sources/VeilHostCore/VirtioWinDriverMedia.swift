import CryptoKit
import Foundation

/// The Fedora virtio-win driver ISO that gives a one-click Windows 11 Arm install a working network.
///
/// Without driver media QEMU attaches `usb-net`, which Windows Arm binds as a serial port, so the
/// guest never gets an IPv4 address and the host cannot reach the agent. With this ISO attached the
/// boot plan switches to `virtio-net-pci` and the answer file installs NetKVM from it.
///
/// Veil downloads the ISO from Fedora onto the user's Mac and never redistributes it. Fedora
/// publishes no checksum for the ISO itself (the release `CHECKSUM` file lists only RPM MD5 sums),
/// so Veil pins one release and the SHA-256 recorded when that release was adopted; a new release
/// needs a new pin. See docs/legal-support-notes.md.
public enum VirtioWinDriverMedia {
    public static let version = "0.1.302"
    public static let downloadURL = URL(
        string: "https://fedorapeople.org/groups/virt/virtio-win/direct-downloads/archive-virtio/virtio-win-0.1.302-1/virtio-win-0.1.302.iso"
    )!
    public static let sha256 = "303f7ae40dad495d6ae474fdc571df58958a4dbc5c37a522d80f9a203867949d"
    public static let byteCount: Int64 = 877_373_440
    public static let fileName = "virtio-win-\(version).iso"

    /// Every release labels its volume `virtio-win-<version>`; the answer file finds the drive by
    /// this prefix, so a later pin needs no answer-file change.
    public static let volumeLabelPrefix = "virtio-win"

    /// The driver folder the answer file installs, from `<folder>\w11\ARM64`. NetKVM is the only
    /// one Veil needs today: the boot plan pairs this ISO with `virtio-net-pci`. The display stays
    /// on ramfb plus virtio-gpu without viogpudo, and the system disk on NVMe, which Windows Setup
    /// drives with inbox drivers (docs/install-flow.md records the virtio-gpu and storage findings).
    public static let networkDriverFolder = "NetKVM"

    public static func allowsDownload(from url: URL?) -> Bool {
        guard let url,
              url.scheme?.lowercased() == "https",
              url.host?.lowercased() == "fedorapeople.org" else {
            return false
        }

        return url.path.hasPrefix("/groups/virt/virtio-win/")
    }

    public static func defaultDownloadsDirectory() -> URL {
        VeilApplicationSupport.directory.appendingPathComponent("Downloads", isDirectory: true)
    }

    public static func failureReason(actualSHA256: String) -> String? {
        actualSHA256.lowercased() == sha256
            ? nil
            : "The VirtIO driver ISO did not match the SHA-256 Veil pins for virtio-win \(version). Veil removed the download."
    }

    public static func sha256(of url: URL) throws -> String {
        let handle = try FileHandle(forReadingFrom: url)
        defer {
            try? handle.close()
        }

        var hasher = SHA256()
        while let data = try handle.read(upToCount: 8 * 1_024 * 1_024), !data.isEmpty {
            hasher.update(data: data)
        }
        return hasher.finalize().map { String(format: "%02x", $0) }.joined()
    }
}

public enum VirtioWinDriverMediaError: Error, LocalizedError, Equatable {
    case rejectedURL(String)
    case httpStatus(Int)
    case integrityCheckFailed(String)

    public var errorDescription: String? {
        switch self {
        case .rejectedURL(let url):
            "Veil only downloads VirtIO drivers over HTTPS from fedorapeople.org, not \(url)."
        case .httpStatus(let status):
            "Fedora answered the VirtIO driver download with HTTP \(status)."
        case .integrityCheckFailed(let reason):
            reason
        }
    }
}

/// Downloads and verifies the pinned virtio-win ISO once per process. Concurrent callers share one
/// transfer, so the assistant can start it next to the Windows download and await it later.
public actor VirtioWinDriverMediaProvider {
    public typealias Transfer = @Sendable (URL, URL) async throws -> Void

    public static let shared = VirtioWinDriverMediaProvider()

    private let directory: @Sendable () -> URL
    private let transfer: Transfer
    private let hasher: @Sendable (URL) throws -> String
    private var inFlight: Task<URL, any Error>?
    private var verifiedURL: URL?

    public init(
        directory: @escaping @Sendable () -> URL = VirtioWinDriverMedia.defaultDownloadsDirectory,
        transfer: @escaping Transfer = VirtioWinDriverMediaProvider.download,
        hasher: @escaping @Sendable (URL) throws -> String = VirtioWinDriverMedia.sha256(of:)
    ) {
        self.directory = directory
        self.transfer = transfer
        self.hasher = hasher
    }

    /// Starts the download without waiting for it.
    public func prefetch() {
        _ = task()
    }

    /// The ISO when it is already on this Mac and still matches the pin. It never downloads, so a
    /// start can use it without waiting on the network.
    public func cachedMedia() async -> URL? {
        if let verifiedURL, FileManager.default.fileExists(atPath: verifiedURL.path) {
            return verifiedURL
        }
        guard inFlight == nil else {
            return nil
        }

        let destination = directory().appendingPathComponent(VirtioWinDriverMedia.fileName)
        guard FileManager.default.fileExists(atPath: destination.path),
              (try? await Self.hash(destination, hasher: hasher)) == VirtioWinDriverMedia.sha256 else {
            return nil
        }
        verifiedURL = destination
        return destination
    }

    public func ensureMedia() async throws -> URL {
        if let verifiedURL, FileManager.default.fileExists(atPath: verifiedURL.path) {
            return verifiedURL
        }

        let current = task()
        do {
            let url = try await current.value
            verifiedURL = url
            inFlight = nil
            return url
        } catch {
            inFlight = nil
            throw error
        }
    }

    private func task() -> Task<URL, any Error> {
        if let inFlight {
            return inFlight
        }

        let directory = directory
        let transfer = transfer
        let hasher = hasher
        let task = Task {
            try await Self.fetchVerifiedMedia(directory: directory(), transfer: transfer, hasher: hasher)
        }
        inFlight = task
        return task
    }

    private static func fetchVerifiedMedia(
        directory: URL,
        transfer: Transfer,
        hasher: @escaping @Sendable (URL) throws -> String
    ) async throws -> URL {
        let fileManager = FileManager.default
        try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        let destination = directory.appendingPathComponent(VirtioWinDriverMedia.fileName)

        // A file already in place is reused only if it still hashes to the pin.
        if fileManager.fileExists(atPath: destination.path) {
            if try await hash(destination, hasher: hasher) == VirtioWinDriverMedia.sha256 {
                return destination
            }
            try? fileManager.removeItem(at: destination)
        }

        let partial = directory.appendingPathComponent("\(VirtioWinDriverMedia.fileName).download")
        try? fileManager.removeItem(at: partial)
        defer {
            try? fileManager.removeItem(at: partial)
        }

        try await transfer(VirtioWinDriverMedia.downloadURL, partial)
        let actual = try await hash(partial, hasher: hasher)
        if let reason = VirtioWinDriverMedia.failureReason(actualSHA256: actual) {
            throw VirtioWinDriverMediaError.integrityCheckFailed(reason)
        }

        try fileManager.moveItem(at: partial, to: destination)
        return destination
    }

    private static func hash(_ url: URL, hasher: @escaping @Sendable (URL) throws -> String) async throws -> String {
        try await Task.detached(priority: .utility) {
            try hasher(url).lowercased()
        }.value
    }

    /// Downloads with a session that refuses any redirect away from HTTPS fedorapeople.org.
    public static let download: Transfer = { source, destination in
        guard VirtioWinDriverMedia.allowsDownload(from: source) else {
            throw VirtioWinDriverMediaError.rejectedURL(source.absoluteString)
        }

        let session = URLSession(
            configuration: .ephemeral,
            delegate: FedoraOnlyRedirectDelegate(),
            delegateQueue: nil
        )
        defer {
            session.finishTasksAndInvalidate()
        }

        let (downloadedURL, response) = try await session.download(from: source)
        defer {
            try? FileManager.default.removeItem(at: downloadedURL)
        }
        if let http = response as? HTTPURLResponse, http.statusCode != 200 {
            throw VirtioWinDriverMediaError.httpStatus(http.statusCode)
        }
        guard VirtioWinDriverMedia.allowsDownload(from: response.url) else {
            throw VirtioWinDriverMediaError.rejectedURL(response.url?.absoluteString ?? "an unknown address")
        }

        try FileManager.default.moveItem(at: downloadedURL, to: destination)
    }
}

private final class FedoraOnlyRedirectDelegate: NSObject, URLSessionTaskDelegate {
    func urlSession(
        _ session: URLSession,
        task: URLSessionTask,
        willPerformHTTPRedirection response: HTTPURLResponse,
        newRequest request: URLRequest,
        completionHandler: @escaping @Sendable (URLRequest?) -> Void
    ) {
        completionHandler(VirtioWinDriverMedia.allowsDownload(from: request.url) ? request : nil)
    }
}
