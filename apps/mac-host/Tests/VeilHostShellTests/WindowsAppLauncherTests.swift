import AppKit
import Foundation
import Testing
import VeilHostCore
import VeilLauncherSupport
@testable import VeilHostShell

struct VeilURLRouteTests {
    @Test("open-app and launcher-request URLs round-trip")
    func routesRoundTrip() throws {
        let openApp = VeilURLRoute.openApp(appId: "winapp_notepad")
        #expect(openApp.url.absoluteString == "veil://open-app?id=winapp_notepad")
        #expect(VeilURLRoute(url: openApp.url) == openApp)

        let id = UUID()
        let request = VeilURLRoute.launcherRequest(id: id)
        #expect(VeilURLRoute(url: request.url) == request)
    }

    @Test("the scheme and host are case-insensitive")
    func caseInsensitiveSchemeAndHost() throws {
        let url = try #require(URL(string: "VEIL://Open-App?id=winapp_paint"))
        #expect(VeilURLRoute(url: url) == .openApp(appId: "winapp_paint"))
    }

    @Test("URLs that are not a supported veil:// action are ignored", arguments: [
        "https://open-app?id=winapp_notepad",
        "veil://open-app",
        "veil://open-app?id=",
        "veil://open-app?id=winapp%20notepad",
        "veil://open-app?id=..%2F..%2Fetc",
        "veil://launcher-request?id=not-a-uuid",
        "veil://open-file?path=/Users/me/.ssh/id_ed25519&app=winapp_notepad",
        "veil://delete-everything"
    ])
    func rejectsUnsupportedURLs(_ string: String) throws {
        let url = try #require(URL(string: string))
        #expect(VeilURLRoute(url: url) == nil)
    }

    @Test("app ids are limited to the characters the guest uses")
    func appIdValidation() {
        #expect(VeilURLRoute.isValidAppId("winapp_notepad"))
        #expect(VeilURLRoute.isValidAppId("winapp.calc-2"))
        #expect(!VeilURLRoute.isValidAppId(""))
        #expect(!VeilURLRoute.isValidAppId(String(repeating: "a", count: 129)))
        #expect(!VeilURLRoute.isValidAppId("winapp/notepad"))
        #expect(!VeilURLRoute.isValidAppId("메모장"))
    }
}

struct WindowsAppLauncherRequestStoreTests {
    private func makeStore() -> WindowsAppLauncherRequestStore {
        WindowsAppLauncherRequestStore(veilApplicationSupport: FileManager.default.temporaryDirectory
            .appendingPathComponent("VeilLauncherRequestTests-\(UUID().uuidString)", isDirectory: true))
    }

    @Test("a request is read once and then gone")
    func takeConsumesRequest() throws {
        let store = makeStore()
        defer { try? FileManager.default.removeItem(at: store.directory.deletingLastPathComponent()) }
        let request = WindowsAppLauncherRequest(appId: "winapp_notepad", filePaths: ["/tmp/report.txt"])
        let id = try store.write(request)

        #expect(store.directory.lastPathComponent == "Launcher Requests")
        let taken = try store.take(id: id)
        #expect(taken.appId == "winapp_notepad")
        #expect(taken.fileURLs == [URL(fileURLWithPath: "/tmp/report.txt")])
        #expect(throws: WindowsAppLauncherRequestError.missing) { try store.take(id: id) }
    }

