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
        modifiers: [String] = [],
        deltaX: Int? = nil,
        deltaY: Int? = nil
    ) async {
        guard canSendInput(to: windowId) else {
            return
        }
        // A press or a turn of the wheel sent through the hardware lands on whatever is on top in Windows,
        // so it is not sent at a point another window covers there. The agent is asked to bring the window
        // forward instead, which it may or may not be allowed to do for a window above it; the next press
        // goes through once the point is clear. Moves and releases always go, or a button would stick.
        if event == "leftDown" || event == "rightDown" || event == "scroll",
           let layout = GuestWindowLayoutStore.shared.latest,
           HardwareInputRouting.origin(windowId: windowId, layout: layout) != nil,
           HardwareInputRouting.isCovered(windowId: windowId, x: x, y: y, layout: layout) {
            _ = await focusMirrorSession(windowId: windowId)
            return
        }
        if sendThroughHardware(windowId: windowId, { translator, origin, _ in
            translator.mouse(
                event: event, x: x, y: y, origin: origin, modifiers: modifiers, deltaX: deltaX, deltaY: deltaY)
        }) != nil {
            return
        }

        do {
            if let pointer = try await service.sendMouseInputReportingPointer(
                InputMouseEvent(
                    windowId: windowId,
                    event: event,
                    x: x,
                    y: y,
                    modifiers: modifiers,
                    deltaX: deltaX,
                    deltaY: deltaY
                )
            ) {
                onGuestPointerMoved?(pointer)
            }
        } catch {
            if await dropMirrorSessionIfUntracked(windowId: windowId, error: error) {
                return
            }
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
    /// Resizes a mirrored window after first growing the guest display when the window would not fit on it.
    ///
    /// See `MirroredWindowDisplayFit`: without this, zooming on a Mac screen larger than the guest display
    /// only stretched the guest's bitmap.
    ///
    /// Requests for one window are coalesced: while one is in flight, newer sizes replace each other and only
    /// the latest is sent next. A live resize reports many sizes, and sending each one in turn would leave
    /// Windows replaying stale sizes after the user had already let go.
    public func resizeMirrorSession(
        windowId: String,
        width: Int,
        height: Int,
        macScreenWidth: Int,
        macScreenHeight: Int,
        pixelsPerPoint: Int = 1
    ) async -> WindowResizeResponse? {
        pendingMirrorResizes[windowId] = PendingMirrorResize(
            width: width,
            height: height,
            macScreenWidth: macScreenWidth,
            macScreenHeight: macScreenHeight,
            pixelsPerPoint: pixelsPerPoint
        )
        guard !mirrorResizesInFlight.contains(windowId) else {
            return nil
        }

        mirrorResizesInFlight.insert(windowId)
        defer {
            mirrorResizesInFlight.remove(windowId)
        }

        var response: WindowResizeResponse?
        while let next = pendingMirrorResizes.removeValue(forKey: windowId) {
            await growGuestDisplayIfNeeded(windowId: windowId, for: next)
            response = await resizeMirrorSession(windowId: windowId, width: next.width, height: next.height)
        }
        return response
    }

    private func growGuestDisplayIfNeeded(windowId: String, for request: PendingMirrorResize) async {
        guard canResizeMirrorSession(windowId: windowId),
              canResizeDisplay,
              let displaySize = MirroredWindowDisplayFit.displaySize(
                windowWidth: request.width,
                windowHeight: request.height,
                currentDisplay: guestDisplaySize,
                macScreenWidth: request.macScreenWidth,
                macScreenHeight: request.macScreenHeight,
                pixelsPerPoint: request.pixelsPerPoint
              ) else {
            return
        }

        let response = await resizeDisplay(width: displaySize.width, height: displaySize.height)
        VeilLog.window.notice(
            "Guest display \(displaySize.width)x\(displaySize.height) for window \(request.width)x\(request.height): accepted=\(response?.accepted ?? false, privacy: .public)"
        )
    }

    public func resizeMirrorSession(windowId: String, width: Int, height: Int) async -> WindowResizeResponse? {
        guard canResizeMirrorSession(windowId: windowId),
              WindowResizeRequest.isPlausible(width: width, height: height) else {
            return nil
        }

        GuestWindowLayoutStore.shared.expectFrameChange(windowId: windowId)
        do {
            return try await service.resizeWindow(windowId: windowId, width: width, height: height)
        } catch {
            errorMessage = userMessage(for: error)
            phase = .failed
            return nil
        }
    }

    /// Sets the Windows IME mode, once per change: `lastSentImeMode` is cleared when the agent reconnects so
    /// a restarted agent, which starts with no mode, gets it again.
    public func syncGuestImeMode(_ mode: GuestImeMode) async {
        guard hasLiveAgentConnection, health?.capabilities.imeMode == true else {
            lastSentImeMode = nil
            return
        }
        let connection = health?.agentVersion
        guard lastSentImeMode?.mode != mode || lastSentImeMode?.connection != connection else {
            return
        }
        do {
            try await service.setGuestImeMode(mode)
            lastSentImeMode = (mode, connection)
        } catch {
            VeilLog.window.notice("IME mode \(mode.rawValue, privacy: .public) not set: \(String(describing: error), privacy: .public)")
        }
    }

    /// Whether the connected agent can start the tools update itself, with nothing typed into Windows.
    public var agentStartsToolsUpdate: Bool {
        hasLiveAgentConnection && health?.capabilities.toolsUpdate == true
    }

    /// Has the agent start the tools update from the disc the host just inserted. Returns the file it
    /// started, or nil when the agent cannot or would not.
    ///
    /// Windows takes a moment to mount a disc that was just inserted, and until then the agent answers that
    /// there is none. So the request is repeated for a while before giving up.
    public func startToolsUpdateThroughAgent(
        attempts: Int = 10,
        retryDelay: Duration = .milliseconds(1_500)
    ) async -> String? {
        guard agentStartsToolsUpdate else {
            return nil
        }
        for attempt in 1...max(1, attempts) {
            do {
                let response = try await service.startToolsUpdate(ToolsUpdateRequest())
                if response.accepted {
                    return response.entryPoint ?? ""
                }
            } catch {
                VeilLog.runtime.notice(
                    "Tools update through the agent, attempt \(attempt, privacy: .public): \(String(describing: error), privacy: .public)"
                )
            }
            if attempt < attempts {
                try? await Task.sleep(for: retryDelay)
            }
        }
        return nil
    }

    /// Removes the Windows drive for the Mac folder. Nil when the agent cannot, or did not answer.
    public func unmountHostFolder(driveLetter: String) async -> HostFolderStatus? {
        guard hasLiveAgentConnection, health?.capabilities.hostFolder == true else {
            return nil
        }
        return try? await service.unmountHostFolder(
            HostFolderUnmountRequest(requestId: "req_host_folder_unmount", driveLetter: driveLetter)
        ).hostFolder
    }

    /// Asks the agent to map the Mac folder Veil serves over WebDAV. Nil when the agent cannot, or did not answer.
    public func mountHostFolder(port: Int, token: String, driveLetter: String, label: String) async -> HostFolderStatus? {
        guard hasLiveAgentConnection, health?.capabilities.hostFolder == true else {
            return nil
        }
        do {
            return try await service.mountHostFolder(
                HostFolderMountRequest(requestId: "req_host_folder", port: port, token: token, driveLetter: driveLetter, label: label)
            ).hostFolder
        } catch {
            VeilLog.window.notice("Host folder mount failed: \(String(describing: error), privacy: .public)")
            return nil
        }
    }

    /// Sends committed Unicode text to a mirrored Windows window.
    ///
    /// This is the path for anything the Windows virtual-key map cannot express, which includes every
    /// Hangul, kana, and Han character. macOS finishes the IME composition first; only the committed
    /// result reaches the guest.
    @discardableResult
    public func sendTextInput(windowId: String, text: String, replaceLength: Int = 0) async -> Bool {
        guard canSendInput(to: windowId),
              InputTextEvent.isSendable(text, replaceLength: replaceLength),
              replaceLength == 0 || supportsTextComposition else {
            return false
        }
        if let sent = sendThroughHardware(windowId: windowId, { translator, _, _ in
            // Hardware keys cannot take back what was typed, nor type what a US keyboard has no key for.
            replaceLength == 0 ? translator.text(text) : nil
        }) {
            return sent
        }

        do {
            try await service.sendTextInput(
                InputTextEvent(windowId: windowId, text: text, replaceLength: replaceLength > 0 ? replaceLength : nil)
            )
            return true
        } catch {
            if await dropMirrorSessionIfUntracked(windowId: windowId, error: error) {
                return false
            }
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
        if sendThroughHardware(windowId: windowId, { translator, _, _ in
            translator.key(event: event, windowsVirtualKey: windowsVirtualKey, modifiers: modifiers)
        }) != nil {
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
            if await dropMirrorSessionIfUntracked(windowId: windowId, error: error) {
                return
            }
            errorMessage = userMessage(for: error)
            phase = .failed
        }
    }

    /// Sends a window's input through the virtual hardware when the layout marks the window as one the
    /// agent cannot reach.
    ///
    /// - Returns: nil when the window is an ordinary one and the input should go to the agent. Otherwise
    ///   whether events were sent: false when there is no hardware connection yet or nothing to send. Such
    ///   input is dropped, not handed to the agent, whose injection Windows would discard without a word.
    private func sendThroughHardware(
        windowId: String,
        _ makeEvents: (inout HardwareInputTranslator, (x: Int, y: Int), WindowLayoutEvent) -> [HardwareInputEvent]?
    ) -> Bool? {
        guard let layout = GuestWindowLayoutStore.shared.latest,
              let origin = HardwareInputRouting.origin(windowId: windowId, layout: layout) else {
            return nil
        }
        guard let hardwareInput, hardwareInput.isReady,
              let events = makeEvents(&hardwareInputTranslator, origin, layout),
              !events.isEmpty else {
            return false
        }
        hardwareInput.send(events)
        return true
    }

    /// Drops a mirror session the guest has already reported as gone.
    ///
    /// Returns whether the error was `window_not_tracked`, so callers can skip the
    /// "Connection failed" phase: the connection is fine, the window simply no longer exists.
    func dropMirrorSessionIfUntracked(windowId: String, error: any Error) async -> Bool {
        guard let agentError = error as? VeilHostError,
              case .agentError(let code, _) = agentError,
              code == "window_not_tracked" else {
            return false
        }

        await removeWindowState(windowId: windowId)
        return true
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

    /// Sends a Mac pasteboard image. Same delivery contract as ``sendHostClipboardText(_:)``, except that an
    /// agent without the capability is `.failed` rather than `.skipped`: pasting Windows' own clipboard when
    /// the user copied a picture on the Mac is the stale paste that outcome exists to prevent.
    public func sendHostClipboardImage(png: Data) async -> HostClipboardSendOutcome {
        guard canSendHostClipboardImage else {
            return .failed(reason: HostDashboardServiceError.clipboardFormatUnsupported.localizedDescription)
        }

        let payload: ClipboardImagePayload
        do {
            payload = try ClipboardImagePayload(png: png)
        } catch {
            return .failed(reason: error.localizedDescription)
        }

        let nextSequence = clipboardSequence + 1
        do {
            try await service.sendClipboardImage(
                payload.message(requestId: "req_clipboard_\(nextSequence)", origin: "host", sequence: nextSequence)
            )
            clipboardSequence = nextSequence
            return .sent
        } catch {
            return .failed(reason: userMessage(for: error))
        }
    }

    /// Names files the shell has already copied into the shared folder. See ``ClipboardFilePaste``.
    public func sendHostClipboardFiles(shareName: String, relativePaths: [String]) async -> HostClipboardSendOutcome {
        guard canSendHostClipboardFiles else {
            return .failed(reason: HostDashboardServiceError.clipboardFormatUnsupported.localizedDescription)
        }

        let nextSequence = clipboardSequence + 1
        do {
            try await service.sendClipboardFiles(
                ClipboardFilesSet(
                    requestId: "req_clipboard_\(nextSequence)",
                    sequence: nextSequence,
                    shareName: shareName,
                    relativePaths: relativePaths
                )
            )
            clipboardSequence = nextSequence
            return .sent
        } catch {
            return .failed(reason: userMessage(for: error))
        }
    }

    /// Accepts a guest image only after ``ClipboardImagePayload`` has verified it. Text and image share one
    /// guest sequence space, so an image cannot be overtaken by an older text update or the reverse.
    public func receiveClipboardImage(_ clipboard: ClipboardImageSet, receivedAt: Date = Date()) -> Bool {
        guard clipboard.origin == "guest",
              clipboard.sequence > lastGuestClipboardSequence else {
            return false
        }

        let payload: ClipboardImagePayload
        do {
            payload = try ClipboardImagePayload(message: clipboard)
        } catch {
            VeilLog.agent.notice(
                "Rejected a guest clipboard image: \(error.localizedDescription, privacy: .public)"
            )
            return false
        }

        guard guestClipboardRateLimiter.allows(at: receivedAt) else {
            VeilLog.agent.notice("Rate limited a guest clipboard image.")
            return false
        }

        latestGuestClipboardImage = payload
        lastGuestClipboardSequence = clipboard.sequence
        return true
    }

    /// Accepts a guest file copy once ``ClipboardGuestFiles/plan(_:)`` has checked every path and name. Shares
    /// the guest sequence space and rate limit with text and images. Nothing is read from the share here;
    /// the shell copies the files only if Veil is active and guest file copy is on.
    public func receiveClipboardFiles(_ clipboard: ClipboardFilesSet, receivedAt: Date = Date()) -> Bool {
        guard clipboard.origin == "guest",
              clipboard.sequence > lastGuestClipboardSequence else {
            return false
        }

        let plan: ClipboardGuestFilesPlan
        do {
            plan = try ClipboardGuestFiles.plan(clipboard)
        } catch {
            VeilLog.agent.notice(
                "Rejected a guest clipboard file copy: \(error.localizedDescription, privacy: .public)"
            )
            return false
        }

        guard guestClipboardRateLimiter.allows(at: receivedAt) else {
            VeilLog.agent.notice("Rate limited a guest clipboard file copy.")
            return false
        }

        latestGuestClipboardFiles = plan
        lastGuestClipboardSequence = clipboard.sequence
        return true
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
