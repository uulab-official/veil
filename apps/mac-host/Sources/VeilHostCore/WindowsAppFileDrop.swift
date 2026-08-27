import Foundation

/// Why a dragged file was not sent to the Windows guest.
///
/// Drag-and-drop is the one input path where the host refuses work *before* the guest ever sees it, to
/// avoid reading, base64-encoding, and transferring a file the guest would reject anyway. That saved cost
/// came with a hole: the refusals were silent. macOS had already played the accept animation by the time
/// the size check ran, so an oversized file looked exactly like a successful drop that did nothing.
///
/// Every case carries the values its own message needs, so there is one place a refusal can be worded and
/// no way to construct a refusal without the facts that explain it.
public enum WindowsAppFileDropRefusal: Equatable, Sendable {
    /// The whole drop, refused before any file was read. Known synchronously from the provider count.
    case tooManyFiles(count: Int)
    case emptyFile(fileName: String)
    case fileTooLarge(fileName: String, byteCount: Int)
    /// The size could not be read, so the size limit cannot be enforced. Refused rather than attempted,
    /// because the alternative is discovering it by exhausting memory on an unbounded read.
    case sizeUnavailable(fileName: String)
    /// The file exists and is a sane size, but reading it failed. Usually a sandbox or permission denial
    /// on a location macOS did not grant access to.
    case unreadableFile(fileName: String)
    /// The drop never yielded a usable file at all, so there is not even a name to report. Distinct from
    /// ``unreadableFile`` because there is nothing for the user to go check.
    case unreadableItem
    /// Nothing Windows would accept survived rewriting the name. Only reachable for names that are entirely
    /// unusable, such as `.` or `..` — ordinary Windows-illegal characters are rewritten instead.
    case unusableFileName(fileName: String)
    /// Windows itself refused or failed the drop. Carries the guest's own wording, because the guest knows
    /// things the host cannot check: whether the app is still installed, whether the write succeeded, and
    /// whether the launch worked.
    case guestRejected(fileName: String, detail: String)

    /// Product-facing text. Names what happened and what would work instead, in the same Windows-app
    /// language the rest of the launcher uses rather than transfer or agent wording.
    public var message: String {
        switch self {
        case .tooManyFiles(let count):
            return "Too many files to open at once (\(count)). Each file opens its own Windows app window, so Veil opens up to \(WindowsAppFileDropPolicy.maximumFilesPerDrop) at a time."
        case .emptyFile(let fileName):
            return "\"\(fileName)\" is empty, so there is nothing for the Windows app to open."
        case .fileTooLarge(let fileName, let byteCount):
            return "\"\(fileName)\" is \(WindowsAppFileDropPolicy.describeBytes(byteCount)), over the \(WindowsAppFileDropPolicy.describeBytes(WindowsAppFileDropPolicy.maximumFileBytes)) drag-and-drop limit. Copy it into the shared folder and open it from inside Windows instead."
        case .sizeUnavailable(let fileName):
            return "Veil could not read the size of \"\(fileName)\", so it cannot check it against the \(WindowsAppFileDropPolicy.describeBytes(WindowsAppFileDropPolicy.maximumFileBytes)) drag-and-drop limit."
        case .unreadableFile(let fileName):
            return "Veil could not read \"\(fileName)\". Check that the file still exists and that Veil has permission to open its folder."
        case .unreadableItem:
            return "Veil could not read the dropped item as a file. Try dragging it from Finder again."
        case .unusableFileName(let fileName):
            return "\"\(fileName)\" is not a name Windows can use. Rename it and drag it again."
        case .guestRejected(let fileName, let detail):
            return "Windows could not open \"\(fileName)\". \(detail)"
        }
    }

    /// Stable identifier for the refusal kind, for logs and diagnostics that should not match on prose.
    public var reasonId: String {
        switch self {
        case .tooManyFiles: return "tooManyFiles"
        case .emptyFile: return "emptyFile"
        case .fileTooLarge: return "fileTooLarge"
        case .sizeUnavailable: return "sizeUnavailable"
        case .unreadableFile: return "unreadableFile"
        case .unreadableItem: return "unreadableItem"
        case .unusableFileName: return "unusableFileName"
        case .guestRejected: return "guestRejected"
        }
    }

