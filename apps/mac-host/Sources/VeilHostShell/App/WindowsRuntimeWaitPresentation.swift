import Foundation
import VeilHostCore

struct WindowsRuntimeWaitContext: Equatable {
    let attemptStartedAt: Date?
    let persistedLaunchStartedAt: Date?

    /// A persisted console launch can belong to a previous attempt. Only the
    /// timestamp captured by this host for the current start is eligible for
    /// elapsed-time presentation.
    var effectiveStartedAt: Date? {
        attemptStartedAt
    }
}

struct WindowsRuntimeWaitPresentation: Equatable {
    let elapsedSeconds: Int?
    let elapsedText: String?
    let title: String
    let detail: String
    let isLongWait: Bool

    static func resolve(
        state: VMRuntimeState,
        attemptStartedAt: Date?,
        now: Date
    ) -> WindowsRuntimeWaitPresentation? {
        guard state == .starting else {
            return nil
        }

        let elapsedSeconds = attemptStartedAt.map {
            max(0, Int(now.timeIntervalSince($0).rounded(.down)))
        }
        let isLongWait = elapsedSeconds.map { $0 >= 90 } ?? false
        let title = isLongWait ? String(localized: "Windows is taking longer than usual") : String(localized: "Starting Windows")
        let detail = isLongWait
            ? String(localized: "Windows is still booting. Keep this window open and use Refresh status to inspect the runtime.")
            : String(localized: "Veil is waiting for Windows and its display to respond.")

        return WindowsRuntimeWaitPresentation(
            elapsedSeconds: elapsedSeconds,
            elapsedText: elapsedSeconds.map(Self.formatElapsed),
            title: title,
            detail: detail,
            isLongWait: isLongWait
        )
    }

    static func resolve(
        state: VMRuntimeState,
        context: WindowsRuntimeWaitContext,
        now: Date
    ) -> WindowsRuntimeWaitPresentation? {
        resolve(
            state: state,
            attemptStartedAt: context.effectiveStartedAt,
            now: now
        )
    }

    private static func formatElapsed(_ seconds: Int) -> String {
        guard seconds >= 60 else {
            return String(seconds) + "s"
        }

        return String(seconds / 60) + "m " + String(seconds % 60) + "s"
    }
}
