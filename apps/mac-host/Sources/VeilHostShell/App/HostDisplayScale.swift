import AppKit

/// This Mac's backing scale factor, read at the point of use so it follows the user between displays.
///
/// VeilHostCore does not import AppKit, so it cannot read this itself and takes it as a parameter. That
/// keeps the DPI comparison unit-testable without a window server.
///
/// `NSScreen.main` is the screen holding keyboard focus, not necessarily the screen a given mirrored
/// window sits on. On a mixed-DPI setup those differ, and there is no single correct answer to pick
/// instead: Windows exposes one display-scaling setting for the whole guest, so any recommendation has to
/// choose one screen. The focused screen is the one whose text the user is actually reading, which is what
/// this check is about. Existing placement code reads `NSScreen.main` the same way.
/// `@MainActor` to match the two other `NSScreen` reads in this package, which both sit inside `@MainActor`
/// types. `NSScreen.main` carries no isolation annotation in the current SDK, so a non-isolated read compiles
/// today — but relying on that would make this the one file that breaks if a future SDK annotates it. Every
/// call site is already main-actor isolated, since each one also touches `HostDashboardModel`.
@MainActor
enum HostDisplayScale {
    /// `nil` when no screen is attached, which reports the scaling state as unknown rather than claiming a
    /// match that was never measured.
    static var current: Double? {
        guard let screen = NSScreen.main else { return nil }
        return Double(screen.backingScaleFactor)
    }
}
