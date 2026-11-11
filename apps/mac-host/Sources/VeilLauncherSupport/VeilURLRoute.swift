import Foundation

/// The `veil://` URLs Veil answers. Documented in `docs/protocol.md` under "Mac Integration URLs".
///
/// The scheme is reachable from anything on the Mac that can open a URL, a web page included, so a URL may
/// only *ask* Veil to do something a user could do from its own menus. It never names a host file: opening a
/// file goes through ``launcherRequest(id:)``, whose file list lives in a request file that only a local
/// process with access to the user's Application Support folder can write.
public enum VeilURLRoute: Equatable, Sendable {
    /// `veil://open-app?id=<appId>` opens a Windows app as a Mac window, starting Windows first if needed.
    case openApp(appId: String)
    /// `veil://launcher-request?id=<uuid>` hands Veil a request a Windows app launcher wrote, usually because
    /// the user opened Mac files with that launcher.
    case launcherRequest(id: UUID)

    public static let scheme = "veil"
    static let openAppHost = "open-app"
    static let launcherRequestHost = "launcher-request"

    public init?(url: URL) {
        guard url.scheme?.lowercased() == Self.scheme,
              let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
              let host = components.host?.lowercased() else {
            return nil
        }
        let id = components.queryItems?.first { $0.name == "id" }?.value

        switch host {
        case Self.openAppHost:
            guard let id, Self.isValidAppId(id) else {
                return nil
            }
            self = .openApp(appId: id)
        case Self.launcherRequestHost:
            guard let id, let uuid = UUID(uuidString: id) else {
                return nil
            }
            self = .launcherRequest(id: uuid)
        default:
            return nil
        }
    }

    public var url: URL {
        var components = URLComponents()
        components.scheme = Self.scheme
        switch self {
        case .openApp(let appId):
            components.host = Self.openAppHost
            components.queryItems = [URLQueryItem(name: "id", value: appId)]
        case .launcherRequest(let id):
            components.host = Self.launcherRequestHost
            components.queryItems = [URLQueryItem(name: "id", value: id.uuidString)]
        }
        // Every component above is built from validated values, so this cannot fail.
        return components.url!
    }

    /// App ids come from the guest's `app.list.response` (`winapp_notepad`). Anything else is refused before
    /// it reaches the guest, so a crafted URL cannot smuggle text into a protocol message.
    public static func isValidAppId(_ appId: String) -> Bool {
        guard (1...128).contains(appId.count) else {
            return false
        }
        return appId.unicodeScalars.allSatisfy { scalar in
            scalar.isASCII && (CharacterSet.alphanumerics.contains(scalar) || scalar == "_" || scalar == "-" || scalar == ".")
        }
    }
}
