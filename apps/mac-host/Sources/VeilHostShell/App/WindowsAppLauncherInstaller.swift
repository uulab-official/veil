import AppKit
import CoreServices
import CryptoKit
import ImageIO
import UniformTypeIdentifiers
import VeilHostCore
import VeilLauncherSupport

/// What happened to one launcher.
enum WindowsAppLauncherInstallOutcome: Equatable, Sendable {
    case created(URL)
    case updated(URL)
    case unchanged(URL)
}

enum WindowsAppLauncherInstallError: Error, Equatable, LocalizedError {
    case launcherProgramMissing
    case signingFailed(String)

    var errorDescription: String? {
        switch self {
        case .launcherProgramMissing:
            return "This copy of Veil does not include the app launcher program."
        case .signingFailed(let detail):
            return "The launcher could not be signed: \(detail)"
        }
    }
}

/// Writes Windows app launchers into `~/Applications/Veil Apps`.
///
/// Each launcher is built on this Mac: a copy of Veil's small `veil-app-launcher` program, an Info.plist
/// naming the Windows app, and an icon made from the icon the guest reported. It is signed ad hoc, so it
/// runs without a developer certificate, and registered with Launch Services so Spotlight, Launchpad and
/// Finder's Open With pick it up right away.
///
/// The installer only ever replaces or removes bundles whose Info.plist carries ``WindowsAppLauncherBundleSpec/appIdKey``,
/// so an app the user put in the same folder is never touched.
struct WindowsAppLauncherInstaller: Sendable {
    let folder: URL
    let launcherProgram: URL
    let veilVersion: String
    /// Signs a finished bundle. Replaceable in tests, which cannot assume `codesign` behaves the same everywhere.
    var sign: @Sendable (URL) throws -> Void = WindowsAppLauncherInstaller.signAdHoc
    /// Registers a finished bundle with Launch Services.
    var register: @Sendable (URL) -> Void = WindowsAppLauncherInstaller.registerWithLaunchServices

    func fingerprint(spec: WindowsAppLauncherBundleSpec, icon: Data, program: Data) -> String {
        var hasher = SHA256()
        hasher.update(data: Data("\(WindowsAppLauncherBundleSpec.formatVersion)\n\(spec.appId)\n\(spec.appName)\n\(veilVersion)\n".utf8))
        hasher.update(data: program)
        hasher.update(data: icon)
        return hasher.finalize().prefix(12).map { String(format: "%02x", $0) }.joined()
    }

    /// Creates or refreshes the launcher for one Windows app. Cheap when nothing changed: it reads one plist.
    @discardableResult
    func install(spec: WindowsAppLauncherBundleSpec, icns: Data) throws -> WindowsAppLauncherInstallOutcome {
        let fileManager = FileManager.default
        guard let program = fileManager.contents(atPath: launcherProgram.path) else {
            throw WindowsAppLauncherInstallError.launcherProgramMissing
        }
        try fileManager.createDirectory(at: folder, withIntermediateDirectories: true)

        let fingerprint = fingerprint(spec: spec, icon: icns, program: program)
        let destination = destinationURL(for: spec)
        let existing = Self.ownedLauncherInfo(at: destination)
        removeStaleLaunchers(for: spec.appId, keeping: destination)

        if let existing, existing.fingerprint == fingerprint {
            return .unchanged(destination)
        }

        // Built next to its destination, then moved into place, so a half-written launcher never appears in
        // Launchpad and the move stays on one volume.
        let staging = folder.appendingPathComponent(".staging-\(UUID().uuidString)", isDirectory: true)
        defer { try? fileManager.removeItem(at: staging) }
        let bundle = staging.appendingPathComponent(spec.bundleFileName, isDirectory: true)
        let contents = bundle.appendingPathComponent("Contents", isDirectory: true)
        let macOS = contents.appendingPathComponent("MacOS", isDirectory: true)
        let resources = contents.appendingPathComponent("Resources", isDirectory: true)
        try fileManager.createDirectory(at: macOS, withIntermediateDirectories: true)
        try fileManager.createDirectory(at: resources, withIntermediateDirectories: true)

        let executable = macOS.appendingPathComponent(WindowsAppLauncherBundleSpec.executableName)
        try program.write(to: executable)
        try fileManager.setAttributes([.posixPermissions: 0o755], ofItemAtPath: executable.path)
        try icns.write(to: resources.appendingPathComponent("\(WindowsAppLauncherBundleSpec.iconFileName).icns"))
        let plist = try PropertyListSerialization.data(
            fromPropertyList: spec.infoPlist(fingerprint: fingerprint, veilVersion: veilVersion),
            format: .xml,
            options: 0
        )
        try plist.write(to: contents.appendingPathComponent("Info.plist"))
        try Data("APPL????".utf8).write(to: contents.appendingPathComponent("PkgInfo"))

        try sign(bundle)

        if fileManager.fileExists(atPath: destination.path) {
            _ = try fileManager.replaceItemAt(destination, withItemAt: bundle)
        } else {
            try fileManager.moveItem(at: bundle, to: destination)
        }
        register(destination)
        return existing == nil ? .created(destination) : .updated(destination)
    }

