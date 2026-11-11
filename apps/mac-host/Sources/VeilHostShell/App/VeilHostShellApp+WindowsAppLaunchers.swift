import AppKit
import VeilHostCore
import VeilLauncherSupport

/// Keeps one launcher per Windows app the user has opened, in `~/Applications/Veil Apps`.
///
/// Remembers what it already wrote this run, so reopening Notepad ten times costs one plist read, not ten
/// signatures. Turned off with `defaults write org.uulab.veil.host-shell VeilCreatesWindowsAppLaunchers -bool NO`.
@MainActor
final class WindowsAppLauncherLibrary {
    static let shared = WindowsAppLauncherLibrary()
    static let enabledDefaultsKey = "VeilCreatesWindowsAppLaunchers"

    private var completedInputs: [String: String] = [:]
    private var inFlight: Set<String> = []

    var isEnabled: Bool {
        UserDefaults.standard.object(forKey: Self.enabledDefaultsKey) as? Bool ?? true
    }

    var folder: URL {
        WindowsAppLauncherBundleSpec.defaultFolder()
    }

    func ensureLaunchers(for apps: [WindowsApp]) {
        guard isEnabled,
              let program = WindowsAppLauncherInstaller.bundledLauncherProgram() else {
            return
        }

        for app in apps where VeilURLRoute.isValidAppId(app.id) {
            // Name and icon are all that can change from the guest's side; the installer's fingerprint covers the rest.
            let inputs = "\(app.name)\n\(app.iconPngBase64 ?? "")"
            guard completedInputs[app.id] != inputs, !inFlight.contains(app.id) else {
                continue
            }
            guard let icns = WindowsAppLauncherIcon.icnsData(for: WindowsAppLauncherIcon.image(for: app)) else {
                continue
            }

            inFlight.insert(app.id)
            let installer = WindowsAppLauncherInstaller(
                folder: folder,
                launcherProgram: program,
                veilVersion: Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0"
            )
            let spec = WindowsAppLauncherBundleSpec(appId: app.id, appName: app.name)
            let logger = VeilLog.integration
            Task.detached(priority: .utility) {
                let outcome = Result { try installer.install(spec: spec, icns: icns) }
                await MainActor.run {
                    self.inFlight.remove(app.id)
                    switch outcome {
                    case .success(let result):
                        self.completedInputs[app.id] = inputs
                        logger.info("Windows app launcher \(String(describing: result), privacy: .public)")
                    case .failure(let error):
                        logger.error("Windows app launcher for \(app.id, privacy: .public) failed: \(error.localizedDescription, privacy: .public)")
                    }
                }
            }
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
        let openAppIds = Set(model.mirrorSessions.filter { $0.connectionMode == .agent }.map(\.window.appId))
        let apps = model.apps.filter { openAppIds.contains($0.id) }
        WindowsAppLauncherLibrary.shared.ensureLaunchers(for: apps)
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
