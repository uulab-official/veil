import Foundation
import Testing

@testable import VeilHostCore

/// Drag-and-drop is the one input path where the host refuses work before the guest ever sees it, to avoid
/// reading and base64-encoding a file the guest would reject anyway. That saved cost came with a hole: the
/// refusals were silent, and macOS had already played its accept animation by the time the checks ran. So an
/// oversized file looked exactly like a file that opened and did nothing.
///
/// These tests cover the rules. The point of every case is that a refusal exists and can be worded, not just
/// that a file was skipped.
@Suite("Windows app file drop policy")
struct FileDropPolicyTests {
    @Test("accepts an ordinary file")
    func acceptsOrdinaryFile() {
        #expect(WindowsAppFileDropPolicy.refusal(forFileNamed: "notes.txt", byteCount: 4_096) == nil)
    }

    @Test("accepts a file exactly at the size limit")
    func acceptsFileAtLimit() {
        // The guest's own check is `> MaxDroppedFileBytes`, so the boundary has to be inclusive on both
        // sides or the host would refuse a file the guest would have taken.
        let refusal = WindowsAppFileDropPolicy.refusal(
            forFileNamed: "exactly-fifty.bin",
            byteCount: WindowsAppFileDropPolicy.maximumFileBytes
        )

        #expect(refusal == nil)
    }

    @Test("refuses one byte over the size limit and says how big it was")
    func refusesFileOverLimit() throws {
        let byteCount = WindowsAppFileDropPolicy.maximumFileBytes + 1
        let refusal = WindowsAppFileDropPolicy.refusal(forFileNamed: "huge.iso", byteCount: byteCount)

        #expect(refusal == .fileTooLarge(fileName: "huge.iso", byteCount: byteCount))
        let message = try #require(refusal).message
        #expect(message.contains("huge.iso"))
        // Both numbers, so the user can see how far over the limit they are rather than being told only
        // that a limit exists.
        #expect(message.contains("50.0 MB"))
        // And a way forward, since the file itself is not going to get smaller.
        #expect(message.contains("shared folder"))
    }

    @Test("refuses an empty file")
    func refusesEmptyFile() {
        #expect(WindowsAppFileDropPolicy.refusal(forFileNamed: "empty.txt", byteCount: 0) == .emptyFile(fileName: "empty.txt"))
    }

    @Test("refuses a negative size rather than treating it as small")
    func refusesNegativeSize() {
        #expect(WindowsAppFileDropPolicy.refusal(forFileNamed: "odd.bin", byteCount: -1) == .emptyFile(fileName: "odd.bin"))
    }

    @Test("refuses a file whose size could not be read instead of guessing")
    func refusesUnknownSize() {
        // Refused rather than attempted: the alternative to a size check is discovering the size by
        // exhausting memory on an unbounded read.
        let refusal = WindowsAppFileDropPolicy.refusal(forFileNamed: "mystery.dat", byteCount: nil)

        #expect(refusal == .sizeUnavailable(fileName: "mystery.dat"))
    }

    @Test("accepts a batch at the per-drop limit")
    func acceptsBatchAtLimit() {
        #expect(WindowsAppFileDropPolicy.refusal(forFileCount: WindowsAppFileDropPolicy.maximumFilesPerDrop) == nil)
    }

    @Test("accepts a single file")
    func acceptsSingleFile() {
        #expect(WindowsAppFileDropPolicy.refusal(forFileCount: 1) == nil)
    }

    @Test("refuses a batch over the per-drop limit and names the count")
    func refusesOversizedBatch() throws {
        let count = WindowsAppFileDropPolicy.maximumFilesPerDrop + 1
        let refusal = WindowsAppFileDropPolicy.refusal(forFileCount: count)

        #expect(refusal == .tooManyFiles(count: count))
        let message = try #require(refusal).message
        #expect(message.contains("\(count)"))
        #expect(message.contains("\(WindowsAppFileDropPolicy.maximumFilesPerDrop)"))
    }

    @Test("bounds a drop by the same number as the per-app window bound")
    @MainActor
    func dropBoundMatchesWindowBound() {
        // Each dropped file opens its own Windows app window. Two different numbers for "how many windows
        // of one app will Veil put on screen" would drift, and the drop limit is written out separately
        // because the window bound lives on a MainActor type this policy cannot reach.
        #expect(WindowsAppFileDropPolicy.maximumFilesPerDrop == HostDashboardModel.maximumAdoptedWindowsPerApp)
    }

