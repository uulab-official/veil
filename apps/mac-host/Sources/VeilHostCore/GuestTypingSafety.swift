import Foundation

/// Why Veil must not type a command into the Windows desktop right now.
public enum GuestTypingRefusal: Equatable, Sendable {
    /// Windows has app windows open.
    case appsAreOpen
    /// The Windows tools were installed but do not answer, so nobody can say what is open in Windows.
    case toolsDoNotAnswer
}

/// Decides whether a command may be typed into Windows through QEMU.
///
/// The typed commands click a fixed place on the Windows screen, press Ctrl+A, and type into the Run
/// dialog. They are meant for a Windows with an empty desktop and no tools yet. On the live guest, with
/// apps open, they replaced the text of an open Notepad document, and once the tools had stopped answering
/// the host no longer knew that apps were open and typed anyway.
public enum GuestTypingSafety {
    /// - Parameters:
    ///   - hasLiveAgent: Whether the Windows tools are connected and can report the open windows.
    ///   - openWindowCount: Windows the host shows or the guest's layout reports.
    ///   - toolsWereInstalled: Whether this Windows ever had the tools, now or in an earlier run.
    public static func refusal(
        hasLiveAgent: Bool,
        openWindowCount: Int,
        toolsWereInstalled: Bool
    ) -> GuestTypingRefusal? {
        if openWindowCount > 0 {
            return .appsAreOpen
        }
        if hasLiveAgent {
            // The tools report every app window, and there is none.
            return nil
        }
        // A Windows that has had the tools is one somebody uses. Its apps cannot be seen from here, and
        // restarting Windows starts the tools again without typing anything.
        return toolsWereInstalled ? .toolsDoNotAnswer : nil
    }
}
