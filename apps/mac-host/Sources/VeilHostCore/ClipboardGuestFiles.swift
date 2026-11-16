import CoreServices
import Darwin
import Foundation

/// Why a Windows file copy did not reach the Mac pasteboard. Logged, not shown: the guest chose to send it,
/// and a hostile guest must not be able to put text in front of the user by sending bad copies.
public enum ClipboardGuestFilesRefusal: Error, Equatable, LocalizedError, Sendable {
    case malformedPath(String)
    case nameNotAllowed(String)
    case duplicateName(String)
    case tooManyFiles(count: Int)
    case notARegularFile(name: String)
    case tooLarge
    case copyFailed(detail: String)

    public var errorDescription: String? {
        switch self {
        case .malformedPath(let path):
            "The guest named a path outside its clipboard staging folder: \(path)"
        case .nameNotAllowed(let name):
            "The guest file name \(name) is not allowed on the Mac."
        case .duplicateName(let name):
            "Two guest files are both named \(name)."
        case .tooManyFiles(let count):
            "The guest named \(count) files; at most \(ClipboardGuestFiles.maximumFileCount) are copied."
        case .notARegularFile(let name):
            "\(name) in the shared folder is not a regular file."
        case .tooLarge:
            "The guest files exceed the \(ClipboardGuestFiles.maximumTotalBytes / 1_048_576) MiB copy limit."
        case .copyFailed(let detail):
            "The guest files could not be copied to the Mac. \(detail)"
        }
    }
}

/// A checked guest-origin `clipboard.files.set`: which share entries to read and what each is called on
/// the Mac. Built only by ``ClipboardGuestFiles/plan(_:)``.
public struct ClipboardGuestFilesPlan: Equatable, Sendable {
    /// As received, relative to the share, with Windows separators.
    public var relativePaths: [String]
    /// The destination name of each entry, in the same order, after the Mac name rules.
    public var fileNames: [String]
}

/// Guest-to-host file copy. See `docs/protocol.md` "Clipboard Files", "Guest to host".
///
/// The guest names files inside its own share. The host copies their bytes, through descriptors opened
/// without following links, into a folder it creates in `~/Downloads`, quarantines them, and only then puts
/// those copies on the pasteboard. No guest-chosen path ever reaches `NSPasteboard`, and the guest cannot
/// reach the copies once they are written.
public enum ClipboardGuestFiles {
    public static let guestDirectoryName = "Veil Clipboard from Windows"
    public static let destinationDirectoryName = "Veil Clipboard"
    public static let maximumFileCount = ClipboardFilePaste.maximumFileCount
    public static let maximumTotalBytes = ClipboardFilePaste.maximumTotalBytes
    public static let retainedBatchCount = ClipboardFilePaste.retainedBatchCount
    static let maximumFileNameUTF8Length = 255
    private static let copyChunkSize = 1_048_576

    /// `~/Downloads/Veil Clipboard`, a folder the user can see and clean up in Finder.
    public static func defaultDestinationRoot(fileManager: FileManager = .default) -> URL {
        let downloads = fileManager.urls(for: .downloadsDirectory, in: .userDomainMask).first
            ?? fileManager.homeDirectoryForCurrentUser.appending(path: "Downloads", directoryHint: .isDirectory)
        return downloads.appending(path: destinationDirectoryName, directoryHint: .isDirectory)
    }

