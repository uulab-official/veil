import AppKit
import VeilLauncherSupport

/// The program inside every Windows app launcher in `~/Applications/Veil Apps`.
///
/// It does one thing: tell Veil which Windows app to open, with any Mac files the user opened with the
/// launcher, and quit. Veil starts Windows when needed and shows the app as a Mac window. Plain app launches
/// use `veil://open-app`; launches with files write a request into Veil's Application Support folder and
/// name it with `veil://launcher-request`, so file paths never travel in a URL.
@MainActor
final class LauncherDelegate: NSObject, NSApplicationDelegate {
    private var pendingFiles: [URL] = []
    private var didFinishLaunching = false
    private var inFlight = 0

    func application(_ application: NSApplication, open urls: [URL]) {
        pendingFiles += urls.filter(\.isFileURL)
        // Files opened at launch arrive before applicationDidFinishLaunching and are sent with it. Files
        // opened while the launcher is still running (it quits within a second) are sent on their own.
        if didFinishLaunching {
            dispatch()
        }
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        didFinishLaunching = true
        dispatch()
    }

    private func dispatch() {
        let files = pendingFiles
        pendingFiles = []

        guard let appId = Bundle.main.object(forInfoDictionaryKey: WindowsAppLauncherBundleSpec.appIdKey) as? String,
              VeilURLRoute.isValidAppId(appId) else {
            fail("This launcher is damaged. Open the Windows app from Veil once to rebuild it.")
            return
        }

        let route: VeilURLRoute
        if files.isEmpty {
            route = .openApp(appId: appId)
        } else {
            let store = WindowsAppLauncherRequestStore.standard()
            store.removeExpired()
            do {
                let id = try store.write(WindowsAppLauncherRequest(appId: appId, filePaths: files.map(\.path)))
                route = .launcherRequest(id: id)
            } catch {
                fail("Veil could not receive the files: \(error.localizedDescription)")
                return
            }
        }

        inFlight += 1
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = true
        NSWorkspace.shared.open(route.url, configuration: configuration) { _, error in
            Task { @MainActor in
                self.inFlight -= 1
                if let error {
                    self.fail("Veil could not be opened. Make sure Veil is installed. (\(error.localizedDescription))")
                    return
                }
                self.terminateWhenIdle()
            }
        }
    }

    private func terminateWhenIdle() {
        guard inFlight == 0, pendingFiles.isEmpty else {
            return
        }
        NSApp.terminate(nil)
    }

    private func fail(_ message: String) {
        let appName = Bundle.main.object(forInfoDictionaryKey: WindowsAppLauncherBundleSpec.appNameKey) as? String
            ?? "Windows app"
        NSApp.activate()
        let alert = NSAlert()
        alert.messageText = "\(appName) could not open"
        alert.informativeText = message
        alert.alertStyle = .warning
        alert.runModal()
        NSApp.terminate(nil)
    }
}

let application = NSApplication.shared
let delegate = LauncherDelegate()
application.delegate = delegate
application.setActivationPolicy(.accessory)
application.run()