    /// `nil` for a whole-drop refusal, which is not about any one file.
    public var fileName: String? {
        switch self {
        case .tooManyFiles, .unreadableItem:
            return nil
        case .emptyFile(let fileName),
             .fileTooLarge(let fileName, _),
             .sizeUnavailable(let fileName),
             .unreadableFile(let fileName),
             .unusableFileName(let fileName),
             .guestRejected(let fileName, _):
            return fileName
        }
    }
}

/// The host half of the drag-and-drop contract.
///
/// Pure, so the rules are testable without a VM, a window server, or a file on disk. The app shell reads
/// sizes and bytes; this decides what that means.
public enum WindowsAppFileDropPolicy {
    /// Matches `MaxDroppedFileBytes` in the guest's `AgentSession.cs`. Duplicated on purpose: checking here
    /// avoids a pointless transfer, and checking there stops a host that skipped the check.
    public static let maximumFileBytes = 50 * 1024 * 1024

    /// Each dropped file opens its own Windows app window, so an accidental drag of a whole folder's worth
    /// of files would carpet the screen.
    ///
    /// Deliberately the same number as `HostDashboardModel.maximumAdoptedWindowsPerApp`, so the product has
    /// one answer to "how many windows of one app will Veil put on screen" instead of two that drift apart.
    /// Written out rather than referencing that constant, because it lives on a `@MainActor` type and this
    /// policy is used from the non-isolated file-loading callbacks. A test pins the two together.
    public static let maximumFilesPerDrop = 8

    /// Refuses an entire drop before any file is read. Known from the provider count alone, so this runs
    /// synchronously while the drop can still be rejected outright.
    public static func refusal(forFileCount fileCount: Int) -> WindowsAppFileDropRefusal? {
        guard fileCount > maximumFilesPerDrop else {
            return nil
        }
        return .tooManyFiles(count: fileCount)
    }

    /// Refuses one file on the facts the app shell could gather before reading it.
    ///
    /// - Parameter byteCount: `nil` when the size could not be read at all, which is refused rather than
    ///   treated as zero or as unlimited.
    public static func refusal(forFileNamed fileName: String, byteCount: Int?) -> WindowsAppFileDropRefusal? {
        guard let byteCount else {
            return .sizeUnavailable(fileName: fileName)
        }
        if byteCount <= 0 {
            return .emptyFile(fileName: fileName)
        }
        if byteCount > maximumFileBytes {
            return .fileTooLarge(fileName: fileName, byteCount: byteCount)
        }
        return nil
    }

    /// Characters Windows forbids in a file name. Mirrors `Path.GetInvalidFileNameChars()` on Windows,
    /// which the guest checks against in `AgentSession.TryResolveSafeFileName`.
    private static let charactersWindowsForbids: Set<Character> = ["<", ">", ":", "\"", "/", "\\", "|", "?", "*"]

    /// Names Windows resolves to device files no matter the extension: `CON.txt` is still the CON device.
    /// Mirrors `ReservedWindowsDeviceNames` in the guest.
    private static let namesWindowsReserves: Set<String> = {
        var reserved: Set<String> = ["CON", "PRN", "AUX", "NUL"]
        for index in 1...9 {
            reserved.insert("COM\(index)")
            reserved.insert("LPT\(index)")
        }
        return reserved
    }()

    /// Rewrites a macOS file name into one Windows will accept.
    ///
    /// macOS allows characters Windows forbids. `: * ? " < > | \` are all legal in an APFS name, and Finder
    /// stores a name it *displays* with `/` using `:` on disk — so a file the user sees as
    /// "2026/08/12 report.txt" arrives here as "2026:08:12 report.txt". The guest refuses those names,
    /// correctly, which meant a perfectly legal file was rejected for a reason invisible on the user's own
    /// machine.
    ///
    /// Rewriting here cannot weaken anything: the guest validates independently and remains the security
    /// boundary. This only decides whether a legal-on-macOS name gets a chance to open at all. The copy
    /// lives in a temporary guest directory that is deleted minutes later, so the rewritten name is not
    /// something the user has to live with.
    ///
    /// - Returns: A name Windows will accept, or `nil` when nothing usable survives — which only happens for
    ///   names that carry no content at all, like `.` or `..`.
    public static func windowsSafeFileName(for fileName: String) -> String? {
        let trimmed = fileName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, trimmed != ".", trimmed != ".." else {
            return nil
        }

        let substituted = String(trimmed.map { character in
            if charactersWindowsForbids.contains(character) {
                return Character("_")
            }
            // Control characters are also in Path.GetInvalidFileNameChars(). Checked by scalar value so a
            // multi-scalar grapheme such as an emoji is never mistaken for one.
            if character.unicodeScalars.count == 1,
               let scalar = character.unicodeScalars.first,
               scalar.value < 32 {
                return Character("_")
            }
            return character
        })

        guard let shortened = shortenedToWindowsPathBudget(substituted) else {
            return nil
        }

        let (baseName, fileExtension) = splitExtension(shortened)
        guard namesWindowsReserves.contains(baseName.uppercased()) else {
            return shortened
        }

        // Suffixing the base rather than the whole name keeps the extension intact, so Windows still picks
        // the right app: "CON.txt" becomes "CON_.txt", not "CON.txt_". The shortening step above leaves one
        // code unit spare precisely so this suffix cannot push the name back over budget.
        return fileExtension.isEmpty ? "\(baseName)_" : "\(baseName)_.\(fileExtension)"
    }