    @Test("an old request cannot be replayed")
    func expiredRequestIsRefusedAndDeleted() throws {
        let store = makeStore()
        defer { try? FileManager.default.removeItem(at: store.directory.deletingLastPathComponent()) }
        let createdAt = Date(timeIntervalSince1970: 1_000_000)
        let id = try store.write(WindowsAppLauncherRequest(appId: "winapp_notepad", createdAt: createdAt))

        #expect(throws: WindowsAppLauncherRequestError.expired) {
            try store.take(id: id, now: createdAt.addingTimeInterval(WindowsAppLauncherRequestStore.maximumAge + 1))
        }
        #expect(!FileManager.default.fileExists(atPath: store.url(for: id).path))
    }

    @Test("requests with a bad app id or a relative path are refused")
    func malformedRequestsAreRefused() throws {
        let store = makeStore()
        defer { try? FileManager.default.removeItem(at: store.directory.deletingLastPathComponent()) }

        let badApp = try store.write(WindowsAppLauncherRequest(appId: "../notepad"))
        #expect(throws: WindowsAppLauncherRequestError.invalidAppId) { try store.take(id: badApp) }

        let relative = try store.write(WindowsAppLauncherRequest(appId: "winapp_notepad", filePaths: ["report.txt"]))
        #expect(throws: WindowsAppLauncherRequestError.relativeFilePath) { try store.take(id: relative) }
    }

    @Test("the request folder is private to the user")
    func requestFolderIsPrivate() throws {
        let store = makeStore()
        defer { try? FileManager.default.removeItem(at: store.directory.deletingLastPathComponent()) }
        let id = try store.write(WindowsAppLauncherRequest(appId: "winapp_notepad"))

        let folderMode = try FileManager.default.attributesOfItem(atPath: store.directory.path)[.posixPermissions] as? Int
        let fileMode = try FileManager.default.attributesOfItem(atPath: store.url(for: id).path)[.posixPermissions] as? Int
        #expect(folderMode == 0o700)
        #expect(fileMode == 0o600)
    }

    @Test("the launcher and Veil agree on where requests live")
    func standardLocationFollowsVeilOverride() {
        let store = WindowsAppLauncherRequestStore.standard(environment: ["VEIL_APPLICATION_SUPPORT_DIRECTORY": "/tmp/VeilSupport"])
        #expect(store.directory.path == "/tmp/VeilSupport/Launcher Requests")
    }
}

struct WindowsAppLauncherBundleSpecTests {
    @Test("bundle identifiers and names are valid for any app id or name")
    func identifiersAndNamesAreSanitized() {
        let spec = WindowsAppLauncherBundleSpec(appId: "winapp_notepad", appName: "Notepad")
        #expect(spec.bundleIdentifier == "org.uulab.veil.winapp.winapp-notepad")
        #expect(spec.bundleFileName == "Notepad.app")

        let odd = WindowsAppLauncherBundleSpec(appId: "winapp_x", appName: " ../Reports: 2026/Q3 ")
        #expect(odd.displayName == "-Reports- 2026-Q3")
        #expect(WindowsAppLauncherBundleSpec(appId: "winapp_x", appName: "  ").displayName == "winapp_x")
    }

    @Test("Notepad and Paint offer their file types under Open With without becoming the default")
    func documentTypes() throws {
        let notepad = WindowsAppLauncherBundleSpec(appId: "winapp_notepad", appName: "Notepad")
        let plist = notepad.infoPlist(fingerprint: "abc", veilVersion: "0.1.0")
        let types = try #require(plist["CFBundleDocumentTypes"] as? [[String: Any]])
        #expect(types.count == 1)
        #expect((types[0]["LSItemContentTypes"] as? [String])?.contains("public.plain-text") == true)
        #expect(types[0]["LSHandlerRank"] as? String == "Alternate")

        let paint = WindowsAppLauncherBundleSpec.documentTypes(forAppId: "winapp_paint")
        #expect(paint.first?.contentTypes.contains("public.png") == true)

        let calculator = WindowsAppLauncherBundleSpec(appId: "winapp_calculator", appName: "Calculator")
        #expect(calculator.infoPlist(fingerprint: "abc", veilVersion: "0.1.0")["CFBundleDocumentTypes"] == nil)
    }

    @Test("the Info.plist names the Windows app and stays out of the Dock while it runs")
    func infoPlistKeys() {
        let plist = WindowsAppLauncherBundleSpec(appId: "winapp_paint", appName: "Paint")
            .infoPlist(fingerprint: "f00d", veilVersion: "0.2.0")
        #expect(plist["CFBundleExecutable"] as? String == "veil-app-launcher")
        #expect(plist["CFBundleIconFile"] as? String == "AppIcon")
        #expect(plist["LSUIElement"] as? Bool == true)
        #expect(plist[WindowsAppLauncherBundleSpec.appIdKey] as? String == "winapp_paint")
        #expect(plist[WindowsAppLauncherBundleSpec.fingerprintKey] as? String == "f00d")
        #expect(PropertyListSerialization.propertyList(plist, isValidFor: .xml))
    }

    @Test("launchers live in the user's own Applications folder")
    func defaultFolder() {
        let folder = WindowsAppLauncherBundleSpec.defaultFolder(home: URL(fileURLWithPath: "/Users/someone"))
        #expect(folder.path == "/Users/someone/Applications/Veil Apps")
    }
}

final class WindowsAppLauncherInstallerTests {
    let root: URL
    let folder: URL
    let program: URL

    init() throws {
        root = FileManager.default.temporaryDirectory.appendingPathComponent("VeilLauncherInstallerTests-\(UUID().uuidString)")
        folder = root.appendingPathComponent("Veil Apps", isDirectory: true)
        program = root.appendingPathComponent("veil-app-launcher")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        try Data("launcher".utf8).write(to: program)
    }

