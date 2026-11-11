import AppKit
import VeilHostCore
import VeilLauncherSupport

/// What happened the last time Veil tried to make one app's launcher. Written to
/// `~/Library/Application Support/Veil/Diagnostics/windows-app-launchers.json`, so a launcher that did not
/// appear can be explained without a debugger or a log stream.
struct WindowsAppLauncherDiagnosticEntry: Codable, Equatable {
    var appName: String
    /// `created`, `updated`, `unchanged`, `installing`, `failed`, or a `skipped-…` reason.
    var status: String
    var detail: String?
    var bundlePath: String?
    var at: Date
}

struct WindowsAppLauncherDiagnostics: Codable, Equatable {
    var updatedAt: Date
    var enabled: Bool
    var folder: String
    var launcherProgram: String?
    var apps: [String: WindowsAppLauncherDiagnosticEntry]

    static let fileName = "windows-app-launchers.json"

    static func defaultURL(applicationSupport: URL = VeilApplicationSupport.directory) -> URL {
        applicationSupport
            .appendingPathComponent("Diagnostics", isDirectory: true)
            .appendingPathComponent(fileName)
    }
}

/// Keeps one launcher per Windows app the user has opened, in `~/Applications/Veil Apps`.
///
/// Remembers what it already wrote this run, so reopening Notepad ten times costs one plist read, not ten
/// signatures. Turned off with `defaults write org.uulab.veil.host-shell VeilCreatesWindowsAppLaunchers -bool NO`.
/// Every attempt, including every reason for doing nothing, is recorded in ``WindowsAppLauncherDiagnostics``.
@MainActor
final class WindowsAppLauncherLibrary {
    static let shared = WindowsAppLauncherLibrary()
    static let enabledDefaultsKey = "VeilCreatesWindowsAppLaunchers"

    private var completedInputs: [String: String] = [:]
    private var inFlight: Set<String> = []
    private var diagnostics: WindowsAppLauncherDiagnostics
    let diagnosticsURL: URL
    let folder: URL
    let launcherProgram: URL?
    let defaults: UserDefaults

    init(
        folder: URL = WindowsAppLauncherBundleSpec.defaultFolder(),
        launcherProgram: URL? = WindowsAppLauncherInstaller.bundledLauncherProgram(),
        diagnosticsURL: URL = WindowsAppLauncherDiagnostics.defaultURL(),
        defaults: UserDefaults = .standard
    ) {
        self.folder = folder
        self.launcherProgram = launcherProgram
        self.diagnosticsURL = diagnosticsURL
        self.defaults = defaults
        diagnostics = WindowsAppLauncherDiagnostics(
            updatedAt: Date(),
            enabled: true,
            folder: folder.path,
            launcherProgram: launcherProgram?.path,
            apps: [:]
        )
    }

    var isEnabled: Bool {
        defaults.object(forKey: Self.enabledDefaultsKey) as? Bool ?? true
    }

    var latestDiagnostics: WindowsAppLauncherDiagnostics {
        diagnostics
    }

    /// Records why an open window's app gets no launcher, for causes found before ``ensureLaunchers(for:)``.
    func recordSkip(appId: String, appName: String, status: String, detail: String) {
        record(appId: appId, appName: appName, status: status, detail: detail)
    }