    /// Checks the message shape. Every entry must be `Veil Clipboard from Windows\<batch>\<name>` in one
    /// batch, and every name must survive the Mac rules. One bad entry refuses the whole message.
    public static func plan(_ message: ClipboardFilesSet) throws(ClipboardGuestFilesRefusal) -> ClipboardGuestFilesPlan {
        guard message.origin == "guest",
              message.shareName == QEMUWindowsSharedFolderTransport.shareName,
              !message.relativePaths.isEmpty else {
            throw .malformedPath(message.relativePaths.first ?? "")
        }
        guard message.relativePaths.count <= maximumFileCount else {
            throw .tooManyFiles(count: message.relativePaths.count)
        }

        var batch: String?
        var seen: Set<String> = []
        var fileNames: [String] = []
        for path in message.relativePaths {
            let components = path.split(separator: "\\", omittingEmptySubsequences: false).map(String.init)
            guard path.count <= ClipboardFilePaste.maximumRelativePathLength,
                  components.count == 3,
                  components[0] == guestDirectoryName,
                  ClipboardFilePaste.isBatchName(components[1]),
                  batch == nil || batch == components[1] else {
                throw .malformedPath(path)
            }
            batch = components[1]

            guard let name = macFileName(forGuestName: components[2]) else {
                throw .nameNotAllowed(components[2])
            }
            // APFS and HFS+ volumes are case-insensitive by default, so these would collide in one folder.
            guard seen.insert(name.lowercased()).inserted else {
                throw .duplicateName(name)
            }
            fileNames.append(name)
        }

        return ClipboardGuestFilesPlan(relativePaths: message.relativePaths, fileNames: fileNames)
    }

    /// The name a guest file gets on the Mac, or nil when it is refused.
    ///
    /// Windows rules first (the guest's own names already pass them, so failing one means the guest is not
    /// the agent), then the Mac's: the APFS length limit, no bidirectional controls that would let
    /// `invoice` + U+202E + `fdp.app` display as `invoiceppa.pdf`, and no leading dot, which would hide the
    /// file in Downloads.
    public static func macFileName(forGuestName name: String) -> String? {
        guard ClipboardFilePaste.isAllowedWindowsFileName(name),
              !name.unicodeScalars.contains(where: isBidirectionalControl) else {
            return nil
        }

        var result = name
        if result.hasPrefix(".") {
            result = "_" + result.dropFirst()
        }
        guard result.utf8.count <= maximumFileNameUTF8Length else {
            return nil
        }
        return result
    }

    private static func isBidirectionalControl(_ scalar: Unicode.Scalar) -> Bool {
        switch scalar.value {
        case 0x200E, 0x200F, 0x202A...0x202E, 0x2066...0x2069, 0x061C:
            true
        default:
            false
        }
    }

    /// Copies the planned files from the mounted share into `<destinationRoot>/<new batch>/`, quarantines
    /// them, prunes older batches, and returns the copies in plan order. A failure removes the partial batch.
    public static func copy(
        _ plan: ClipboardGuestFilesPlan,
        fromShareAt shareRoot: URL,
        into destinationRoot: URL,
        now: Date = Date(),
        batchSuffix: String = ClipboardFilePaste.randomBatchSuffix(),
        fileManager: FileManager = .default
    ) throws(ClipboardGuestFilesRefusal) -> [URL] {
        let batchDirectory = destinationRoot.appending(
            path: ClipboardFilePaste.batchName(at: now, suffix: batchSuffix),
            directoryHint: .isDirectory
        )
        do {
            try fileManager.createDirectory(at: destinationRoot, withIntermediateDirectories: true)
            // Not intermediate: the batch is new, and an existing folder of that name is not ours to fill.
            try fileManager.createDirectory(at: batchDirectory, withIntermediateDirectories: false)
        } catch {
            throw .copyFailed(detail: error.localizedDescription)
        }

        var copies: [URL] = []
        do throws(ClipboardGuestFilesRefusal) {
            let rootDescriptor = open(shareRoot.path, O_RDONLY | O_DIRECTORY | O_CLOEXEC)
            guard rootDescriptor >= 0 else {
                throw .copyFailed(detail: posixDetail("Opening the shared folder"))
            }
            defer { close(rootDescriptor) }

            var remaining = maximumTotalBytes
            for (relativePath, name) in zip(plan.relativePaths, plan.fileNames) {
                let destination = batchDirectory.appending(path: name, directoryHint: .notDirectory)
                try copyEntry(
                    relativePath: relativePath,
                    displayName: name,
                    shareRoot: rootDescriptor,
                    to: destination,
                    remaining: &remaining
                )
                quarantine(destination)
                copies.append(destination)
            }
        } catch {
            try? fileManager.removeItem(at: batchDirectory)
            throw error
        }

        ClipboardFilePaste.pruneBatches(in: destinationRoot, fileManager: fileManager)
        return copies
    }