    deinit {
        try? FileManager.default.removeItem(at: root)
    }

    private func makeInstaller(signed: SignedBundles = SignedBundles()) -> WindowsAppLauncherInstaller {
        var installer = WindowsAppLauncherInstaller(folder: folder, launcherProgram: program, veilVersion: "0.1.0")
        installer.sign = { signed.append($0) }
        installer.register = { _ in }
        return installer
    }

    @Test("creates a complete launcher bundle")
    func createsBundle() throws {
        let signed = SignedBundles()
        let outcome = try makeInstaller(signed: signed).install(
            spec: WindowsAppLauncherBundleSpec(appId: "winapp_notepad", appName: "Notepad"),
            icns: Data("icon".utf8)
        )

        let bundle = folder.appendingPathComponent("Notepad.app", isDirectory: true)
        #expect(outcome == .created(bundle))
        #expect(signed.count == 1)
        let executable = bundle.appendingPathComponent("Contents/MacOS/veil-app-launcher").path
        #expect(FileManager.default.isExecutableFile(atPath: executable))
        #expect(FileManager.default.fileExists(atPath: bundle.appendingPathComponent("Contents/Resources/AppIcon.icns").path))
        #expect(WindowsAppLauncherInstaller.ownedLauncherInfo(at: bundle)?.appId == "winapp_notepad")
        // No staging folders are left behind for Launchpad to find.
        let leftovers = try FileManager.default.contentsOfDirectory(atPath: folder.path)
        #expect(leftovers == ["Notepad.app"])
    }

    @Test("does nothing when the launcher is current, and rebuilds when the icon changes")
    func skipsCurrentLauncherAndRebuildsOnChange() throws {
        let signed = SignedBundles()
        let installer = makeInstaller(signed: signed)
        let spec = WindowsAppLauncherBundleSpec(appId: "winapp_notepad", appName: "Notepad")
        let bundle = folder.appendingPathComponent("Notepad.app", isDirectory: true)

        _ = try installer.install(spec: spec, icns: Data("icon".utf8))
        #expect(try installer.install(spec: spec, icns: Data("icon".utf8)) == .unchanged(bundle))
        #expect(try installer.install(spec: spec, icns: Data("new icon".utf8)) == .updated(bundle))
        #expect(signed.count == 2)
    }

    @Test("never replaces an app the user put in the folder")
    func leavesForeignAppsAlone() throws {
        let foreign = folder.appendingPathComponent("Notepad.app/Contents", isDirectory: true)
        try FileManager.default.createDirectory(at: foreign, withIntermediateDirectories: true)
        let foreignPlist = try PropertyListSerialization.data(
            fromPropertyList: ["CFBundleIdentifier": "com.example.notepad"],
            format: .xml,
            options: 0
        )
        try foreignPlist.write(to: foreign.appendingPathComponent("Info.plist"))

        let outcome = try makeInstaller().install(
            spec: WindowsAppLauncherBundleSpec(appId: "winapp_notepad", appName: "Notepad"),
            icns: Data("icon".utf8)
        )

        #expect(outcome == .created(folder.appendingPathComponent("Notepad (winapp_notepad).app", isDirectory: true)))
        let untouched = try Data(contentsOf: foreign.appendingPathComponent("Info.plist"))
        #expect(untouched == foreignPlist)
    }

    @Test("a renamed app replaces its old launcher")
    func renamedAppRemovesOldLauncher() throws {
        let installer = makeInstaller()
        _ = try installer.install(spec: WindowsAppLauncherBundleSpec(appId: "winapp_paint", appName: "Paint"), icns: Data("i".utf8))
        _ = try installer.install(spec: WindowsAppLauncherBundleSpec(appId: "winapp_paint", appName: "Paint 11"), icns: Data("i".utf8))

        let names = try FileManager.default.contentsOfDirectory(atPath: folder.path)
        #expect(names == ["Paint 11.app"])
    }

    @Test("a Veil without the launcher program reports it instead of writing a broken bundle")
    func missingProgram() throws {
        let installer = WindowsAppLauncherInstaller(
            folder: folder,
            launcherProgram: root.appendingPathComponent("missing"),
            veilVersion: "0.1.0"
        )
        #expect(throws: WindowsAppLauncherInstallError.launcherProgramMissing) {
            try installer.install(spec: WindowsAppLauncherBundleSpec(appId: "winapp_paint", appName: "Paint"), icns: Data())
        }
        #expect(!FileManager.default.fileExists(atPath: folder.appendingPathComponent("Paint.app").path))
    }
}

