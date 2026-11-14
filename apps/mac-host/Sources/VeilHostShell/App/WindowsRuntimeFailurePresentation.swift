import Foundation
import VeilHostCore

struct WindowsRuntimeFailurePresentation: Equatable {
    let title: String
    let message: String
    let refreshTitle: String
    let detailsTitle: String

    static func resolve(
        state: VMRuntimeState,
        errorMessage: String?,
        snapshotDetail: String
    ) -> WindowsRuntimeFailurePresentation? {
        guard state == .failed else {
            return nil
        }

        let message = [errorMessage, snapshotDetail]
            .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
            .first { !$0.isEmpty }
            ?? String(localized: "The last Windows start attempt failed. Open settings for diagnostics.")

        return WindowsRuntimeFailurePresentation(
            title: String(localized: "Windows needs attention"),
            message: message,
            refreshTitle: String(localized: "Refresh status"),
            detailsTitle: String(localized: "Open settings")
        )
    }
}