    @Test("matches the guest's own size cap")
    func sizeCapMatchesGuest() {
        // AgentSession.cs: `private const int MaxDroppedFileBytes = 50 * 1024 * 1024;`. Duplicated on
        // purpose — checking on the host avoids a pointless transfer, checking on the guest stops a host
        // that skipped the check — so the two values have to be pinned to each other somewhere.
        #expect(WindowsAppFileDropPolicy.maximumFileBytes == 50 * 1024 * 1024)
    }

    @Test("gives every refusal a stable id and a non-empty message")
    func everyRefusalIsReportable() {
        // Every case, including the ones added later. A list that drifts behind the enum stops guaranteeing the
        // thing it claims to.
        let refusals: [WindowsAppFileDropRefusal] = [
            .tooManyFiles(count: 20),
            .emptyFile(fileName: "a.txt"),
            .fileTooLarge(fileName: "b.bin", byteCount: 99_999_999),
            .sizeUnavailable(fileName: "c.dat"),
            .unreadableFile(fileName: "d.doc"),
            .unreadableItem,
            .unusableFileName(fileName: "e.txt"),
            .guestRejected(fileName: "f.txt", detail: "Windows said no.")
        ]

        for refusal in refusals {
            // A refusal with no message is a silent failure wearing a type.
            #expect(refusal.message.isEmpty == false)
            #expect(refusal.reasonId.isEmpty == false)
        }

        // Ids must be distinct, or diagnostics cannot tell two different refusals apart.
        #expect(Set(refusals.map(\.reasonId)).count == refusals.count)
    }

    @Test("reports a file name for file refusals and none for whole-drop refusals")
    func fileNameIsPresentOnlyWhenItMeansSomething() {
        #expect(WindowsAppFileDropRefusal.emptyFile(fileName: "a.txt").fileName == "a.txt")
        #expect(WindowsAppFileDropRefusal.unreadableFile(fileName: "d.doc").fileName == "d.doc")
        // Neither of these is about one file, so inventing a name for them would be a small lie.
        #expect(WindowsAppFileDropRefusal.tooManyFiles(count: 20).fileName == nil)
        #expect(WindowsAppFileDropRefusal.unreadableItem.fileName == nil)
    }

    @Test("describes sizes without a locale-dependent separator")
    func describesSizesIndependentOfLocale() {
        // ByteCountFormatter would use a comma decimal separator in much of the world and make these
        // messages impossible to assert on.
        #expect(WindowsAppFileDropPolicy.describeBytes(50 * 1024 * 1024) == "50.0 MB")
        #expect(WindowsAppFileDropPolicy.describeBytes(1024 * 1024) == "1.0 MB")
        #expect(WindowsAppFileDropPolicy.describeBytes(1536) == "1.5 KB")
    }
}

/// macOS and Windows disagree about what a file may be called, and the disagreement is not symmetric:
/// `: * ? " < > | \` are all legal in an APFS name and all forbidden by Windows. Finder even *stores* a name
/// it displays with `/` using `:`, so a file the user sees as "2026/08/12 report.txt" reaches the host as
/// "2026:08:12 report.txt". The guest refuses those names, correctly — which meant a perfectly legal file was
/// rejected for a reason invisible on the user's own machine.
///
/// Rewriting on the host cannot weaken anything, because the guest validates independently and stays the
/// security boundary. These tests pin the rewrite to the guest's rules in
/// `AgentSession.TryResolveSafeFileName`.
@Suite("Windows-safe file names")
struct WindowsSafeFileNameTests {
    @Test("leaves an ordinary name alone")
    func leavesOrdinaryNameAlone() {
        #expect(WindowsAppFileDropPolicy.windowsSafeFileName(for: "report.txt") == "report.txt")
        #expect(WindowsAppFileDropPolicy.windowsSafeFileName(for: "my notes 2026.md") == "my notes 2026.md")
    }

    @Test("rewrites the colon Finder uses for a displayed slash")
    func rewritesColon() {
        // The most likely real case: any date in a file name that the user typed with slashes.
        #expect(WindowsAppFileDropPolicy.windowsSafeFileName(for: "2026:08:12 report.txt") == "2026_08_12 report.txt")
    }

    @Test("rewrites every character Windows forbids")
    func rewritesForbiddenCharacters() {
        #expect(WindowsAppFileDropPolicy.windowsSafeFileName(for: #"a<b>c:d"e\f|g?h*i.txt"#) == "a_b_c_d_e_f_g_h_i.txt")
    }

    @Test("rewrites control characters")
    func rewritesControlCharacters() {
        #expect(WindowsAppFileDropPolicy.windowsSafeFileName(for: "tab\there.txt") == "tab_here.txt")
    }

