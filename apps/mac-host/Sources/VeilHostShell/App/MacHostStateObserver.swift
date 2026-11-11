import AppKit
import VeilHostCore

/// Watches the Mac state Windows should follow: waking from sleep and the light/dark appearance.
///
/// Observation only. It never activates the app or posts input; the callbacks just mark guest sync
/// work, which `GuestStateSyncCoordinator` sends once the agent is reachable.
@MainActor
final class MacHostStateObserver {
    private var wakeObserver: NSObjectProtocol?
    private var appearanceObservation: NSKeyValueObservation?
    private var lastTheme: GuestAppearanceTheme?

    func start(onWake: @escaping @MainActor () -> Void, onAppearanceChange: @escaping @MainActor () -> Void) {
        guard wakeObserver == nil else {
            return
        }

        wakeObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didWakeNotification,
            object: nil,
            queue: .main
        ) { _ in
            MainActor.assumeIsolated { onWake() }
        }

        lastTheme = Self.currentTheme()
        // Veil never overrides NSApp.appearance, so the app's effective appearance is the system one.
        appearanceObservation = NSApp.observe(\.effectiveAppearance, options: [.new]) { [weak self] _, _ in
            Task { @MainActor in
                guard let self else {
                    return
                }
                let theme = Self.currentTheme()
                guard theme != self.lastTheme else {
                    return
                }
                self.lastTheme = theme
                onAppearanceChange()
            }
        }
    }

    static func currentTheme() -> GuestAppearanceTheme {
        let appearance = NSApp?.effectiveAppearance ?? NSAppearance.currentDrawing()
        return appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua ? .dark : .light
    }
}