    /// Starts the installs; `onFinish` runs on the main actor once every started install has finished.
    func ensureLaunchers(for apps: [WindowsApp], onFinish: (@MainActor () -> Void)? = nil) {
        guard isEnabled else {
            apps.forEach { record(appId: $0.id, appName: $0.name, status: "skipped-disabled", detail: "\(Self.enabledDefaultsKey) is NO") }
            onFinish?()
            return
        }
        guard let program = launcherProgram else {
            apps.forEach {
                record(appId: $0.id, appName: $0.name, status: "skipped-no-launcher-program",
                       detail: "No veil-app-launcher in Contents/Helpers or beside the executable")
            }
            onFinish?()
            return
        }

        var jobs: [(app: WindowsApp, inputs: String, spec: WindowsAppLauncherBundleSpec, icns: Data)] = []
        for app in apps {
            guard VeilURLRoute.isValidAppId(app.id) else {
                record(appId: app.id, appName: app.name, status: "skipped-invalid-app-id", detail: nil)
                continue
            }
            // Name and icon are all that can change from the guest's side; the installer's fingerprint covers the rest.
            let inputs = "\(app.name)\n\(app.iconPngBase64 ?? "")"
            guard completedInputs[app.id] != inputs, !inFlight.contains(app.id) else {
                continue
            }
            guard let icns = WindowsAppLauncherIcon.icnsData(for: WindowsAppLauncherIcon.image(for: app)) else {
                record(appId: app.id, appName: app.name, status: "failed", detail: "Could not render the launcher icon")
                continue
            }
            inFlight.insert(app.id)
            record(appId: app.id, appName: app.name, status: "installing", detail: nil)
            jobs.append((app, inputs, WindowsAppLauncherBundleSpec(appId: app.id, appName: app.name), icns))
        }
        guard !jobs.isEmpty else {
            onFinish?()
            return
        }

        let installer = WindowsAppLauncherInstaller(
            folder: folder,
            launcherProgram: program,
            veilVersion: Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0"
        )
        Task { @MainActor in
            for job in jobs {
                let spec = job.spec
                let icns = job.icns
                // Off the main actor: signing runs `codesign` and waits for it.
                let outcome = await Task.detached(priority: .utility) {
                    Result { try installer.install(spec: spec, icns: icns) }
                }.value
                inFlight.remove(job.app.id)
                switch outcome {
                case .success(let result):
                    completedInputs[job.app.id] = job.inputs
                    let (status, url): (String, URL) = switch result {
                    case .created(let url): ("created", url)
                    case .updated(let url): ("updated", url)
                    case .unchanged(let url): ("unchanged", url)
                    }
                    record(appId: job.app.id, appName: job.app.name, status: status, detail: nil, bundlePath: url.path)
                case .failure(let error):
                    record(appId: job.app.id, appName: job.app.name, status: "failed", detail: String(describing: error))
                }
            }
            onFinish?()
        }
    }

    private func record(appId: String, appName: String, status: String, detail: String?, bundlePath: String? = nil) {
        let now = Date()
        diagnostics.updatedAt = now
        diagnostics.enabled = isEnabled
        diagnostics.apps[appId] = WindowsAppLauncherDiagnosticEntry(
            appName: appName,
            status: status,
            detail: detail,
            bundlePath: bundlePath,
            at: now
        )
        // Notice, not info: info messages are not kept by `log show`, which is how this gets checked headlessly.
        if status == "failed" {
            VeilLog.integration.error("Launcher \(appId, privacy: .public): \(status, privacy: .public) \(detail ?? "", privacy: .public)")
        } else {
            VeilLog.integration.notice("Launcher \(appId, privacy: .public): \(status, privacy: .public) \(detail ?? bundlePath ?? "", privacy: .public)")
        }

        do {
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            try FileManager.default.createDirectory(
                at: diagnosticsURL.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            try encoder.encode(diagnostics).write(to: diagnosticsURL, options: .atomic)
        } catch {
            VeilLog.integration.error("Launcher diagnostics could not be written: \(error.localizedDescription, privacy: .public)")
        }
    }
}

extension VeilHostShellApp {
    func configureVeilURLBridge() {
        appDelegate.urlHandler = { url in
            handleVeilURL(url)
        }
    }

    /// Creates launchers for the Windows apps that have a window open through the guest agent.
    func syncWindowsAppLaunchers() {
        syncWindowsAppLaunchers(for: model.mirrorSessions)
    }

    /// Called whenever a Windows app window is shown on the Mac. That is an AppKit path, so it runs even while
    /// Veil's own SwiftUI window is hidden, which the `onChange` hooks on that window cannot promise.
    func syncWindowsAppLauncher(for session: WindowMirrorSession) {
        syncWindowsAppLaunchers(for: [session])
    }

    private func syncWindowsAppLaunchers(for sessions: [WindowMirrorSession]) {
        let library = WindowsAppLauncherLibrary.shared
        var apps: [WindowsApp] = []
        var seen: Set<String> = []
        for session in sessions where seen.insert(session.window.appId).inserted {
            let appId = session.window.appId
            guard session.connectionMode == .agent else {
                library.recordSkip(appId: appId, appName: session.window.title, status: "skipped-not-agent",
                                   detail: "Window is mirrored in \(session.connectionMode) mode")
                continue
            }
            guard let app = model.apps.first(where: { $0.id == appId }) else {
                library.recordSkip(appId: appId, appName: session.window.title, status: "skipped-not-in-app-list",
                                   detail: "No app with this id in the latest app list (\(model.apps.count) apps)")
                continue
            }
            apps.append(app)
        }
        library.ensureLaunchers(for: apps)
    }