/// Collects the bundles a test installer was asked to sign.
final class SignedBundles: @unchecked Sendable {
    private let lock = NSLock()
    private var urls: [URL] = []

    func append(_ url: URL) {
        lock.withLock { urls.append(url) }
    }

    var count: Int {
        lock.withLock { urls.count }
    }
}

@MainActor
struct WindowsAppLauncherIconTests {
    @Test("the launcher icon is a real icns with Finder's sizes")
    func writesICNS() throws {
        let image = NSImage(size: NSSize(width: 64, height: 64), flipped: false) { rect in
            NSColor.systemBlue.setFill()
            rect.fill()
            return true
        }
        let data = try #require(WindowsAppLauncherIcon.icnsData(for: image))
        #expect(data.prefix(4) == Data("icns".utf8))
        #expect(NSImage(data: data) != nil)
    }

    @Test("apps without a reported icon fall back to Veil's icon")
    func fallsBackWithoutIcon() {
        let app = WindowsApp(id: "winapp_calculator", name: "Calculator", exePath: "calc.exe", publisher: "Microsoft", iconId: "icon_calculator")
        #expect(WindowsAppLauncherIcon.image(for: app) === WindowsAppDockIcon.veilIcon)
    }
}

struct LauncherFileOpenTests {
    @Test("files opened with a launcher follow the drag-and-drop rules")
    func fileOpenUsesDropRules() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("VeilLauncherFileTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }

        let report = folder.appendingPathComponent("2026:08:12 report.txt")
        try Data("hello".utf8).write(to: report)
        #expect(WindowsAppWindowPresenter.droppedFileOutcome(forFileAt: report)
            == .ready(fileName: "2026_08_12 report.txt", contentBase64: Data("hello".utf8).base64EncodedString()))

        let empty = folder.appendingPathComponent("empty.txt")
        try Data().write(to: empty)
        #expect(WindowsAppWindowPresenter.droppedFileOutcome(forFileAt: empty) == .refused(.emptyFile(fileName: "empty.txt")))
    }
}

/// Builds a launcher from the real `veil-app-launcher` program and signs it with the real `codesign`, the way
/// Veil does on a user's Mac. Skipped when the launcher product has not been built.
struct WindowsAppLauncherSigningTests {
    static var builtLauncherProgram: URL? {
        let packageRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let candidate = packageRoot.appendingPathComponent(".build/debug/veil-app-launcher")
        return FileManager.default.isExecutableFile(atPath: candidate.path) ? candidate : nil
    }

    @Test("a generated launcher passes strict signature verification", .enabled(if: builtLauncherProgram != nil))
    @MainActor
    func generatedLauncherVerifies() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("VeilLauncherSigning-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: root) }
        var installer = WindowsAppLauncherInstaller(
            folder: root,
            launcherProgram: try #require(Self.builtLauncherProgram),
            veilVersion: "0.1.0"
        )
        installer.register = { _ in }

        let outcome = try installer.install(
            spec: WindowsAppLauncherBundleSpec(appId: "winapp_notepad", appName: "Notepad"),
            icns: try #require(WindowsAppLauncherIconTests.sampleICNS())
        )
        guard case .created(let bundle) = outcome else {
            Issue.record("expected a new launcher, got \(outcome)")
            return
        }

        let verify = Process()
        verify.executableURL = URL(fileURLWithPath: "/usr/bin/codesign")
        verify.arguments = ["--verify", "--strict", "--deep", bundle.path]
        try verify.run()
        verify.waitUntilExit()
        #expect(verify.terminationStatus == 0)
        #expect(Bundle(url: bundle)?.bundleIdentifier == "org.uulab.veil.winapp.winapp-notepad")
    }
}

extension WindowsAppLauncherIconTests {
    @MainActor
    static func sampleICNS() -> Data? {
        let image = NSImage(size: NSSize(width: 64, height: 64), flipped: false) { rect in
            NSColor.systemTeal.setFill()
            rect.fill()
            return true
        }
        return WindowsAppLauncherIcon.icnsData(for: image)
    }
}

@MainActor
struct WindowsAppLauncherLibraryTests {
    private struct Sandbox {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("VeilLauncherLibrary-\(UUID().uuidString)")
        var folder: URL { root.appendingPathComponent("Veil Apps", isDirectory: true) }
        var diagnosticsURL: URL { root.appendingPathComponent("Diagnostics/windows-app-launchers.json") }
        let defaults = UserDefaults(suiteName: "VeilLauncherLibraryTests-\(UUID().uuidString)")!

