import AppKit

/// A launch that must not take the Mac over: Veil opens its windows behind the app in use and does not
/// activate itself until the user brings it forward.
///
/// Relaunching Veil to pick up a new build activated it at launch and again for each restored Windows app
/// window, pulling the person away from whatever they were doing. `script/build_and_run.sh` passes the
/// argument when `VEIL_LAUNCH_IN_BACKGROUND=1`.
@MainActor
enum QuietLaunch {
    static let argument = "-VeilLaunchInBackground"

    private(set) static var isActive = false
    private static var observer: NSObjectProtocol?

    /// Reads the launch argument; ends quiet mode the first time the user activates Veil.
    static func begin(arguments: [String] = ProcessInfo.processInfo.arguments) {
        guard arguments.contains(argument) else {
            return
        }
        isActive = true
        observer = NotificationCenter.default.addObserver(
            forName: NSApplication.didBecomeActiveNotification,
            object: nil,
            queue: .main
        ) { _ in
            MainActor.assumeIsolated {
                isActive = false
                if let observer {
                    NotificationCenter.default.removeObserver(observer)
                }
                observer = nil
            }
        }
    }

#if DEBUG
    /// Development builds only: a script that drives Veil goes back to quiet mode first, so the windows it
    /// opens stay behind the app the person is using even after they have used Veil in this run.
    static func resumeForScript() {
        guard !isActive else {
            return
        }
        isActive = true
        observer = NotificationCenter.default.addObserver(
            forName: NSApplication.didBecomeActiveNotification,
            object: nil,
            queue: .main
        ) { _ in
            MainActor.assumeIsolated {
                isActive = false
                if let observer {
                    NotificationCenter.default.removeObserver(observer)
                }
                observer = nil
            }
        }
    }
#endif

    /// Activates Veil unless this is a quiet launch the user has not yet brought forward.
    static func activateApplication() {
        guard !isActive else {
            return
        }
        NSApp.activate(ignoringOtherApps: true)
    }
}
