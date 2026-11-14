import AppKit
import SwiftUI
import VeilHostCore
import VeilLauncherSupport

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private static let launchVerificationMaximumAttempts = 60
    var dockMenuProvider: (() -> NSMenu?)?
    var reopenHandler: (() -> Void)?
    /// Runs before Veil quits, for example to suspend Windows. A second Quit while it runs exits at once.
    /// Runs before Veil quits. Returning false cancels the quit.
    var terminationHandler: (@MainActor (_ isSystemQuit: Bool) async -> Bool)?
    private var isRunningTerminationHandler = false
    /// Handles `veil://` URLs once the main scene has configured itself. URLs that arrive earlier, such as the
    /// one that cold-launched Veil from a Windows app launcher, wait in `pendingURLs` until then.
    var urlHandler: ((URL) -> Void)? {
        didSet {
            guard let urlHandler else {
                return
            }
            let queued = pendingURLs
            pendingURLs = []
            queued.forEach(urlHandler)
        }
    }
    private var pendingURLs: [URL] = []
    private let launchVerificationReportURL = LaunchVerificationArguments.reportURL(
        from: ProcessInfo.processInfo.arguments
    )
    private var appIconSource: AppIconSource = .fallback

    func applicationWillFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)
        NSWindow.allowsAutomaticWindowTabbing = false
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        appIconSource = applyBundledAppIcon()
        NSApp.setActivationPolicy(.regular)
        QuietLaunch.begin()
        QuietLaunch.activateApplication()
        DispatchQueue.main.async {
            MainWindowChrome.showMainWindow()
        }
        scheduleLaunchVerificationReportIfNeeded()
    }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        guard let terminationHandler, !isRunningTerminationHandler else {
            return .terminateNow
        }

        isRunningTerminationHandler = true
        let isSystemQuit = Self.isSystemQuit()
        Task { @MainActor in
            let proceeds = await terminationHandler(isSystemQuit)
            isRunningTerminationHandler = false
            sender.reply(toApplicationShouldTerminate: proceeds)
        }
        return .terminateLater
    }

    /// Whether macOS is quitting Veil to log out, restart, or shut down, rather than the user quitting it.
    /// The quit Apple event then names a reason; a question asked then would hold up the logout.
    private static func isSystemQuit() -> Bool {
        guard let reason = NSAppleEventManager.shared().currentAppleEvent?
            .attributeDescriptor(forKeyword: AEKeyword(kAEQuitReason))?.enumCodeValue else {
            return false
        }
        return [kAELogOut, kAEReallyLogOut, kAEShowRestartDialog, kAEShowShutdownDialog, kAERestart, kAEShutDown]
            .map { OSType($0) }
            .contains(reason)
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        guard let reopenHandler else {
            return true
        }

        reopenHandler()
        return false
    }

    // The launcher owns its own layout and the host persists mirrored Windows app windows through
    // WindowRestoreIntentStore. Letting AppKit restore the SwiftUI Window scene can therefore restore
    // an empty state after the user previously closed or hid the launcher: applicationDidFinishLaunching
    // runs before the scene exists, MainWindowChrome has nothing to show, and the app remains windowless.
    // Always presenting the main scene gives a Finder/Dock launch the same deterministic entry point.
    func applicationShouldRestoreState(_ app: NSApplication) -> Bool {
        false
    }

    func application(_ application: NSApplication, open urls: [URL]) {
        for url in urls where url.scheme?.lowercased() == VeilURLRoute.scheme {
            if let urlHandler {
                urlHandler(url)
            } else {
                pendingURLs.append(url)
            }
        }
    }

    func applicationDockMenu(_ sender: NSApplication) -> NSMenu? {
        dockMenuProvider?()
    }

    @MainActor
    private func applyBundledAppIcon() -> AppIconSource {
        guard let iconURL = Bundle.main.url(forResource: "VeilAppIcon", withExtension: "icns"),
              let icon = NSImage(contentsOf: iconURL) else {
            NSApp.applicationIconImage = fallbackAppIcon()
            return .fallback
        }

        NSApp.applicationIconImage = icon
        return .bundled
    }

    private func scheduleLaunchVerificationReportIfNeeded(attempt: Int = 1) {
        guard launchVerificationReportURL != nil else {
            return
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) { [weak self] in
            guard let self else {
                return
            }

            MainWindowChrome.showMainWindow()
            let report = MainWindowChrome.launchReport(appIconSource: self.appIconSource)
            if report.meetsLauncherContract || attempt >= Self.launchVerificationMaximumAttempts {
                self.writeLaunchVerificationReport(report)
            } else {
                self.scheduleLaunchVerificationReportIfNeeded(attempt: attempt + 1)
            }
        }
    }

    private func writeLaunchVerificationReport(_ report: MainWindowLaunchReport) {
        guard let launchVerificationReportURL else {
            return
        }

        do {
            let encoder = PropertyListEncoder()
            encoder.outputFormat = .xml
            let data = try encoder.encode(report)
            try FileManager.default.createDirectory(
                at: launchVerificationReportURL.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            try data.write(to: launchVerificationReportURL, options: .atomic)
        } catch {
            NSLog("Veil launch verification report could not be written: \(error.localizedDescription)")
        }
    }

    private func fallbackAppIcon() -> NSImage {
        let dimension: CGFloat = 1024
        let size = NSSize(width: dimension, height: dimension)
        let image = NSImage(size: size)
        image.lockFocus()

        defer { image.unlockFocus() }

        let backgroundRect = NSRect(origin: .zero, size: size)
        let gradient = NSGradient(colors: [
            NSColor(calibratedRed: 0.05, green: 0.09, blue: 0.18, alpha: 1),
            NSColor(calibratedRed: 0.11, green: 0.44, blue: 0.78, alpha: 1)
        ])
        gradient?.draw(in: backgroundRect, angle: 145)

        let iconRect = NSRect(x: 132, y: 132, width: 760, height: 760)
        let path = NSBezierPath(roundedRect: iconRect, xRadius: 188, yRadius: 188)
        NSColor.white.setFill()
        path.fill()

        let outer = NSBezierPath(roundedRect: iconRect.insetBy(dx: 66, dy: 66), xRadius: 150, yRadius: 150)
        NSColor(calibratedRed: 0.00, green: 0.57, blue: 0.95, alpha: 1).setFill()
        outer.fill()

        let inner = NSBezierPath(roundedRect: iconRect.insetBy(dx: 164, dy: 164), xRadius: 110, yRadius: 110)
        NSColor(calibratedRed: 0.95, green: 0.37, blue: 0.14, alpha: 1).setFill()
        inner.fill()

        let text = "V"
        let paragraph = NSMutableParagraphStyle()
        paragraph.alignment = .center

        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 430, weight: .bold),
            .foregroundColor: NSColor.black,
            .paragraphStyle: paragraph
        ]

        let textRect = NSRect(x: 110, y: 320, width: 804, height: 420)
        text.draw(with: textRect, options: .usesLineFragmentOrigin, attributes: attributes)

        return image
    }

}

// This selector is not surfaced consistently by the macOS SDK overlay, so keep it in an extension
// to avoid Swift's optional-protocol near-match warning while still disabling empty AppKit restoration.
extension AppDelegate {
    @objc(applicationShouldSaveState:)
    func applicationShouldSaveState(_ app: NSApplication) -> Bool {
        false
    }
}
