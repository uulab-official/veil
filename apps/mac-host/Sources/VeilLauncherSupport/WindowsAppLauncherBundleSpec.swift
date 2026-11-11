import Foundation

/// A document type a launcher declares, so Finder offers it under Open With.
public struct WindowsAppLauncherDocumentType: Equatable, Sendable {
    public var name: String
    public var contentTypes: [String]

    public init(name: String, contentTypes: [String]) {
        self.name = name
        self.contentTypes = contentTypes
    }
}

/// Everything about a Windows app launcher bundle that can be decided without touching the disk.
///
/// A launcher is a tiny `.app` in `~/Applications/Veil Apps` that Veil generates on the user's Mac the first
/// time a Windows app opens. It carries the Windows app's own icon (taken from the guest at run time, never
/// shipped in the repository) and, for apps Veil knows, the Mac file types that app opens.
public struct WindowsAppLauncherBundleSpec: Equatable, Sendable {
    /// Bump when the bundle layout or Info.plist changes, so existing launchers are rebuilt.
    public static let formatVersion = 1
    public static let folderName = "Veil Apps"
    public static let executableName = "veil-app-launcher"
    public static let iconFileName = "AppIcon"
    public static let bundleIdentifierPrefix = "org.uulab.veil.winapp."
    /// Info.plist keys the launcher reads, and Veil uses to recognise bundles it owns.
    public static let appIdKey = "VeilWindowsAppID"
    public static let appNameKey = "VeilWindowsAppName"
    public static let fingerprintKey = "VeilLauncherFingerprint"
    public static let minimumSystemVersion = "15.0"

    public var appId: String
    public var appName: String

    public init(appId: String, appName: String) {
        self.appId = appId
        self.appName = appName
    }

    /// `~/Applications/Veil Apps`. A user-writable Applications folder is indexed by Spotlight and listed in
    /// Launchpad, and a launcher there can be kept in the Dock like any app.
    public static func defaultFolder(home: URL = FileManager.default.homeDirectoryForCurrentUser) -> URL {
        home.appendingPathComponent("Applications", isDirectory: true)
            .appendingPathComponent(folderName, isDirectory: true)
    }

    /// Bundle identifiers allow only letters, digits, hyphens and periods.
    public var bundleIdentifier: String {
        let sanitized = String(appId.unicodeScalars.map { scalar -> Character in
            scalar.isASCII && (CharacterSet.alphanumerics.contains(scalar) || scalar == "." || scalar == "-")
                ? Character(scalar)
                : "-"
        })
        return Self.bundleIdentifierPrefix + sanitized
    }

    /// The name Finder, Launchpad and Spotlight show, as a usable file name.
    public var displayName: String {
        let cleaned = appName
            .replacingOccurrences(of: "/", with: "-")
            .replacingOccurrences(of: ":", with: "-")
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .trimmingCharacters(in: CharacterSet(charactersIn: "."))
        let limited = String(cleaned.prefix(100))
        return limited.isEmpty ? appId : limited
    }

    public var bundleFileName: String {
        "\(displayName).app"
    }

    public var documentTypes: [WindowsAppLauncherDocumentType] {
        Self.documentTypes(forAppId: appId)
    }

    /// File types for the inbox apps the guest reports. Other apps get a launcher without Open With entries,
    /// rather than a guess that would put them in the menu for files they cannot open.
    public static func documentTypes(forAppId appId: String) -> [WindowsAppLauncherDocumentType] {
        switch appId {
        case "winapp_notepad":
            return [
                WindowsAppLauncherDocumentType(
                    name: "Text Document",
                    // public.plain-text covers .txt, .log, source code and the other text types that conform to it.
                    contentTypes: ["public.plain-text", "public.comma-separated-values-text", "public.json", "public.xml"]
                )
            ]
        case "winapp_paint":
            return [
                WindowsAppLauncherDocumentType(
                    name: "Image",
                    contentTypes: ["public.png", "public.jpeg", "com.microsoft.bmp", "com.compuserve.gif", "public.tiff"]
                )
            ]
        default:
            return []
        }
    }

    /// The launcher's Info.plist. `fingerprint` records what the bundle was built from, so Veil can tell an
    /// up-to-date launcher from one that needs rebuilding without comparing files.
    public func infoPlist(fingerprint: String, veilVersion: String) -> [String: Any] {
        var plist: [String: Any] = [
            "CFBundleExecutable": Self.executableName,
            "CFBundleIdentifier": bundleIdentifier,
            "CFBundleName": displayName,
            "CFBundleDisplayName": displayName,
            "CFBundlePackageType": "APPL",
            "CFBundleIconFile": Self.iconFileName,
            "CFBundleShortVersionString": veilVersion,
            "CFBundleVersion": "\(Self.formatVersion)",
            "CFBundleDevelopmentRegion": "en",
            "CFBundleInfoDictionaryVersion": "6.0",
            "LSMinimumSystemVersion": Self.minimumSystemVersion,
            // The launcher hands its work to Veil and quits, so it never needs a Dock tile or menu bar of its own.
            "LSUIElement": true,
            "NSHighResolutionCapable": true,
            "NSPrincipalClass": "NSApplication",
            Self.appIdKey: appId,
            Self.appNameKey: appName,
            Self.fingerprintKey: fingerprint
        ]
        let types = documentTypes
        if !types.isEmpty {
            plist["CFBundleDocumentTypes"] = types.map { type -> [String: Any] in
                [
                    "CFBundleTypeName": type.name,
                    "CFBundleTypeRole": "Editor",
                    "LSItemContentTypes": type.contentTypes,
                    // Offered under Open With, never made the default app for a type behind the user's back.
                    "LSHandlerRank": "Alternate"
                ]
            }
        }
        return plist
    }
}
