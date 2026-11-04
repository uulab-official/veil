import CoreGraphics
import Foundation
import Observation

extension HostDashboardModel {
    @discardableResult
    public func closeAllMirrorSessions() async -> [WindowCloseResponse] {
        let windowIds = mirrorSessions.map(\.id)
        var responses: [WindowCloseResponse] = []

        for windowId in windowIds {
            guard let response = await closeMirrorSession(windowId: windowId) else {
                continue
            }

            responses.append(response)
        }

        return responses
    }

    public func sendMouseInput(
        windowId: String,
        event: String,
        x: Int,
        y: Int,
        modifiers: [String] = []
    ) async {
        guard canSendInput(to: windowId) else {
            return
        }

        do {
            try await service.sendMouseInput(
                InputMouseEvent(windowId: windowId, event: event, x: x, y: y, modifiers: modifiers)
            )
        } catch {
            errorMessage = userMessage(for: error)
            phase = .failed
        }
    }

    /// Propagates a user resize from the macOS mirror to the real Windows HWND.
    ///
    /// The request is deliberately sent only after AppKit finishes the live resize gesture. During a
    /// drag the mirror remains responsive and aspect-correct; one bounded request at gesture end avoids
    /// flooding the guest agent with a network message for every intermediate pixel.
    @discardableResult
    public func resizeMirrorSession(windowId: String, width: Int, height: Int) async -> WindowResizeResponse? {
        guard canResizeMirrorSession(windowId: windowId),
              WindowResizeRequest.isPlausible(width: width, height: height) else {
            return nil
        }

        do {
            return try await service.resizeWindow(windowId: windowId, width: width, height: height)
        } catch {
            errorMessage = userMessage(for: error)
            phase = .failed
            return nil
        }
    }

    /// Sends committed Unicode text to a mirrored Windows window.
    ///
    /// This is the path for anything the Windows virtual-key map cannot express, which includes every
    /// Hangul, kana, and Han character. macOS finishes the IME composition first; only the committed
    /// result reaches the guest.
    @discardableResult
    public func sendTextInput(windowId: String, text: String) async -> Bool {
        guard canSendInput(to: windowId),
              InputTextEvent.isSendable(text) else {
            return false
        }

        do {
            try await service.sendTextInput(InputTextEvent(windowId: windowId, text: text))
            return true
        } catch {
            errorMessage = userMessage(for: error)
            phase = .failed
            return false
        }
    }

    public func sendKeyInput(
        windowId: String,
        event: String,
        key: String,
        windowsVirtualKey: Int,
        modifiers: [String] = []
    ) async {
        guard canSendInput(to: windowId) else {
            return
        }

        do {
            try await service.sendKeyInput(
                InputKeyEvent(
                    windowId: windowId,
                    event: event,
                    key: key,
                    windowsVirtualKey: windowsVirtualKey,
                    modifiers: modifiers
                )
            )
        } catch {
            errorMessage = userMessage(for: error)
            phase = .failed
        }
    }

    /// - Returns: Whether the clipboard write reached the guest. Callers that follow this with a paste
    ///   shortcut must not send it on `.failed`: Ctrl+V does not fail, it pastes whatever Windows had
    ///   before, into the user's document, silently.
    @discardableResult
    public func sendHostClipboardText(_ text: String) async -> HostClipboardSendOutcome {
        guard canSendHostClipboardText else {
            return .skipped
        }

        let nextSequence = clipboardSequence + 1
        do {
            try await service.sendClipboardText(
                ClipboardTextSet(
                    requestId: "req_clipboard_\(nextSequence)",
                    origin: "host",
                    sequence: nextSequence,
                    text: text
                )
            )
            clipboardSequence = nextSequence
            return .sent
        } catch {
            // Not `phase = .failed`. That phase renders as "Connection failed" in the runtime status line
            // and the menu bar title, so one undelivered ⌘V would have reported the Windows connection as
            // down while every other action still worked. The sequence deliberately does not advance, so
            // loop prevention does not record a host update the guest never received.
            return .failed(reason: userMessage(for: error))
        }
    }

    public func receiveClipboardText(_ clipboard: ClipboardTextSet, receivedAt: Date = Date()) -> Bool {
        guard clipboard.origin == "guest",
              clipboard.sequence > lastGuestClipboardSequence else {
            return false
        }

        // Rejected rather than truncated. A truncated clipboard is worse than a missing one: the user pastes
        // half a document into something and has no way to notice. The host bounded its own *outbound* text at
        // 4096 units and accepted inbound text with no bound at all, and this value is both stored and written
        // straight to `NSPasteboard`.
        guard clipboard.text.utf16.count <= Self.maximumGuestClipboardUTF16Length else {
            VeilLog.agent.notice(
                "Rejected a guest clipboard update of \(clipboard.text.utf16.count, privacy: .public) UTF-16 units, above the accepted maximum."
            )
            return false
        }

        // Checked last, so a message rejected above never spends the allowance. Otherwise a guest could deny
        // the user their own clipboard by sending malformed updates.
        guard guestClipboardRateLimiter.allows(at: receivedAt) else {
            VeilLog.agent.notice("Rate limited a guest clipboard update.")
            return false
        }

        latestGuestClipboardText = clipboard.text
        lastGuestClipboardSequence = clipboard.sequence
        return true
    }

    public func receiveWindowsNotification(
        _ notification: WindowsNotificationReceivedEvent,
        receivedAt: Date = Date()
    ) -> Bool {
        guard !notification.notificationId.isEmpty,
              !notification.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              !latestWindowsNotifications.contains(where: { $0.notificationId == notification.notificationId }) else {
            return false
        }

        // The five-entry dedupe above stops repeats, not floods: rotating six ids defeats it completely. These
        // become real macOS notifications carrying guest-chosen text under Veil's identity, so an unbounded
        // stream is a phishing surface rather than only a nuisance.
        guard guestNotificationRateLimiter.allows(at: receivedAt) else {
            VeilLog.agent.notice("Rate limited a Windows notification.")
            return false
        }

        latestWindowsNotifications.insert(notification, at: 0)
        if latestWindowsNotifications.count > 5 {
            latestWindowsNotifications.removeLast(latestWindowsNotifications.count - 5)
        }
        return true
    }
}