    func handleVeilURL(_ url: URL) {
        guard let route = VeilURLRoute(url: url) else {
            VeilLog.integration.notice("Ignored a veil:// URL Veil does not handle")
            return
        }

        switch route {
        case .openApp(let appId):
            openWindowsAppFromMac(appId: appId)
        case .launcherRequest(let id):
            let store = WindowsAppLauncherRequestStore(veilApplicationSupport: VeilApplicationSupport.directory)
            do {
                let request = try store.take(id: id)
                if request.filePaths.isEmpty {
                    openWindowsAppFromMac(appId: request.appId)
                } else {
                    openMacFiles(request.fileURLs, inWindowsAppWithId: request.appId)
                }
            } catch {
                // A missing or expired request is a replayed or stale URL, not something the user just did.
                VeilLog.integration.notice("Ignored a launcher request: \(String(describing: error), privacy: .public)")
            }
        }
    }

    private func launchableWindowsApp(id appId: String) -> WindowsApp? {
        guard let app = model.apps.first(where: { $0.id == appId })
                ?? KnownWindowsAppCatalog.apps.first(where: { $0.id == appId }) else {
            activateMainWindow()
            displayMessage = String(localized: "That Windows app is no longer available.")
            return nil
        }
        guard vmModel.snapshot?.installEvidence.isInstalled == true else {
            activateMainWindow()
            displayMessage = String(localized: "Windows is not installed yet. Finish setup in Veil first.")
            return nil
        }
        return app
    }

    /// A launcher, a Dock item or a `veil://open-app` link: the same one-click path as the launcher list.
    func openWindowsAppFromMac(appId: String) {
        guard let app = launchableWindowsApp(id: appId) else {
            return
        }
        runOneClickAppLaunch(appId: app.id)
    }

    /// Finder's Open With: sends each file through the same path as dragging it onto the app's window, so the
    /// same size limit, name rewriting and guest-side checks apply, starting Windows first when needed.
    func openMacFiles(_ fileURLs: [URL], inWindowsAppWithId appId: String) {
        guard let app = launchableWindowsApp(id: appId) else {
            return
        }
        if let refusal = WindowsAppFileDropPolicy.refusal(forFileCount: fileURLs.count) {
            activateMainWindow()
            displayMessage = refusal.message
            return
        }

        Task { @MainActor in
            guard await ensureLiveAgentConnection(appName: app.name) else {
                return
            }

            for fileURL in fileURLs {
                let outcome = await Task.detached(priority: .userInitiated) {
                    WindowsAppWindowPresenter.droppedFileOutcome(forFileAt: fileURL)
                }.value

                switch outcome {
                case .refused(let refusal):
                    model.recordFileDropRefusal(refusal)
                    activateMainWindow()
                    displayMessage = refusal.message
                case .ready(let fileName, let contentBase64):
                    displayMessage = String(localized: "Opening \(fileName) in \(app.name).")
                    guard let result = await model.openFile(appId: app.id, fileName: fileName, contentBase64: contentBase64) else {
                        activateMainWindow()
                        displayMessage = model.lastFileDropRefusal?.message
                            ?? String(localized: "Windows could not open \(fileName).")
                        continue
                    }
                    await presentWindowWhenFirstFrameArrives(result, successMessage: String(localized: "\(fileName) opened in \(app.name)."))
                }
            }
        }
    }

    /// Starts or resumes Windows and waits for the guest agent, the way the one-click launch does.
    private func ensureLiveAgentConnection(appName: String) async -> Bool {
        if model.hasLiveAgentConnection {
            return true
        }

        cancelAutomaticQuietRuntime()
        displayMessage = String(localized: "Starting Windows to open \(appName).")
        await startOrResumeWindows()
        guard vmModel.snapshot?.state == .running || vmModel.snapshot?.state == .starting else {
            activateMainWindow()
            displayMessage = vmModel.errorMessage ?? String(localized: "Windows could not start.")
            return false
        }

        let report = await model.waitForLiveAgentConnection(
            endpoint: agentURLString,
            timeoutSeconds: OneClickAppLaunchCoordinator.agentWaitSeconds
        )
        guard report.status == .connected else {
            activateMainWindow()
            displayMessage = report.diagnostic.errorMessage
                ?? String(localized: "Windows started, but Veil could not connect to it yet. Try again in a moment.")
            return false
        }
        return true
    }

    private func presentWindowWhenFirstFrameArrives(_ result: WindowsAppLaunchResult, successMessage: String) async {
        let windowId = result.window.windowId
        let appId = result.window.appId
        _ = try? await WindowsAppWindowPresentationReadiness.wait(
            timeoutSeconds: OneClickAppLaunchCoordinator.firstFrameWaitSeconds,
            sessionProvider: { model.mirrorSessions.first { $0.id == windowId && $0.window.appId == appId } },
            compositedImageProvider: { model.compositedFrameImage(for: $0) }
        )
        presentWindowsAppWindowWhenReady(
            windowId: windowId,
            expectedAppId: appId,
            intent: .userRequested,
            bringToFront: true,
            successMessage: successMessage
        )
    }
}