    @Test("leaves multi-scalar graphemes intact")
    func leavesEmojiIntact() {
        // Checked by scalar value with an explicit single-scalar guard, so a flag or skin-tone sequence is
        // never mistaken for a control character.
        #expect(WindowsAppFileDropPolicy.windowsSafeFileName(for: "party 🎉.txt") == "party 🎉.txt")
        #expect(WindowsAppFileDropPolicy.windowsSafeFileName(for: "flag 🇰🇷.txt") == "flag 🇰🇷.txt")
    }

    @Test("suffixes a reserved device name and keeps its extension")
    func suffixesReservedName() {
        // Windows resolves CON.txt to the CON device regardless of extension. Suffixing the base rather
        // than the whole name keeps the extension, so Windows still opens it with the right app.
        #expect(WindowsAppFileDropPolicy.windowsSafeFileName(for: "CON.txt") == "CON_.txt")
        #expect(WindowsAppFileDropPolicy.windowsSafeFileName(for: "NUL") == "NUL_")
        #expect(WindowsAppFileDropPolicy.windowsSafeFileName(for: "lpt3.log") == "lpt3_.log")
    }

    @Test("leaves a name that merely starts like a reserved one")
    func leavesNearReservedName() {
        // Only the exact base name is reserved. Rewriting these would be a bug the user would notice.
        #expect(WindowsAppFileDropPolicy.windowsSafeFileName(for: "console.txt") == "console.txt")
        #expect(WindowsAppFileDropPolicy.windowsSafeFileName(for: "COM10.txt") == "COM10.txt")
        #expect(WindowsAppFileDropPolicy.windowsSafeFileName(for: "nullify.dat") == "nullify.dat")
    }

    @Test("trims surrounding whitespace like the guest does")
    func trimsWhitespace() {
        #expect(WindowsAppFileDropPolicy.windowsSafeFileName(for: "  report.txt  ") == "report.txt")
    }

    @Test("refuses names that carry no content at all")
    func refusesEmptyNames() {
        #expect(WindowsAppFileDropPolicy.windowsSafeFileName(for: "") == nil)
        #expect(WindowsAppFileDropPolicy.windowsSafeFileName(for: "   ") == nil)
        #expect(WindowsAppFileDropPolicy.windowsSafeFileName(for: ".") == nil)
        #expect(WindowsAppFileDropPolicy.windowsSafeFileName(for: "..") == nil)
    }

    @Test("keeps a leading dot as part of the name")
    func keepsLeadingDot() {
        // Splitting ".gitignore" into an empty base plus a "gitignore" extension would make the reserved
        // name check operate on nothing.
        #expect(WindowsAppFileDropPolicy.splitExtension(".gitignore").base == ".gitignore")
        #expect(WindowsAppFileDropPolicy.splitExtension(".gitignore").fileExtension == "")
        #expect(WindowsAppFileDropPolicy.windowsSafeFileName(for: ".gitignore") == ".gitignore")
    }

    @Test("splits on the last dot only")
    func splitsOnLastDot() {
        #expect(WindowsAppFileDropPolicy.splitExtension("archive.tar.gz").base == "archive.tar")
        #expect(WindowsAppFileDropPolicy.splitExtension("archive.tar.gz").fileExtension == "gz")
        // Matches Path.GetFileNameWithoutExtension, which strips only the last extension — so "CON.tar.gz"
        // has base "CON.tar", which is not reserved, and the guest accepts it unchanged.
        #expect(WindowsAppFileDropPolicy.windowsSafeFileName(for: "CON.tar.gz") == "CON.tar.gz")
    }

    @Test("produces a name the guest's own rules would accept")
    func producesGuestAcceptableName() throws {
        let hostile = #"CON:evil\..*?.txt"#
        let safe = try #require(WindowsAppFileDropPolicy.windowsSafeFileName(for: hostile))

        // The guest's checks, restated: no separators, not a traversal, none of the forbidden characters,
        // base name not reserved.
        #expect(safe.contains("\\") == false)
        #expect(safe.contains("/") == false)
        #expect(safe.contains(":") == false)
        #expect(safe.contains("?") == false)
        #expect(safe.contains("*") == false)
        #expect(safe != "." && safe != "..")
    }

