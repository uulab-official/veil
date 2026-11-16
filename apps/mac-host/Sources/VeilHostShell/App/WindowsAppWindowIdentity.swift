import Foundation
import VeilHostCore

/// Stable app metadata used by mirrored windows and their macOS chrome.
///
/// The guest catalog is authoritative for the icon, but a missing or malformed
/// icon must never prevent a window from being presented. Keeping this resolver
/// pure lets the presenter use the same fallback behavior after reconnects and
/// for catalog entries that predate icon support.
struct WindowsAppWindowIdentity: Equatable, Sendable {
    let appId: String
    let appName: String
    let iconData: Data?

    static func resolve(appId: String, apps: [WindowsApp]) -> WindowsAppWindowIdentity {
        guard let app = apps.first(where: { $0.id == appId }) else {
            return WindowsAppWindowIdentity(
                appId: appId,
                appName: "Windows App",
                iconData: nil
            )
        }

        return WindowsAppWindowIdentity(
            appId: app.id,
            appName: app.name,
            iconData: app.iconPngBase64.flatMap { Data(base64Encoded: $0) }
        )
    }
}
