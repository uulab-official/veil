import Foundation

/// Why a Finder file selection was not pasted into Windows. Each case is shown to the user; a partial paste
/// is never attempted, because pasting three of five files looks like success.
public enum ClipboardFilePasteRefusal: Error, Equatable, LocalizedError, Sendable {
    case sharedFolderUnavailable
    case notARegularFile(name: String)
    case tooManyFiles(count: Int)
    case tooLarge(totalBytes: Int64)
    case nameNotAllowedInWindows(name: String)
    case duplicateName(name: String)
    case copyFailed(detail: String)

    public var errorDescription: String? {
        switch self {
        case .sharedFolderUnavailable:
            "Copying files into Windows needs the Veil shared folder mounted on this Mac."
        case .notARegularFile(let name):
            "\(name) is a folder, alias, or link. Veil copies individual files only."
        case .tooManyFiles(let count):
            "\(count) files are selected. Veil copies up to \(ClipboardFilePaste.maximumFileCount) at a time."
        case .tooLarge(let totalBytes):
            "The files total \(ByteCountFormatter.string(fromByteCount: totalBytes, countStyle: .file)), above the \(ByteCountFormatter.string(fromByteCount: ClipboardFilePaste.maximumTotalBytes, countStyle: .file)) Veil copies on paste. Use the shared folder for large files."
        case .nameNotAllowedInWindows(let name):
            "Windows does not allow the file name \(name)."
        case .duplicateName(let name):
            "Two selected files are both named \(name)."
        case .copyFailed(let detail):
            "The files could not be copied into the shared folder. \(detail)"
        }
    }
}

/// What one checked file selection will become inside the shared folder.
public struct ClipboardFilePastePlan: Equatable, Sendable {
    public var sourceURLs: [URL]
    public var batchName: String
    /// Relative to the share root, with Windows separators, in the same order as `sourceURLs`.
    public var relativePaths: [String]
}

/// What the planner needs to know about one selected item. Read with `lstat` semantics, so a symbolic link
/// is reported as a link rather than as whatever it points at.
public struct ClipboardFilePasteEntry: Equatable, Sendable {
    public var isRegularFile: Bool
    public var byteCount: Int64

    public init(isRegularFile: Bool, byteCount: Int64) {
        self.isRegularFile = isRegularFile
        self.byteCount = byteCount
    }
}

/// Host-to-guest file paste through the guest-served shared folder. See `docs/protocol.md` "Clipboard Files".
///
/// Only the files the user copied in Finder are copied, at the moment they paste into a Windows window.
/// The host never sends a host path and never makes a Mac folder visible to Windows.
public enum ClipboardFilePaste {
    public static let directoryName = "Veil Clipboard"
    public static let maximumFileCount = 64
    public static let maximumTotalBytes: Int64 = 512 * 1_024 * 1_024
    public static let maximumRelativePathLength = 240
    /// Explorer copies pasted files out immediately, but the user can paste the same batch again later, so a
    /// few are kept rather than deleting each one as soon as the next paste happens.
    public static let retainedBatchCount = 3

    public static func plan(
        fileURLs: [URL],
        now: Date = Date(),
        batchSuffix: String = randomBatchSuffix(),
        entry: (URL) throws -> ClipboardFilePasteEntry = readEntry
    ) throws(ClipboardFilePasteRefusal) -> ClipboardFilePastePlan {
        guard fileURLs.count <= maximumFileCount else {
            throw .tooManyFiles(count: fileURLs.count)
        }

        let batchName = batchName(at: now, suffix: batchSuffix)
        var totalBytes: Int64 = 0
        var seenNames: Set<String> = []
        var relativePaths: [String] = []
        for url in fileURLs {
            let name = url.lastPathComponent
            let info: ClipboardFilePasteEntry
            do {
                info = try entry(url)
            } catch {
                throw .copyFailed(detail: error.localizedDescription)
            }
            guard info.isRegularFile else {
                throw .notARegularFile(name: name)
            }
            guard isAllowedWindowsFileName(name) else {
                throw .nameNotAllowedInWindows(name: name)
            }
            // NTFS is case-insensitive, so `a.txt` and `A.TXT` would overwrite each other in one batch.
            guard seenNames.insert(name.lowercased()).inserted else {
                throw .duplicateName(name: name)
            }
            totalBytes += info.byteCount
            guard totalBytes <= maximumTotalBytes else {
                throw .tooLarge(totalBytes: totalBytes)
            }

            let relativePath = "\(directoryName)\\\(batchName)\\\(name)"
            guard relativePath.count <= maximumRelativePathLength else {
                throw .nameNotAllowedInWindows(name: name)
            }
            relativePaths.append(relativePath)
        }

        return ClipboardFilePastePlan(sourceURLs: fileURLs, batchName: batchName, relativePaths: relativePaths)
    }