    /// Opens each path component relative to the one before with `O_NOFOLLOW`, so a link anywhere on the
    /// path fails instead of being followed out of the share, then streams the bytes while counting them
    /// against the remaining budget. The size the guest staged is never trusted: a file can grow mid-copy.
    private static func copyEntry(
        relativePath: String,
        displayName: String,
        shareRoot: Int32,
        to destination: URL,
        remaining: inout Int64
    ) throws(ClipboardGuestFilesRefusal) {
        let components = relativePath.split(separator: "\\").map(String.init)
        var directory = shareRoot
        var opened: [Int32] = []
        defer { opened.forEach { close($0) } }
        for component in components.dropLast() {
            let next = openat(directory, component, O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC)
            guard next >= 0 else {
                throw .notARegularFile(name: displayName)
            }
            opened.append(next)
            directory = next
        }

        let source = openat(directory, components.last ?? "", O_RDONLY | O_NOFOLLOW | O_NONBLOCK | O_CLOEXEC)
        guard source >= 0 else {
            throw .notARegularFile(name: displayName)
        }
        defer { close(source) }
        var status = stat()
        guard fstat(source, &status) == 0, (status.st_mode & S_IFMT) == S_IFREG else {
            throw .notARegularFile(name: displayName)
        }
        guard Int64(status.st_size) <= remaining else {
            throw .tooLarge
        }

        // 0644 and O_EXCL: never executable, and never written through something already at that name.
        let output = open(destination.path, O_WRONLY | O_CREAT | O_EXCL | O_NOFOLLOW | O_CLOEXEC, 0o644)
        guard output >= 0 else {
            throw .copyFailed(detail: posixDetail("Creating \(displayName)"))
        }
        defer { close(output) }

        var buffer = [UInt8](repeating: 0, count: copyChunkSize)
        while true {
            let count = buffer.withUnsafeMutableBytes { read(source, $0.baseAddress, copyChunkSize) }
            if count == 0 {
                break
            }
            guard count > 0 else {
                if errno == EINTR || errno == EAGAIN {
                    continue
                }
                throw .copyFailed(detail: posixDetail("Reading \(displayName)"))
            }
            remaining -= Int64(count)
            guard remaining >= 0 else {
                throw .tooLarge
            }
            var written = 0
            while written < count {
                let result = buffer.withUnsafeBytes { write(output, $0.baseAddress! + written, count - written) }
                guard result > 0 else {
                    if result < 0, errno == EINTR {
                        continue
                    }
                    throw .copyFailed(detail: posixDetail("Writing \(displayName)"))
                }
                written += result
            }
        }
    }

    /// The same quarantine a browser download gets, so opening the copy goes through Gatekeeper. Best effort:
    /// a volume without extended attributes cannot hold it, and refusing the copy would not make it safer.
    static func quarantine(_ url: URL) {
        let properties: [String: Any] = [
            kLSQuarantineAgentNameKey as String: "Veil",
            kLSQuarantineTypeKey as String: kLSQuarantineTypeOtherDownload as String,
        ]
        do {
            try (url as NSURL).setResourceValue(properties, forKey: .quarantinePropertiesKey)
        } catch {
            VeilLog.agent.notice(
                "Could not quarantine a copied guest file: \(error.localizedDescription, privacy: .public)"
            )
        }
    }

    private static func posixDetail(_ action: String) -> String {
        "\(action) failed: \(String(cString: strerror(errno)))."
    }
}
