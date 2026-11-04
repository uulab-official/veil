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
            return "Stopping Windows closes mirrored app windows. The queued app launch will remain pending until Windows reconnects."
        case (true, false):
            return "Stopping Windows closes the mirrored Windows app window."
        case (false, true):
            return "The queued app launch will remain pending until Windows reconnects."
        case (false, false):
            return "Windows will shut down on this Mac."
        }
    }
}
