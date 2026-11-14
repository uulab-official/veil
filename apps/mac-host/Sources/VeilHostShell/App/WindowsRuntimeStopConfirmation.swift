enum WindowsRuntimeStopConfirmation {
    static func needsConfirmation(
        hasMirroredWindowsApp: Bool,
        hasQueuedLaunch: Bool
    ) -> Bool {
        hasMirroredWindowsApp || hasQueuedLaunch
    }

    static func message(
        hasMirroredWindowsApp: Bool,
        hasQueuedLaunch: Bool
    ) -> String {
        switch (hasMirroredWindowsApp, hasQueuedLaunch) {
        case (true, true):
            return String(localized: "Stopping Windows closes mirrored app windows. The queued app launch will remain pending until Windows reconnects.")
        case (true, false):
            return String(localized: "Stopping Windows closes the mirrored Windows app window.")
        case (false, true):
            return String(localized: "The queued app launch will remain pending until Windows reconnects.")
        case (false, false):
            return String(localized: "Windows will shut down on this Mac.")
        }
    }
}
