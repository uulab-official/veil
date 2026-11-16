import Foundation

/// Keeps the Windows IME's Korean/English mode the same as the macOS input source, per Windows process.
///
/// The host can only press the Windows Hangul key, which toggles. Pressing it on every Mac switch kept the two
/// in step only while nothing else changed: a Windows app that opened while the Mac was on Korean started in
/// English, and a switch made while another Mac app was in front never reached Windows, after which every
/// switch left them opposite. Reading the mode back from Windows was not reliable for TSF apps such as the
/// Windows 11 Notepad (docs/protocol.md § Input IME Mode).
///
/// So the host remembers what it last made each process's mode, and presses the key only when that differs
/// from the Mac. The mode belongs to the app's input thread rather than to one window, so it is kept by
/// process id, which a dialog shares with the window that opened it. A process the host has not seen starts
/// in English, as the Windows Korean IME starts a new app.
public struct GuestHangulModeTracker: Equatable, Sendable {
    private var isKoreanByProcess: [Int: Bool] = [:]
    private var processByWindow: [String: Int] = [:]

    public init() {}

    /// Whether a macOS input source is Korean, from its languages (`kTISPropertyInputSourceLanguages`).
    public static func isKorean(languages: [String]) -> Bool {
        languages.first.map { $0 == "ko" || $0.hasPrefix("ko-") } ?? false
    }

    /// Records that the window belongs to the process, and returns whether the Hangul key has to be pressed in
    /// it for Windows to match the Mac. After a `true`, the host is expected to press it.
    public mutating func align(windowId: String, processId: Int, macIsKorean: Bool) -> Bool {
        processByWindow[windowId] = processId
        let current = isKoreanByProcess[processId] ?? false
        isKoreanByProcess[processId] = macIsKorean
        return current != macIsKorean
    }

    /// The user pressed the Hangul key in Windows alone (the right Command key) to bring the two back together,
    /// so Windows now matches the Mac.
    public mutating func realigned(windowId: String, processId: Int, macIsKorean: Bool) {
        processByWindow[windowId] = processId
        isKoreanByProcess[processId] = macIsKorean
    }

    /// Forgets the process once its last known window closed: a new app may reuse its id and starts in English.
    public mutating func windowClosed(windowId: String) {
        guard let processId = processByWindow.removeValue(forKey: windowId) else {
            return
        }
        if !processByWindow.values.contains(processId) {
            isKoreanByProcess[processId] = nil
        }
    }

    /// The Windows session ended or restarted: every app starts again in English.
    public mutating func reset() {
        self = GuestHangulModeTracker()
    }
}