    /// The longest dropped file name the guest can write, in UTF-16 code units.
    ///
    /// Windows' classic path limit is 260 code units including the terminator, so 259 usable, and the guest
    /// builds `%TEMP%\VeilDroppedFiles\<32-char GUID>\<fileName>` in
    /// `AgentSession.WriteDroppedFile`. With `%TEMP%` as `C:\Users\<user>\AppData\Local\Temp\` the prefix is
    /// 79 code units plus the user name, and Windows allows user names up to 20 — so the worst realistic
    /// budget is 160. `app.manifest` declares no `longPathAware`, so the classic limit applies.
    ///
    /// A name this long is not something a person types; the point is that macOS allows 255 bytes per path
    /// component, so a legal Mac name can exceed what the guest can write.
    public static let maximumFileNameUTF16Length = 160

    /// Shortens a name that would overflow Windows' path limit, keeping the extension.
    ///
    /// Shortened rather than refused, for the same reason forbidden characters are rewritten: the user's file
    /// is fine, the name is fine on their own operating system, and the copy lands in a temporary guest
    /// directory that is deleted minutes later. Each drop gets its own GUID directory, so a shortened name
    /// cannot collide with anything.
    ///
    /// - Returns: `nil` only when nothing usable survives, which needs an extension longer than the whole
    ///   budget.
    private static func shortenedToWindowsPathBudget(_ fileName: String) -> String? {
        // One code unit spare so a reserved-name suffix cannot push the result back over the limit.
        let budget = maximumFileNameUTF16Length - 1
        guard fileName.utf16.count > budget else {
            return fileName
        }

        let (baseName, fileExtension) = splitExtension(fileName)
        // The extension decides which app Windows opens the file with, so it is the part worth keeping.
        let suffix = fileExtension.isEmpty ? "" : ".\(fileExtension)"
        let baseBudget = budget - suffix.utf16.count
        guard baseBudget > 0 else {
            return nil
        }

        // Accumulated a Character at a time rather than by slicing UTF-16, so a surrogate pair is never split
        // in half and an emoji cannot be turned into an invalid code unit.
        var shortenedBase = ""
        var usedCodeUnits = 0
        for character in baseName {
            let width = String(character).utf16.count
            if usedCodeUnits + width > baseBudget {
                break
            }
            shortenedBase.append(character)
            usedCodeUnits += width
        }

        guard !shortenedBase.isEmpty else {
            return nil
        }

        return shortenedBase + suffix
    }

    /// Splits on the last dot, treating a leading dot as part of the name so `.gitignore` keeps its name
    /// instead of becoming an empty base with a `gitignore` extension.
    /// Labelled `fileExtension` rather than `extension`, which is a Swift keyword and would need backticks
    /// at every use site.
    static func splitExtension(_ fileName: String) -> (base: String, fileExtension: String) {
        guard let dotIndex = fileName.lastIndex(of: "."), dotIndex != fileName.startIndex else {
            return (fileName, "")
        }
        return (
            String(fileName[fileName.startIndex..<dotIndex]),
            String(fileName[fileName.index(after: dotIndex)...])
        )
    }

    /// Locale-independent on purpose: `ByteCountFormatter` would put a comma decimal separator in some
    /// regions and make these messages untestable by exact match.
    static func describeBytes(_ byteCount: Int) -> String {
        let megabytes = Double(byteCount) / (1024 * 1024)
        if megabytes >= 1 {
            return String(format: "%.1f MB", megabytes)
        }
        let kilobytes = Double(byteCount) / 1024
        return String(format: "%.1f KB", kilobytes)
    }
}