    /// Copies the planned files into `<shareRoot>/Veil Clipboard/<batch>/` and prunes older batches.
    public static func copy(
        _ plan: ClipboardFilePastePlan,
        intoShareAt shareRoot: URL,
        fileManager: FileManager = .default
    ) throws(ClipboardFilePasteRefusal) {
        let clipboardDirectory = shareRoot.appending(path: directoryName, directoryHint: .isDirectory)
        let batchDirectory = clipboardDirectory.appending(path: plan.batchName, directoryHint: .isDirectory)
        do {
            try fileManager.createDirectory(at: batchDirectory, withIntermediateDirectories: true)
            for source in plan.sourceURLs {
                try fileManager.copyItem(
                    at: source,
                    to: batchDirectory.appending(path: source.lastPathComponent, directoryHint: .notDirectory)
                )
            }
        } catch {
            // A half-copied batch must not be offered to Windows, and should not linger in the share either.
            try? fileManager.removeItem(at: batchDirectory)
            throw .copyFailed(detail: error.localizedDescription)
        }

        pruneBatches(in: clipboardDirectory, fileManager: fileManager)
    }

    /// Deletes all but the newest ``retainedBatchCount`` batches. Only folders whose names Veil generates are
    /// touched, so anything else the user keeps in `Veil Clipboard` survives.
    static func pruneBatches(in clipboardDirectory: URL, fileManager: FileManager) {
        guard let names = try? fileManager.contentsOfDirectory(atPath: clipboardDirectory.path) else {
            return
        }

        let batches = names.filter(isBatchName).sorted()
        for name in batches.dropLast(retainedBatchCount) {
            try? fileManager.removeItem(at: clipboardDirectory.appending(path: name, directoryHint: .isDirectory))
        }
    }

    public static func batchName(at date: Date, suffix: String) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(identifier: "UTC")
        formatter.dateFormat = "yyyyMMdd-HHmmss"
        return "\(formatter.string(from: date))-\(suffix)"
    }

    public static func randomBatchSuffix() -> String {
        String(format: "%06X", UInt32.random(in: 0...0xFF_FFFF))
    }

    static func isBatchName(_ name: String) -> Bool {
        name.wholeMatch(of: /[0-9]{8}-[0-9]{6}-[0-9A-F]{6}/) != nil
    }

    /// Windows rejects these outright, so a file named one of them would fail inside the guest after the copy.
    static func isAllowedWindowsFileName(_ name: String) -> Bool {
        let forbidden = CharacterSet(charactersIn: "<>:\"/\\|?*").union(.controlCharacters)
        guard !name.isEmpty,
              name != ".", name != "..",
              name.rangeOfCharacter(from: forbidden) == nil,
              !name.hasSuffix("."), !name.hasSuffix(" ") else {
            return false
        }

        let stem = name.split(separator: ".", maxSplits: 1).first.map(String.init)?.uppercased() ?? ""
        let reserved = Set(["CON", "PRN", "AUX", "NUL"])
            .union((1...9).map { "COM\($0)" })
            .union((1...9).map { "LPT\($0)" })
        return !reserved.contains(stem)
    }

    public static func readEntry(_ url: URL) throws -> ClipboardFilePasteEntry {
        let values = try url.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey, .fileSizeKey])
        return ClipboardFilePasteEntry(
            isRegularFile: values.isRegularFile == true && values.isSymbolicLink != true,
            byteCount: Int64(values.fileSize ?? 0)
        )
    }
}

/// The user's clipboard sharing switches. See `docs/protocol.md` "Host controls".
public enum ClipboardSharingPreferences {
    public static let sharingEnabledKey = "VeilClipboardSharingEnabled"
    public static let filePasteEnabledKey = "VeilClipboardFilePasteEnabled"

    /// On unless the user turned it off, matching the text sharing Veil already shipped.
    public static func isSharingEnabled(_ defaults: UserDefaults = .standard) -> Bool {
        defaults.object(forKey: sharingEnabledKey) as? Bool ?? true
    }

    /// File paste also requires sharing itself: turning sharing off must stop everything.
    public static func isFilePasteEnabled(_ defaults: UserDefaults = .standard) -> Bool {
        isSharingEnabled(defaults) && (defaults.object(forKey: filePasteEnabledKey) as? Bool ?? true)
    }
}