        func readDiagnostics() throws -> WindowsAppLauncherDiagnostics {
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            return try decoder.decode(WindowsAppLauncherDiagnostics.self, from: Data(contentsOf: diagnosticsURL))
        }
    }

    private let notepad = WindowsApp(
        id: "winapp_notepad",
        name: "Notepad",
        exePath: "C:\\Windows\\System32\\notepad.exe",
        publisher: "Microsoft",
        iconId: "icon_notepad"
    )

    private func install(_ library: WindowsAppLauncherLibrary, _ apps: [WindowsApp]) async {
        await withCheckedContinuation { continuation in
            library.ensureLaunchers(for: apps) { continuation.resume() }
        }
    }

    @Test("a launcher that was not made says why in the diagnostics file")
    func recordsSkipReasons() async throws {
        let sandbox = Sandbox()
        defer { try? FileManager.default.removeItem(at: sandbox.root) }

        let missingProgram = WindowsAppLauncherLibrary(
            folder: sandbox.folder, launcherProgram: nil, diagnosticsURL: sandbox.diagnosticsURL, defaults: sandbox.defaults,
            register: { _ in }
        )
        await install(missingProgram, [notepad])
        #expect(try sandbox.readDiagnostics().apps["winapp_notepad"]?.status == "skipped-no-launcher-program")

        sandbox.defaults.set(false, forKey: WindowsAppLauncherLibrary.enabledDefaultsKey)
        let disabled = WindowsAppLauncherLibrary(
            folder: sandbox.folder, launcherProgram: sandbox.root, diagnosticsURL: sandbox.diagnosticsURL, defaults: sandbox.defaults,
            register: { _ in }
        )
        await install(disabled, [notepad])
        let diagnostics = try sandbox.readDiagnostics()
        #expect(diagnostics.apps["winapp_notepad"]?.status == "skipped-disabled")
        #expect(diagnostics.enabled == false)
        #expect(!FileManager.default.fileExists(atPath: sandbox.folder.path))

        disabled.recordSkip(appId: "winapp_paint", appName: "Paint", status: "skipped-not-agent", detail: "demo")
        #expect(try sandbox.readDiagnostics().apps["winapp_paint"]?.status == "skipped-not-agent")
    }

    @Test("a failed install is recorded with its error", .enabled(if: WindowsAppLauncherSigningTests.builtLauncherProgram != nil))
    func recordsInstallFailure() async throws {
        let sandbox = Sandbox()
        defer { try? FileManager.default.removeItem(at: sandbox.root) }
        // A file where the folder should be makes the install fail the way an unwritable folder would.
        try FileManager.default.createDirectory(at: sandbox.root, withIntermediateDirectories: true)
        try Data().write(to: sandbox.folder)

        let library = WindowsAppLauncherLibrary(
            folder: sandbox.folder,
            launcherProgram: WindowsAppLauncherSigningTests.builtLauncherProgram,
            diagnosticsURL: sandbox.diagnosticsURL,
            defaults: sandbox.defaults,
            register: { _ in }
        )
        await install(library, [notepad])
        let entry = try #require(try sandbox.readDiagnostics().apps["winapp_notepad"])
        #expect(entry.status == "failed")
        #expect(entry.detail?.isEmpty == false)
    }

    @Test("an opened app gets a signed launcher and a diagnostics entry pointing at it",
          .enabled(if: WindowsAppLauncherSigningTests.builtLauncherProgram != nil))
    func createsLauncherAndRecordsIt() async throws {
        let sandbox = Sandbox()
        defer { try? FileManager.default.removeItem(at: sandbox.root) }
        let library = WindowsAppLauncherLibrary(
            folder: sandbox.folder,
            launcherProgram: WindowsAppLauncherSigningTests.builtLauncherProgram,
            diagnosticsURL: sandbox.diagnosticsURL,
            defaults: sandbox.defaults,
            register: { _ in }
        )

        await install(library, [notepad])
        let entry = try #require(try sandbox.readDiagnostics().apps["winapp_notepad"])
        #expect(entry.status == "created")
        let bundlePath = try #require(entry.bundlePath)
        #expect(FileManager.default.fileExists(atPath: bundlePath + "/Contents/MacOS/veil-app-launcher"))

        // Same inputs again: nothing to do, and no new install is started.
        await install(library, [notepad])
        #expect(try sandbox.readDiagnostics().apps["winapp_notepad"]?.status == "created")
    }
}
