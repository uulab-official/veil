import Foundation

/// The local Windows account Veil's answer file creates, so Windows Setup never stops at "Who's
/// going to use this device?". The user can name it; otherwise it follows this Mac's account.
///
/// Windows local account names are at most 20 characters, cannot contain " / \ [ ] : ; | = , + * ?
/// < > @, and cannot end with a period. Veil also drops %, which cmd scripts would expand. Built-in
/// names would collide with existing accounts.
/// https://learn.microsoft.com/windows-hardware/customize/desktop/unattend/microsoft-windows-shell-setup-useraccounts-localaccounts-localaccount-name
public enum WindowsAccountName {
    public static let fallback = "Veil"
    public static let maximumLength = 20

    private static let disallowedCharacters = CharacterSet(charactersIn: "\"/\\[]:;|=,+*?<>@%")
        .union(.controlCharacters)
    private static let reservedNames: Set<String> = [
        "administrator", "guest", "defaultaccount", "wdagutilityaccount", "system", "none"
    ]

    /// The cleaned-up name, or nil when nothing usable is left.
    public static func sanitized(_ rawName: String) -> String? {
        let kept = String(String.UnicodeScalarView(rawName.unicodeScalars.filter { !disallowedCharacters.contains($0) }))
        var name = String(kept.trimmingCharacters(in: .whitespacesAndNewlines).prefix(maximumLength))
        while name.hasSuffix(".") || name.hasSuffix(" ") {
            name.removeLast()
        }
        guard !name.isEmpty, !reservedNames.contains(name.lowercased()) else {
            return nil
        }
        return name
    }

    /// The account the next install creates: the user's choice, then this Mac's short user name.
    public static func resolve(preferred: String?, macUserName: String = NSUserName()) -> String {
        if let preferred, let name = sanitized(preferred) {
            return name
        }
        return sanitized(macUserName) ?? fallback
    }
}
