import Foundation

/// One correction to the guest's text: delete `replaceLength` characters with Backspace, then type `text`.
public struct GuestTextReplacement: Equatable, Sendable {
    public var replaceLength: Int
    public var text: String

    public init(replaceLength: Int, text: String) {
        self.replaceLength = replaceLength
        self.text = text
    }
}

/// What of an open macOS IME composition has been typed into the guest.
///
/// Sending only committed text left the syllable being composed off the guest until the next key, so the
/// last Hangul syllable showed only after Space. The composition is typed into the guest as it changes,
/// and each change sends only the difference: Backspace over the changed characters, then the new ones.
/// See docs/protocol.md § Input Text.
public struct GuestTextComposition: Equatable, Sendable {
    /// The composition text the guest currently shows.
    public private(set) var shown = ""

    public init() {}

    /// The composition changed to `text`.
    public mutating func update(to text: String) -> GuestTextReplacement? {
        defer { shown = text }
        return Self.replacement(from: shown, to: text)
    }

    /// The IME committed `text`, which replaces the composition. Afterwards nothing is open.
    public mutating func commit(_ text: String) -> GuestTextReplacement? {
        defer { shown = "" }
        return Self.replacement(from: shown, to: text)
    }

    /// The composition ended without a commit, for example on a click; what the guest shows stays as typed.
    public mutating func abandon() {
        shown = ""
    }

    /// Characters, not code units, so one Backspace per step deletes exactly one.
    static func replacement(from old: String, to new: String) -> GuestTextReplacement? {
        let oldCharacters = Array(old)
        let newCharacters = Array(new)
        var common = 0
        while common < oldCharacters.count,
              common < newCharacters.count,
              oldCharacters[common] == newCharacters[common] {
            common += 1
        }
        let replacement = GuestTextReplacement(
            replaceLength: oldCharacters.count - common,
            text: String(newCharacters[common...])
        )
        return replacement.replaceLength == 0 && replacement.text.isEmpty ? nil : replacement
    }
}