    @Test("words a guest rejection as a Windows problem, not a Veil one")
    func wordsGuestRejection() {
        let refusal = WindowsAppFileDropRefusal.guestRejected(
            fileName: "report.txt",
            detail: "The app is no longer installed."
        )

        // Veil did its part here; Windows refused. Saying "Veil could not read" would misplace the blame,
        // and dropping the guest's own detail would lose the only information that explains it.
        #expect(refusal.message.contains("Windows could not open"))
        #expect(refusal.message.contains("report.txt"))
        #expect(refusal.message.contains("The app is no longer installed."))
        #expect(refusal.fileName == "report.txt")
    }
}

/// macOS allows 255 bytes per path component. The guest writes into
/// `%TEMP%\VeilDroppedFiles\<32-char GUID>\<fileName>` against Windows' 259-usable-code-unit path limit, with
/// no `longPathAware` manifest entry, so a legal Mac name can exceed what the guest can write. Neither side
/// bounded it, and the failure surfaced as a raw .NET exception that said nothing about length.
@Suite("Dropped file name length")
struct DroppedFileNameLengthTests {
    @Test("leaves a name that already fits")
    func leavesShortNameAlone() {
        let name = String(repeating: "a", count: 100) + ".txt"

        #expect(WindowsAppFileDropPolicy.windowsSafeFileName(for: name) == name)
    }

    @Test("shortens an over-long name and keeps the extension")
    func shortensLongName() throws {
        let name = String(repeating: "a", count: 400) + ".txt"

        let safe = try #require(WindowsAppFileDropPolicy.windowsSafeFileName(for: name))

        #expect(safe.utf16.count <= WindowsAppFileDropPolicy.maximumFileNameUTF16Length)
        // The extension decides which app Windows opens the file with, so it is the part worth keeping.
        #expect(safe.hasSuffix(".txt"))
        #expect(safe.hasPrefix("aaaa"))
    }

    @Test("counts UTF-16 code units, not characters, because Windows does")
    func countsCodeUnits() throws {
        // Each of these is one Character and two UTF-16 code units, so 200 of them is 400 code units.
        let name = String(repeating: "🎉", count: 200) + ".png"

        let safe = try #require(WindowsAppFileDropPolicy.windowsSafeFileName(for: name))

        #expect(safe.utf16.count <= WindowsAppFileDropPolicy.maximumFileNameUTF16Length)
        #expect(safe.hasSuffix(".png"))
    }

    @Test("shortens on character boundaries so an emoji is never cut in half")
    func shortensOnCharacterBoundaries() throws {
        let name = String(repeating: "🎉", count: 200) + ".png"

        let safe = try #require(WindowsAppFileDropPolicy.windowsSafeFileName(for: name))
        let base = WindowsAppFileDropPolicy.splitExtension(safe).base

        // An implementation that sliced the UTF-16 array to fit the budget would leave a half surrogate,
        // which Swift would surface as a replacement character and Windows would receive as a different
        // name. Every retained character being a whole emoji is what rules that out.
        #expect(base.allSatisfy { $0 == "🎉" })
        #expect(base.utf16.count % 2 == 0)
        #expect(base.contains("\u{FFFD}") == false)
    }

    @Test("handles a Korean name without mangling it")
    func handlesKoreanName() throws {
        // Hangul syllables are one code unit each, so a name well inside the budget is untouched.
        let name = "회의록 2026년 정리.txt"

        #expect(WindowsAppFileDropPolicy.windowsSafeFileName(for: name) == name)

        let long = String(repeating: "회", count: 300) + ".txt"
        let safe = try #require(WindowsAppFileDropPolicy.windowsSafeFileName(for: long))
        #expect(safe.utf16.count <= WindowsAppFileDropPolicy.maximumFileNameUTF16Length)
        #expect(safe.hasSuffix(".txt"))
    }

    @Test("leaves room for a reserved-name suffix")
    func leavesRoomForReservedSuffix() throws {
        // Shortening reserves one code unit so appending `_` to a reserved base cannot push the name back
        // over the limit. Exercised through a name that is both over-long and reserved after shortening is
        // impractical to construct, so the invariant is checked directly: every shortened name is at least
        // one unit under the cap.
        let safe = try #require(WindowsAppFileDropPolicy.windowsSafeFileName(for: String(repeating: "b", count: 500)))

        #expect(safe.utf16.count < WindowsAppFileDropPolicy.maximumFileNameUTF16Length)
    }

    @Test("shortens rather than refusing, so the file still opens")
    func shortensRatherThanRefusing() {
        // Refusing would have been the conservative-looking choice and the wrong one: the name is legal on
        // the user's own operating system, and the guest copy lives in a temporary directory that is deleted
        // minutes later.
        #expect(WindowsAppFileDropPolicy.windowsSafeFileName(for: String(repeating: "z", count: 250)) != nil)
    }
}