    /// The bundle's own name, unless something that is not a Veil launcher already has it.
    func destinationURL(for spec: WindowsAppLauncherBundleSpec) -> URL {
        let preferred = folder.appendingPathComponent(spec.bundleFileName, isDirectory: true)
        guard FileManager.default.fileExists(atPath: preferred.path) else {
            return preferred
        }
        if let owner = Self.ownedLauncherInfo(at: preferred), owner.appId == spec.appId {
            return preferred
        }
        return folder.appendingPathComponent("\(spec.displayName) (\(spec.appId)).app", isDirectory: true)
    }

    /// Removes launchers for the same Windows app under an old name, for example after the guest renamed it.
    private func removeStaleLaunchers(for appId: String, keeping destination: URL) {
        let entries = (try? FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil)) ?? []
        for entry in entries where entry.pathExtension == "app" && entry.standardizedFileURL != destination.standardizedFileURL {
            if Self.ownedLauncherInfo(at: entry)?.appId == appId {
                try? FileManager.default.removeItem(at: entry)
            }
        }
    }

    struct OwnedLauncherInfo: Equatable {
        let appId: String
        let fingerprint: String?
    }

    /// The launcher details of a bundle Veil made, or nil for anything else.
    static func ownedLauncherInfo(at bundle: URL) -> OwnedLauncherInfo? {
        let plistURL = bundle.appendingPathComponent("Contents/Info.plist")
        guard let data = FileManager.default.contents(atPath: plistURL.path),
              let plist = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any],
              let appId = plist[WindowsAppLauncherBundleSpec.appIdKey] as? String,
              let identifier = plist["CFBundleIdentifier"] as? String,
              identifier.hasPrefix(WindowsAppLauncherBundleSpec.bundleIdentifierPrefix) else {
            return nil
        }
        return OwnedLauncherInfo(appId: appId, fingerprint: plist[WindowsAppLauncherBundleSpec.fingerprintKey] as? String)
    }

    @Sendable
    static func signAdHoc(_ bundle: URL) throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/codesign")
        process.arguments = ["--force", "--sign", "-", bundle.path]
        let errors = Pipe()
        process.standardError = errors
        process.standardOutput = FileHandle.nullDevice
        try process.run()
        let output = errors.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else {
            throw WindowsAppLauncherInstallError.signingFailed(
                String(decoding: output, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
            )
        }
    }

    @Sendable
    static func registerWithLaunchServices(_ bundle: URL) {
        LSRegisterURL(bundle as CFURL, true)
    }

    /// Where this Veil keeps the launcher program: `Contents/Helpers` in a built app, or beside the executable
    /// when run straight from `swift build`.
    static func bundledLauncherProgram(bundle: Bundle = .main) -> URL? {
        let candidates = [
            bundle.bundleURL.appendingPathComponent("Contents/Helpers/\(WindowsAppLauncherBundleSpec.executableName)"),
            bundle.executableURL?.deletingLastPathComponent()
                .appendingPathComponent(WindowsAppLauncherBundleSpec.executableName)
        ].compactMap { $0 }
        return candidates.first { FileManager.default.isExecutableFile(atPath: $0.path) }
    }
}

/// The launcher icon: the Windows app's own icon with Veil's badge, the same picture the Dock shows while the
/// app is in front.
@MainActor
enum WindowsAppLauncherIcon {
    static let sizes: [Int] = [16, 32, 64, 128, 256, 512, 1024]

    static func image(for app: WindowsApp) -> NSImage {
        guard let data = app.iconPngBase64.flatMap({ Data(base64Encoded: $0) }),
              let appIcon = NSImage(data: data) else {
            return WindowsAppDockIcon.veilIcon
        }
        return WindowsAppDockIcon.compose(appIcon: appIcon, badge: WindowsAppDockIcon.veilIcon)
    }

    /// An `.icns` with every size Finder and the Dock ask for.
    static func icnsData(for image: NSImage) -> Data? {
        let data = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(
            data,
            UTType.icns.identifier as CFString,
            sizes.count,
            nil
        ) else {
            return nil
        }
        for size in sizes {
            guard let cgImage = render(image, side: size) else {
                return nil
            }
            CGImageDestinationAddImage(destination, cgImage, nil)
        }
        guard CGImageDestinationFinalize(destination) else {
            return nil
        }
        return data as Data
    }

    private static func render(_ image: NSImage, side: Int) -> CGImage? {
        guard let context = CGContext(
            data: nil,
            width: side,
            height: side,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: CGColorSpace(name: CGColorSpace.sRGB)!,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else {
            return nil
        }
        context.interpolationQuality = .high
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(cgContext: context, flipped: false)
        image.draw(in: NSRect(x: 0, y: 0, width: side, height: side), from: .zero, operation: .copy, fraction: 1)
        NSGraphicsContext.restoreGraphicsState()
        return context.makeImage()
    }
}
