import Foundation
import Darwin
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers
import Vision
import VeilHostCore

extension VeilVMControl {
    @MainActor
    static func runAppRuntimeAction(
        json: Bool,
        demo: Bool,
        action: VMControlArguments.AppRuntimeAction,
        appId: String?,
        windowId: String?,
        text: String?,
        x: Int?,
        y: Int?,
        waitSeconds: Int
    ) async throws {
        let endpoint = demo
            ? "demo"
            : ProcessInfo.processInfo.environment["VEIL_AGENT_URL"] ?? "ws://127.0.0.1:18444"
        let service = appRuntimeStatusService(demo: demo)
        let model = HostDashboardModel(service: service)
        await model.loadRestoreIntent()
        await model.load()

        var launch: AppLaunchResponse?
        var window: WindowCreatedEvent?
        var focus: WindowFocusResponse?
        var close: WindowCloseResponse?
        var closedWindows: [WindowCloseResponse] = []
        var clipboard: ClipboardTextSet?
        var mouseInputs: [InputMouseEvent] = []
        var keyInputs: [InputKeyEvent] = []
        var typedTextCharacterCount: Int?
        var restoredWindows: [WindowCreatedEvent] = []
        var restoreRequestedAppIds: [String] = []
        var broughtForwardWindowIds: [String] = []
        var restartedFrameWindowIds: [String] = []
        var recoveredFrameWindowIds: [String] = []
        var reopenRequestedWindowIds: [String] = []
        var reopenedWindows: [WindowCreatedEvent] = []
        var proof: AppRuntimeRecommendedProofRun?
        var multiAppProof: WindowsMultiAppProofReport?
        var notificationProof: WindowsNotificationProofReport?
        var displayRecovery: AppRuntimeDisplayRecovery?
        var agentWait: AgentConnectionWaitReport?
        var agentRepair: QEMUGuestAgentInstallAttemptReport?
        var sparsePackagePreparation: QEMUGuestAgentInstallAttemptReport?
        var notificationConsent: AppRuntimeNotificationConsent?
        var foregroundWindowId: String?
        var foregroundWindowTitle: String?
        var quietRuntime: WindowsAppRuntimeQuietPolicyStatus?
        var runtimeStop: VMRuntimeSnapshot?
        var runtimeSuspend: VMRuntimeSnapshot?
        var accepted = false
        var resolvedAppId = appId
        var resolvedWindowId = windowId

        switch action {
        case .launch:
            let launchAppId = appId ?? "winapp_notepad"
            guard !launchAppId.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                throw VMControlError.missingAppId
            }

            let result: WindowsAppLaunchResult?
            if demo {
                result = await model.launchApp(appId: launchAppId)
            } else {
                model.selectedAppId = launchAppId
                await model.launchSelectedApp()
                result = model.lastLaunch?.window.appId == launchAppId ? model.lastLaunch : nil
            }

            launch = result?.launch
            window = result?.window
            resolvedAppId = launchAppId
            resolvedWindowId = result?.window.windowId
            foregroundWindowId = result?.window.windowId
            foregroundWindowTitle = result?.window.title
            accepted = result?.launch.accepted == true
        case .fulfillPending:
            let result = await model.refreshLiveAgentIfNeeded()
            launch = result?.launch
            window = result?.window
            resolvedAppId = result?.window.appId ?? model.pendingLaunchAppId
            resolvedWindowId = result?.window.windowId
            foregroundWindowId = result?.window.windowId
            foregroundWindowTitle = result?.window.title
            accepted = result?.launch.accepted == true
        case .focus:
            guard let focusWindowId = windowId,
                  !focusWindowId.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                throw VMControlError.missingWindowId
            }
            focus = await model.focusMirrorSession(windowId: focusWindowId)
            if focus == nil {
                focus = try await service.focusWindow(windowId: focusWindowId)
            }
            accepted = focus?.accepted == true
            resolvedWindowId = focusWindowId
            foregroundWindowId = accepted ? focusWindowId : nil
            foregroundWindowTitle = model.mirrorSessions.first { $0.id == focusWindowId }?.window.title
        case .close:
            guard let closeWindowId = windowId,
                  !closeWindowId.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                throw VMControlError.missingWindowId
            }
            close = await model.closeMirrorSession(windowId: closeWindowId)
            if close == nil {
                close = try await service.closeWindow(windowId: closeWindowId)
            }
            accepted = close?.accepted == true
            resolvedWindowId = closeWindowId
        case .closeAll:
            closedWindows = await model.closeAllMirrorSessions()
            accepted = !closedWindows.isEmpty && closedWindows.allSatisfy(\.accepted)
        case .restartFrameStream:
            if let restartWindowId = windowId,
               !restartWindowId.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                if await model.restartFrameSubscription(windowId: restartWindowId) {
                    restartedFrameWindowIds = [restartWindowId]
                }
                resolvedWindowId = restartWindowId
            } else {
                restartedFrameWindowIds = await model.restartStaleFrameSubscriptions()
                resolvedWindowId = restartedFrameWindowIds.last
            }
            if let foregroundSession = model.mirrorSessions.last {
                foregroundWindowId = foregroundSession.id
                foregroundWindowTitle = foregroundSession.window.title
            }
            accepted = !restartedFrameWindowIds.isEmpty
        case .recoverWindowCapture:
            if let recoverWindowId = windowId,
               !recoverWindowId.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                if await model.recoverFrameCapture(windowId: recoverWindowId) {
                    recoveredFrameWindowIds = [recoverWindowId]
                }
                resolvedWindowId = recoverWindowId
            } else {
                recoveredFrameWindowIds = await model.recoverEscalatedFrameCaptures()
                resolvedWindowId = recoveredFrameWindowIds.last
            }
            if let foregroundSession = model.mirrorSessions.last {
                foregroundWindowId = foregroundSession.id
                foregroundWindowTitle = foregroundSession.window.title
            }
            accepted = !recoveredFrameWindowIds.isEmpty
        case .reopenWindow:
            let results: [WindowsAppReopenResult]
            if let reopenWindowId = windowId,
               !reopenWindowId.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                if let result = await model.reopenAppWindow(windowId: reopenWindowId) {
                    results = [result]
                } else {
                    results = []
                }
            } else {
                results = await model.reopenEscalatedAppWindows()
            }
            reopenRequestedWindowIds = results.map(\.requestedWindowId)
            reopenedWindows = results.map(\.launch.window)
            if let foregroundWindow = reopenedWindows.last {
                resolvedAppId = foregroundWindow.appId
                resolvedWindowId = foregroundWindow.windowId
                foregroundWindowId = foregroundWindow.windowId
                foregroundWindowTitle = foregroundWindow.title
            } else if let reopenWindowId = windowId {
                resolvedWindowId = reopenWindowId
            }
            accepted = !reopenedWindows.isEmpty
        case .maintainFrameStreams:
            let maintenance = await model.maintainStaleFrameStreams()
            restartedFrameWindowIds = maintenance.restartedFrameWindowIds
            recoveredFrameWindowIds = maintenance.recoveredFrameWindowIds
            reopenRequestedWindowIds = maintenance.reopenedWindows.map(\.requestedWindowId)
            reopenedWindows = maintenance.reopenedWindows.map(\.launch.window)
            if let foregroundWindow = reopenedWindows.last {
                resolvedAppId = foregroundWindow.appId
                resolvedWindowId = foregroundWindow.windowId
                foregroundWindowId = foregroundWindow.windowId
                foregroundWindowTitle = foregroundWindow.title
            } else if let foregroundSession = model.mirrorSessions.last {
                resolvedAppId = foregroundSession.window.appId
                resolvedWindowId = foregroundSession.id
                foregroundWindowId = foregroundSession.id
                foregroundWindowTitle = foregroundSession.window.title
            }
            accepted = maintenance.didPerformMaintenance
        case .restore, .reconnectRestore:
            restoreRequestedAppIds = model.restorableAppIds
            let restored = await model.restoreMirroredWindowsAfterReconnect()
            restoredWindows = restored.map(\.window)
            if let foregroundWindow = restoredWindows.last {
                resolvedWindowId = foregroundWindow.windowId
                foregroundWindowId = foregroundWindow.windowId
                foregroundWindowTitle = foregroundWindow.title
            }
            accepted = !restored.isEmpty
        case .bringForward:
            broughtForwardWindowIds = model.mirrorSessions.map(\.id)
            if let foregroundSession = model.mirrorSessions.last {
                focus = await model.focusMirrorSession(windowId: foregroundSession.id)
                resolvedWindowId = foregroundSession.id
                foregroundWindowId = foregroundSession.id
                foregroundWindowTitle = foregroundSession.window.title
            }
            accepted = !broughtForwardWindowIds.isEmpty
        case .recoverDisplay:
            let runtimeService = LocalVMRuntimeService()
            let beforeSnapshot = try? await runtimeService.loadSnapshot()
            let beforeStatus = model.localRuntimeStatus(snapshot: beforeSnapshot)
            let recoveryCommand = beforeStatus.recommendedRecoveryCommand ?? "veil-vmctl qemu-capture --json"
            var capture: QEMUConsoleCaptureRecord?
            var recoveryError: String?

            if beforeStatus.recommendedRecoveryCommand != nil {
                do {
                    capture = try captureLatestQEMUConsole()
                } catch {
                    recoveryError = String(describing: error)
                }
            } else {
                recoveryError = "The local runtime does not currently recommend display recovery."
            }

            let afterSnapshot = try? await runtimeService.loadSnapshot()
            let afterStatus = model.localRuntimeStatus(snapshot: afterSnapshot)
            displayRecovery = AppRuntimeDisplayRecovery(
                command: recoveryCommand,
                beforePreviewStatus: beforeStatus.consolePreviewStatus,
                afterPreviewStatus: afterStatus.consolePreviewStatus,
                beforeScreenshotPath: beforeSnapshot?.latestConsoleScreenshotPath,
                afterScreenshotPath: afterSnapshot?.latestConsoleScreenshotPath,
                capture: capture,
                error: recoveryError
            )
            accepted = capture != nil && afterStatus.consolePreviewStatus == .fresh
        case .waitAgent:
            agentWait = await guestAgentWaitReport(waitSeconds: waitSeconds)
            accepted = agentWait?.status == .connected
        case .repairAgent:
            let localRuntimeSnapshot = try? await LocalVMRuntimeService().loadSnapshot()
            let beforeStatus = model.runtimeStatusReport(
                localRuntime: model.localRuntimeStatus(snapshot: localRuntimeSnapshot)
            )
            if !demo,
               beforeStatus.launchPlan.recommendedRepairCommand != nil,
               beforeStatus.localRuntime.requiresGuestToolsMediaRebuild != true {
                agentRepair = try await qemuGuestAgentInstallAttemptReport(waitSeconds: waitSeconds)
                if agentRepair?.status == .connected {
                    let result = await model.refreshLiveAgentIfNeeded()
                    launch = result?.launch
                    window = result?.window
                    resolvedAppId = result?.window.appId ?? model.pendingLaunchAppId ?? beforeStatus.pendingLaunchAppId
                    resolvedWindowId = result?.window.windowId
                    foregroundWindowId = result?.window.windowId
                    foregroundWindowTitle = result?.window.title
                    accepted = beforeStatus.pendingLaunch.isQueued ? result?.launch.accepted == true : true
                }
            }
        case .prepareSparsePackage:
            if !demo {
                sparsePackagePreparation = try await qemuSparsePackagePreparationAttemptReport(waitSeconds: waitSeconds)
                accepted = sparsePackagePreparation?.agentWait.diagnostic.health?.capabilities.packageIdentity == true
                if sparsePackagePreparation?.status == .connected {
                    await model.load()
                }
            }
        case .requestNotificationConsent:
            let command = "veil-vmctl app-runtime-action --json --action request-notification-consent"
            if demo {
                notificationConsent = AppRuntimeNotificationConsent(
                    command: command,
                    response: nil,
                    error: "Omit --demo to request Windows notification listener consent from the live guest agent."
                )
            } else if model.health?.capabilities.packageIdentity != true {
                notificationConsent = AppRuntimeNotificationConsent(
                    command: command,
                    response: nil,
                    error: "Package identity is required before Windows notification listener consent can be requested."
                )
            } else {
                do {
                    let url = URL(string: endpoint) ?? URL(string: "ws://127.0.0.1:18444")!
                    let client = VeilHostClient(transport: URLSessionWebSocketTransport(url: url))
                    let response = try await client.requestWindowsNotificationListenerConsent()
                    notificationConsent = AppRuntimeNotificationConsent(
                        command: command,
                        response: response,
                        error: nil
                    )
                    accepted = response.accepted
                    await model.load()
                } catch {
                    notificationConsent = AppRuntimeNotificationConsent(
                        command: command,
                        response: nil,
                        error: String(describing: error)
                    )
                }
            }
        case .quietWhenIdle:
            // Resolved against the live snapshot, matching how the status report below resolves it.
            // Without the snapshot the policy cannot know whether this VM can persist a session, so it
            // would report stop as the only option and disagree with its own status block.
            quietRuntime = model.quietRuntimeStatus(
                localRuntime: model.localRuntimeStatus(
                    snapshot: try? await LocalVMRuntimeService().loadSnapshot()
                )
            )
            accepted = quietRuntime?.canQuietRuntime == true
        case .stopRuntime:
            quietRuntime = model.quietRuntimeStatus(
                localRuntime: model.localRuntimeStatus(
                    snapshot: try? await LocalVMRuntimeService().loadSnapshot()
                )
            )
            if quietRuntime?.canQuietRuntime == true {
                runtimeStop = try await LocalVMRuntimeService().stop()
                accepted = runtimeStop?.state == .stopped
            }
        case .suspendRuntime:
            let suspendService = makeSessionRuntimeService(displayMode: .vncLoopback)
            quietRuntime = model.quietRuntimeStatus(
                localRuntime: model.localRuntimeStatus(
                    snapshot: try? await suspendService.loadSnapshot()
                )
            )
            if quietRuntime?.canQuietRuntime == true,
               quietRuntime?.canSuspendSession == true {
                runtimeSuspend = try await suspendService.suspend()
                accepted = runtimeSuspend?.state == .suspended
            }
        case .clipboard:
            guard let text,
                  !text.isEmpty else {
                throw VMControlError.missingAppRuntimeText
            }
            clipboard = ClipboardTextSet(
                requestId: "req_app_runtime_clipboard",
                origin: "host",
                sequence: model.clipboardSequence + 1,
                text: text
            )
            if model.canSendHostClipboardText,
               let clipboard {
                try await service.sendClipboardText(clipboard)
                accepted = true
            }
        case .typeText:
            guard let inputWindowId = windowId,
                  !inputWindowId.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                throw VMControlError.missingWindowId
            }
            guard let text,
                  !text.isEmpty else {
                throw VMControlError.missingAppRuntimeText
            }
            keyInputs = try VeilHostClient.keyInputs(windowId: inputWindowId, text: text)
            typedTextCharacterCount = text.count
            resolvedWindowId = inputWindowId
            if model.hasLiveAgentConnection,
               model.health?.capabilities.input == true {
                for input in keyInputs {
                    try await service.sendKeyInput(input)
                }
                accepted = true
            }
        case .click:
            guard let inputWindowId = windowId,
                  !inputWindowId.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                throw VMControlError.missingWindowId
            }
            guard let x,
                  let y,
                  x >= 0,
                  y >= 0 else {
                throw VMControlError.missingAppRuntimePointerCoordinate
            }
            mouseInputs = [
                InputMouseEvent(windowId: inputWindowId, event: "leftDown", x: x, y: y),
                InputMouseEvent(windowId: inputWindowId, event: "leftUp", x: x, y: y)
            ]
            resolvedWindowId = inputWindowId
            if model.hasLiveAgentConnection,
               model.health?.capabilities.input == true {
                for input in mouseInputs {
                    try await service.sendMouseInput(input)
                }
                accepted = true
            }
        case .proofRecommended:
            let localRuntimeSnapshot = try? await LocalVMRuntimeService().loadSnapshot()
            let currentStatus = model.runtimeStatusReport(
                localRuntime: model.localRuntimeStatus(snapshot: localRuntimeSnapshot)
            )
            if let proofCommand = currentStatus.proofPlan.recommendedProofCommand,
               let proofKind = currentStatus.proofPlan.recommendedProofKind,
               let proofAppId = currentStatus.proofPlan.selectedAppId {
                proof = try await runRecommendedProof(
                    proofKind: proofKind,
                    command: proofCommand,
                    appId: proofAppId,
                    endpoint: endpoint
                )
                resolvedAppId = proofAppId
                resolvedWindowId = proof?.windowId
                foregroundWindowId = proof?.windowId
                foregroundWindowTitle = proof?.windowTitle
                accepted = proof?.status == .proved
            }
        case .proofMultiApp:
            let localRuntimeSnapshot = try? await LocalVMRuntimeService().loadSnapshot()
            let currentStatus = model.runtimeStatusReport(
                localRuntime: model.localRuntimeStatus(snapshot: localRuntimeSnapshot)
            )
            if currentStatus.proofPlan.recommendedMultiAppProofCommand != nil {
                multiAppProof = try await proveMultipleApps(
                    json: false,
                    appIds: WindowsAppRuntimeProofCoverageDefaults.targetAppIds,
                    waitSeconds: waitSeconds,
                    outputDirectoryPath: nil,
                    requireComplete: false,
                    shouldPrint: false
                )
                accepted = multiAppProof?.coverageHealth == "complete"
            }
        case .proofNotifications:
            let localRuntimeSnapshot = try? await LocalVMRuntimeService().loadSnapshot()
            let currentStatus = model.runtimeStatusReport(
                localRuntime: model.localRuntimeStatus(snapshot: localRuntimeSnapshot)
            )
            if currentStatus.notificationBridge.canReceiveNotifications,
               currentStatus.notificationBridge.recommendedAction == "run-notification-proof" {
                let url = URL(string: endpoint) ?? URL(string: "ws://127.0.0.1:18444")!
                let transport = URLSessionWebSocketTransport(url: url)
                let client = VeilHostClient(transport: transport)
                notificationProof = await client.proveWindowsNotificationBridge(
                    endpoint: endpoint,
                    eventSource: transport,
                    waitSeconds: waitSeconds,
                    notificationTimeoutNanoseconds: UInt64(max(waitSeconds, 1)) * 1_000_000_000
                )
                accepted = notificationProof?.status == .proved
            }
        }

        let localRuntimeSnapshot = try? await LocalVMRuntimeService().loadSnapshot()
        let status = model.runtimeStatusReport(
            localRuntime: model.localRuntimeStatus(snapshot: localRuntimeSnapshot)
        )
        let actionLaunchPlan = action == .launch || action == .fulfillPending || action == .repairAgent ? status.launchPlan : nil
        let report = AppRuntimeActionReport(
            action: action,
            requestedAt: Date(),
            endpoint: endpoint,
            connectionMode: status.connection.mode,
            accepted: accepted,
            appId: resolvedAppId,
            windowId: resolvedWindowId,
            foregroundWindowId: foregroundWindowId,
            foregroundWindowTitle: foregroundWindowTitle,
            pendingLaunchAppId: status.pendingLaunchAppId,
            launchPlan: actionLaunchPlan,
            proofPlan: status.proofPlan,
            launch: launch,
            window: window,
            focus: focus,
            close: close,
            closedWindows: closedWindows,
            clipboard: clipboard,
            mouseInputs: mouseInputs,
            keyInputs: keyInputs,
            typedTextCharacterCount: typedTextCharacterCount,
            restoredWindows: restoredWindows,
            restoreRequestedAppIds: restoreRequestedAppIds,
            broughtForwardWindowIds: broughtForwardWindowIds,
            restartedFrameWindowIds: restartedFrameWindowIds,
            recoveredFrameWindowIds: recoveredFrameWindowIds,
            reopenRequestedWindowIds: reopenRequestedWindowIds,
            reopenedWindows: reopenedWindows,
            proof: proof,
            multiAppProof: multiAppProof,
            notificationProof: notificationProof,
            displayRecovery: displayRecovery,
            agentWait: agentWait,
            agentRepair: agentRepair,
            sparsePackagePreparation: sparsePackagePreparation,
            notificationConsent: notificationConsent,
            quietRuntime: quietRuntime,
            runtimeStop: runtimeStop,
            runtimeSuspend: runtimeSuspend,
            status: status,
            nextActions: nextActions(for: action, accepted: accepted, status: status)
        )

        if json {
            let data = try JSONEncoder.veilDiagnostics.encode(report)
            print(String(decoding: data, as: UTF8.self))
            return
        }

        print("Windows app runtime action: \(report.action.rawValue)")
        print("Accepted: \(report.accepted ? "yes" : "no")")
        print("Endpoint: \(report.endpoint)")
        if let appId = report.appId {
            print("App: \(appId)")
        }
        if let windowId = report.windowId {
            print("Window: \(windowId)")
        }
        if let foregroundWindowId = report.foregroundWindowId {
            print("Foreground window id: \(foregroundWindowId)")
        }
        if let foregroundWindowTitle = report.foregroundWindowTitle {
            print("Foreground window: \(foregroundWindowTitle)")
        }
        if let pendingLaunchAppId = report.pendingLaunchAppId {
            print("Pending launch app: \(pendingLaunchAppId)")
        }
        if let displayRecovery = report.displayRecovery {
            print("Display recovery: \(displayRecovery.afterPreviewStatus?.rawValue ?? "unknown")")
            print("Display recovery command: \(displayRecovery.command)")
            if let beforePreviewStatus = displayRecovery.beforePreviewStatus {
                print("Display recovery before: \(beforePreviewStatus.rawValue)")
            }
            if let capturePath = displayRecovery.capture?.consoleScreenshotPath {
                print("Display recovery capture: \(capturePath)")
            }
            if let error = displayRecovery.error {
                print("Display recovery error: \(error)")
            }
        }
        if let agentWait = report.agentWait {
            print("Agent wait: \(agentWait.status.rawValue)")
            print("Agent wait attempts: \(agentWait.attempts)")
            print("Agent wait seconds: \(agentWait.waitedSeconds)")
            if let hostForwardProbe = agentWait.diagnostic.hostForwardProbe {
                print("Agent host forward: \(hostForwardProbe.status.rawValue)")
            }
            if let errorMessage = agentWait.diagnostic.errorMessage {
                print("Agent wait error: \(errorMessage)")
            }
        }
        if let agentRepair = report.agentRepair {
            print("Agent repair: \(agentRepair.status.rawValue)")
            print("Agent repair attempts: \(agentRepair.agentWait.attempts)")
            print("Agent repair waited seconds: \(agentRepair.agentWait.waitedSeconds)")
            print("Agent repair console: \(agentRepair.postAttemptConsole.visualObservation?.screenshotPath ?? agentRepair.postAttemptConsole.capture?.consoleScreenshotPath ?? "not captured")")
        }
        if let sparsePackagePreparation = report.sparsePackagePreparation {
            print("Sparse package preparation: \(sparsePackagePreparation.status.rawValue)")
            print("Sparse package package identity: \(sparsePackagePreparation.agentWait.diagnostic.health?.capabilities.packageIdentity == true ? "ready" : "needed")")
            print("Sparse package attempts: \(sparsePackagePreparation.agentWait.attempts)")
            print("Sparse package waited seconds: \(sparsePackagePreparation.agentWait.waitedSeconds)")
            print("Sparse package console: \(sparsePackagePreparation.postAttemptConsole.visualObservation?.screenshotPath ?? sparsePackagePreparation.postAttemptConsole.capture?.consoleScreenshotPath ?? "not captured")")
        }
        if let notificationConsent = report.notificationConsent {
            print("Notification consent command: \(notificationConsent.command)")
            if let response = notificationConsent.response {
                print("Notification listener access: \(response.notificationListener.accessStatus)")
                print("Notification listener ready: \(response.notificationListener.canListen ? "yes" : "no")")
                print("Notification next action: \(response.notificationListener.recommendedAction)")
            }
            if let error = notificationConsent.error {
                print("Notification consent error: \(error)")
            }
        }
        if let notificationProof = report.notificationProof {
            print("Notification proof: \(notificationProof.status.rawValue)")
            print("Notification proof waited seconds: \(notificationProof.waitedForNotificationSeconds)")
            if let notification = notificationProof.notification {
                print("Notification proof title: \(notification.title)")
                print("Notification proof id: \(notification.notificationId)")
            }
        }
        if let launchPlan = report.launchPlan {
            print("Launch plan: \(launchPlan.recommendedAction)")
            print("Launch automatic app open: \(launchPlan.willOpenAppAutomatically ? "yes" : "no")")
            print("Launch plan reason: \(launchPlan.reason)")
            if let startCommand = launchPlan.recommendedStartCommand {
                print("Launch start command: \(startCommand)")
            }
            if let waitCommand = launchPlan.recommendedWaitCommand {
                print("Launch wait command: \(waitCommand)")
            }
            if let repairCommand = launchPlan.recommendedRepairCommand {
                print("Launch repair command: \(repairCommand)")
            }
            if let launchCommand = launchPlan.recommendedLaunchCommand {
                print("Launch app command: \(launchCommand)")
            }
        }
        print("Proof plan: \(report.proofPlan.reason)")
        if let proofKind = report.proofPlan.recommendedProofKind {
            print("Proof recommended kind: \(proofKind)")
        }
        if let proofCommand = report.proofPlan.recommendedProofCommand {
            print("Proof recommended command: \(proofCommand)")
        }
        if let proofCommand = report.proofPlan.recommendedAppWindowProofCommand {
            print("Proof app-window command: \(proofCommand)")
        }
        if let proofCommand = report.proofPlan.recommendedCoherenceProofCommand {
            print("Proof coherence command: \(proofCommand)")
        }
        if let proofCommand = report.proofPlan.recommendedMVPProofCommand {
            print("Proof MVP command: \(proofCommand)")
        }
        if let window = report.window {
            print("Window title: \(window.title)")
        }
        if let clipboard = report.clipboard {
            print("Clipboard bytes: \(Data(clipboard.text.utf8).count)")
        }
        if !report.closedWindows.isEmpty {
            print("Closed Windows app windows: \(report.closedWindows.map(\.windowId).joined(separator: ", "))")
        }
        if !report.mouseInputs.isEmpty {
            print("Mouse events: \(report.mouseInputs.count)")
        }
        if !report.keyInputs.isEmpty {
            print("Key events: \(report.keyInputs.count)")
        }
        if !report.broughtForwardWindowIds.isEmpty {
            print("Brought forward windows: \(report.broughtForwardWindowIds.joined(separator: ", "))")
        }
        if !report.restartedFrameWindowIds.isEmpty {
            print("Restarted app screen streams: \(report.restartedFrameWindowIds.joined(separator: ", "))")
        }
        if !report.recoveredFrameWindowIds.isEmpty {
            print("Recovered app screen streams: \(report.recoveredFrameWindowIds.joined(separator: ", "))")
        }
        if !report.reopenRequestedWindowIds.isEmpty {
            print("Reopen requested windows: \(report.reopenRequestedWindowIds.joined(separator: ", "))")
        }
        if !report.reopenedWindows.isEmpty {
            print("Reopened app windows: \(report.reopenedWindows.map(\.windowId).joined(separator: ", "))")
        }
        if !report.restoreRequestedAppIds.isEmpty {
            print("Restore requested apps: \(report.restoreRequestedAppIds.joined(separator: ", "))")
        }
        if let proof = report.proof {
            print("Recommended proof: \(proof.proofKind) \(proof.status.rawValue)")
            print("Proof command: \(proof.command)")
            if let windowId = proof.windowId {
                print("Proof window: \(windowId)")
            }
            if let savedProofPath = proof.savedProofPath {
                print("Proof artifact: \(savedProofPath)")
            }
        }
        if let multiAppProof = report.multiAppProof {
            print("Daily Use app proof: \(multiAppProof.coverageHealth) (\(multiAppProof.provedAppCount)/\(multiAppProof.appIds.count))")
            print("Daily Use app proof artifact: \(multiAppProof.aggregateReportPath)")
        }
        if let runtimeStop = report.runtimeStop {
            print("Runtime stop state: \(runtimeStop.state.rawValue)")
            print("Runtime stop detail: \(runtimeStop.detail)")
        }
        print("Open Windows app windows: \(report.status.mirrorSessions.count)")
        print("Next actions:")
        for action in report.nextActions {
            print("  - \(action)")
        }
    }

    static func runRecommendedProof(
        proofKind: String,
        command: String,
        appId: String,
        endpoint: String
    ) async throws -> AppRuntimeRecommendedProofRun {
        let url = URL(string: endpoint) ?? URL(string: "ws://127.0.0.1:18444")!
        let transport = URLSessionWebSocketTransport(url: url)
        let client = VeilHostClient(transport: transport)

        switch proofKind {
        case "app-window":
            let report = try await client.proveAppWindow(
                appId: appId,
                endpoint: endpoint,
                eventSource: transport
            )
            return AppRuntimeRecommendedProofRun(
                proofKind: proofKind,
                command: command,
                appId: appId,
                status: .proved,
                savedProofPath: report.savedProofPath,
                windowId: report.window.windowId,
                windowTitle: report.window.title,
                frameSequence: report.frame.sequence,
                inputEventCount: nil,
                clipboardTextByteCount: nil,
                nextActions: report.nextActions
            )
        case "coherence":
            let report = try await client.proveCoherenceAppWindow(
                appId: appId,
                endpoint: endpoint,
                eventSource: transport
            )
            return AppRuntimeRecommendedProofRun(
                proofKind: proofKind,
                command: command,
                appId: appId,
                status: .proved,
                savedProofPath: report.savedProofPath,
                windowId: report.window.windowId,
                windowTitle: report.window.title,
                frameSequence: report.postInputFrame.sequence,
                inputEventCount: report.input.mouseEventsPosted.count + report.input.keyEventsPosted.count,
                clipboardTextByteCount: report.input.clipboardTextByteCount,
                nextActions: report.nextActions
            )
        case "mvp":
            let report = try await client.proveMVPAppRuntime(
                appId: appId,
                endpoint: endpoint,
                eventSource: transport
            )
            return AppRuntimeRecommendedProofRun(
                proofKind: proofKind,
                command: command,
                appId: appId,
                status: report.status == .proved ? .proved : .unavailable,
                savedProofPath: report.savedProofPath,
                windowId: report.coherence?.window.windowId,
                windowTitle: report.coherence?.window.title,
                frameSequence: report.coherence?.postInputFrame.sequence,
                inputEventCount: report.coherence.map { $0.input.mouseEventsPosted.count + $0.input.keyEventsPosted.count },
                clipboardTextByteCount: report.coherence?.input.clipboardTextByteCount,
                nextActions: report.nextActions
            )
        default:
            return AppRuntimeRecommendedProofRun(
                proofKind: proofKind,
                command: command,
                appId: appId,
                status: .unavailable,
                savedProofPath: nil,
                windowId: nil,
                windowTitle: nil,
                frameSequence: nil,
                inputEventCount: nil,
                clipboardTextByteCount: nil,
                nextActions: [
                    "Run `veil-vmctl app-runtime-status --json` and check proofPlan.recommendedProofKind before retrying."
                ]
            )
        }
    }

    private static func nextActions(
        for action: VMControlArguments.AppRuntimeAction,
        accepted: Bool,
        status: WindowsAppRuntimeStatusReport
    ) -> [String] {
        if accepted {
            switch action {
            case .launch, .fulfillPending:
                return compactActions([
                    "Open or focus the mirrored macOS app window from the menu bar.",
                    proofNextAction(from: status.proofPlan),
                    "Run `veil-vmctl app-runtime-status --json` to inspect the tracked HWND and available actions."
                ])
            case .focus:
                return compactActions([
                    "Confirm the macOS mirror window is frontmost.",
                    proofNextAction(from: status.proofPlan)
                ])
            case .close:
                return [
                    "Run `veil-vmctl app-runtime-status --json` to confirm the HWND no longer appears.",
                    "If Windows keeps the app open, collect guest-agent diagnostics from the shared folder."
                ]
            case .closeAll:
                return [
                    "Run `veil-vmctl app-runtime-status --json` to confirm no mirrored Windows app windows remain.",
                    "Run `veil-vmctl app-runtime-action --json --action quiet-when-idle` if the runtime is ready to quiet."
                ]
            case .restartFrameStream:
                return compactActions([
                    "Run `veil-vmctl app-runtime-status --json` to confirm frameStreamStatus returns to waitingForFirstFrame or fresh.",
                    proofNextAction(from: status.proofPlan)
                ])
            case .recoverWindowCapture:
                return compactActions([
                    "Run `veil-vmctl app-runtime-status --json` to confirm frameStreamRecoveryEscalated is false.",
                    proofNextAction(from: status.proofPlan),
                    "Run `veil-host-probe --diagnose-agent` if the recovered app screen stalls again."
                ])
            case .reopenWindow:
                return compactActions([
                    "Confirm the reopened Windows app window is visible as a macOS window.",
                    proofNextAction(from: status.proofPlan),
                    "Run `veil-vmctl app-runtime-status --json` to confirm the old HWND is gone and the new one is waiting for frames or fresh."
                ])
            case .maintainFrameStreams:
                return compactActions([
                    "Confirm mirrored Windows app windows are visible as macOS windows.",
                    proofNextAction(from: status.proofPlan),
                    "Run `veil-vmctl app-runtime-status --json` to confirm stale app screens are waiting for frames or fresh."
                ])
            case .restore:
                return compactActions([
                    "Open or focus restored mirrored windows from the menu bar.",
                    proofNextAction(from: status.proofPlan),
                    "Run `veil-vmctl app-runtime-status --json` to inspect restored sessions."
                ])
            case .reconnectRestore:
                return compactActions([
                    "Open or focus reconnected Windows app windows from the menu bar.",
                    proofNextAction(from: status.proofPlan),
                    "Run `veil-vmctl app-runtime-status --json` to inspect restored sessions."
                ])
            case .bringForward:
                return compactActions([
                    "Confirm the mirrored Windows app windows are frontmost on macOS.",
                    proofNextAction(from: status.proofPlan),
                    "Run `veil-vmctl app-runtime-action --json --action focus --window-id ...` if one app window needs explicit guest focus."
                ])
            case .recoverDisplay:
                return compactActions([
                    status.localRuntime.recommendedDisplayCommand.map { "Run `\($0)` to validate the embedded Windows display frame." },
                    status.launchPlan.recommendedRepairCommand.map { "Run `\($0)` to repair the guest agent after display evidence is fresh." },
                    "Run `veil-vmctl app-runtime-status --json` before retrying the queued Windows app launch."
                ])
            case .waitAgent:
                return compactActions([
                    "Run `veil-vmctl app-runtime-status --json` to inspect launch, restore, and proof readiness.",
                    status.launchPlan.recommendedLaunchCommand.map { "Run `\($0)` to continue the pending app launch." },
                    proofNextAction(from: status.proofPlan)
                ])
            case .repairAgent:
                return compactActions([
                    status.pendingLaunch.isQueued
                        ? status.launchPlan.recommendedLaunchCommand.map { "Run `\($0)` to continue the queued Windows app launch." }
                        : nil,
                    "Run `veil-vmctl app-runtime-status --json` to confirm the Windows app connection is live.",
                    proofNextAction(from: status.proofPlan)
                ])
            case .prepareSparsePackage:
                return compactActions([
                    "Run `veil-vmctl app-runtime-status --json` to confirm Daily Use package identity readiness.",
                    proofNextAction(from: status.proofPlan)
                ])
            case .requestNotificationConsent:
                return [
                    "Run `veil-vmctl notification-proof --json --require-proved` after triggering a Windows notification.",
                    "Run `veil-vmctl app-runtime-status --json` to confirm notificationBridge.recommendedAction updates from consent to proof or receiving state."
                ]
            case .quietWhenIdle:
                return [
                    "Run `\(status.quietRuntime.recommendedStopCommand ?? "veil-vmctl app-runtime-action --json --action stop-runtime")` to stop the idle local Windows runtime.",
                    "Use `veil-vmctl qemu-powerdown --json --wait-seconds 30` only as a lower-level recovery command.",
                    "Run `veil-vmctl app-runtime-status --json` before relaunching a Windows app."
                ]
            case .stopRuntime:
                return [
                    "Run `veil-vmctl app-runtime-status --json` before relaunching a Windows app.",
                    "If Windows did not stop cleanly, export diagnostics before using force stop."
                ]
            case .suspendRuntime:
                return [
                    "Run `veil-vmctl vm-session-status --json` to confirm the suspended session is on disk.",
                    "Run `veil-vmctl vm-resume --json`, or open a Windows app in Veil, to continue the same session with its apps still open.",
                    "If suspend keeps failing, use `\(status.quietRuntime.recommendedStopCommand ?? "veil-vmctl app-runtime-action --json --action stop-runtime")` instead; stopping loses open apps but always works."
                ]
            case .clipboard:
                return compactActions([
                    "Use Cmd+V inside the mirrored Windows app window to paste the synced text.",
                    proofNextAction(from: status.proofPlan)
                ])
            case .typeText:
                return [
                    "Confirm the text appears in the focused Windows app.",
                    "Run `veil-vmctl app-runtime-action --json --action clipboard --text \"...\"` to validate clipboard transfer as well."
                ]
            case .click:
                return [
                    "Confirm the clicked control or text area is focused inside the Windows app.",
                    "Run `veil-vmctl app-runtime-action --json --action type-text --window-id ... --text veil` to validate keyboard input after the click."
                ]
            case .proofRecommended:
                return [
                    "Attach the proof artifact or JSON report to the current runtime gate.",
                    "Run `veil-vmctl app-runtime-status --json` to inspect the next available Windows app runtime action."
                ]
            case .proofMultiApp:
                return [
                    "Attach the Daily Use multi-app proof artifact to the current runtime gate.",
                    "Run `veil-vmctl app-runtime-status --json` to confirm proofArtifacts.multiAppProofCoverageHealth is complete."
                ]
            case .proofNotifications:
                return [
                    "Run `veil-vmctl app-runtime-status --json` to confirm notificationBridge.recommendedAction is receiving-windows-notifications.",
                    "Attach the notification proof JSON report to the current Daily Use notification gate."
                ]
            }
        }

        if action == .proofRecommended {
            return compactActions([
                proofNextAction(from: status.proofPlan),
                "Run `veil-vmctl guest-agent-wait --json` if no proof command is available yet."
            ])
        }

        if action == .proofMultiApp {
            return compactActions([
                status.proofPlan.recommendedMultiAppProofCommand.map { "Run `\($0)` to retry the Daily Use app coverage check." },
                "Run `veil-vmctl app-runtime-status --json` and confirm Notepad, Calculator, and Paint are all launchable before retrying."
            ])
        }

        if action == .proofNotifications {
            return [
                "Trigger a Windows toast notification while `proof-notifications` is running.",
                "Run `veil-vmctl app-runtime-action --json --action request-notification-consent` if notification listener access is not ready.",
                "Run `veil-vmctl app-runtime-status --json` and inspect notificationBridge.recommendedAction before retrying."
            ]
        }

        if action == .stopRuntime {
            return [
                "Run `veil-vmctl app-runtime-action --json --action quiet-when-idle` to confirm every mirrored Windows app window is closed.",
                "Run `veil-vmctl app-runtime-status --json` and check quietRuntime.reason before retrying stop-runtime."
            ]
        }

        if action == .suspendRuntime {
            return compactActions([
                "Run `veil-vmctl app-runtime-status --json` and check quietRuntime.quietMode; only a `suspend` mode can suspend this session.",
                status.quietRuntime.canSuspendSession
                    ? "Run `veil-vmctl app-runtime-action --json --action quiet-when-idle` to confirm every mirrored Windows app window is closed."
                    : "This VM cannot persist a session, so stop it instead with `veil-vmctl app-runtime-action --json --action stop-runtime`.",
                "Run `veil-vmctl vm-session-status --json` to see why session persistence is unavailable."
            ])
        }

        if action == .launch || action == .fulfillPending {
            return launchRecoveryActions(from: status)
        }

        if action == .restartFrameStream {
            return [
                "Run `veil-vmctl app-runtime-status --json` and check mirrorSessions[].frameStreamStatus.",
                "Run `veil-host-probe --diagnose-agent` if the app screen stream cannot be restarted."
            ]
        }

        if action == .recoverWindowCapture {
            return [
                "Run `veil-vmctl app-runtime-status --json` and check mirrorSessions[].frameStreamRecoveryEscalated.",
                "Run `veil-host-probe --diagnose-agent` if no escalated app screen recovery is available."
            ]
        }

        if action == .reopenWindow {
            return [
                "Run `veil-vmctl app-runtime-status --json` and check mirrorSessions[].frameStreamReopenEscalated.",
                "Run `veil-host-probe --diagnose-agent` if no app window can be reopened."
            ]
        }

        if action == .maintainFrameStreams {
            return [
                "Run `veil-vmctl app-runtime-status --json` and check mirrorSessions[].frameStreamStatus.",
                "Run `veil-host-probe --diagnose-agent` if paused app screens cannot be maintained."
            ]
        }

        if action == .reconnectRestore {
            return compactActions([
                "Run `\(status.guestAgentDiagnostics.waitCommand)` to wait for the Windows guest agent.",
                "Run `\(status.guestAgentDiagnostics.diagnosticCommand)` if the reconnect restore action still cannot reach the agent.",
                "Run `veil-vmctl app-runtime-status --json` and check restorableAppIds before retrying reconnect-restore."
            ])
        }

        if action == .waitAgent {
            if status.localRuntime.requiresGuestToolsMediaRebuild {
                return guestToolsMediaRebuildActions(from: status.localRuntime)
            }

            return [
                "Run `veil-vmctl app-runtime-action --json --action repair-agent --wait-seconds 120` to send the attached guest-agent repair path.",
                "Run `veil-host-probe --diagnose-agent` to inspect host-forward TCP and WebSocket health.",
                "Run `veil-vmctl app-runtime-status --json` before retrying app launch or reconnect-restore."
            ]
        }

        if action == .repairAgent {
            if status.connection.mode == .demo {
                return [
                    "Omit `--demo` to send the attached guest-agent repair path to the running local Windows VM.",
                    "Run `veil-vmctl app-runtime-status --json` to inspect the real app connection before retrying repair-agent."
                ]
            }

            if status.localRuntime.requiresGuestToolsMediaRebuild {
                return guestToolsMediaRebuildActions(from: status.localRuntime)
            }

            return compactActions([
                status.launchPlan.recommendedRepairCommand.map { "Run `\($0)` to retry the in-app guest-agent repair path." },
                "Run `veil-host-probe --diagnose-agent` to inspect host-forward TCP and WebSocket health.",
                "Run `veil-vmctl app-runtime-status --json` before retrying app launch or reconnect-restore."
            ])
        }

        if action == .recoverDisplay {
            return compactActions([
                status.localRuntime.recommendedRecoveryCommand.map { "Run `\($0)` to refresh the latest QEMU console screenshot." },
                status.localRuntime.recommendedDisplayCommand.map { "Run `\($0)` to check whether the embedded display can deliver a frame." },
                "Run `veil-vmctl qemu-install-status --json` and inspect localRuntime.consolePreviewStatus before retrying app launch."
            ])
        }

        if action == .prepareSparsePackage {
            if status.connection.mode == .demo {
                return [
                    "Omit `--demo` to send the sparse package preparation path to the running local Windows VM.",
                    "Run `veil-vmctl app-runtime-status --json` to inspect the real package identity state."
                ]
            }

            return compactActions([
                status.dailyUseReadiness.recommendedCommand.map { "Run `\($0)` to retry the sparse package preparation path." },
                "Confirm the Windows SDK is installed inside the guest if sparse package packing or signing fails.",
                "Run `veil-vmctl app-runtime-status --json` and inspect dailyUseReadiness.packageIdentityStage, packageIdentityMessage, and packageIdentityEvidencePath before retrying."
            ])
        }

        if action == .requestNotificationConsent {
            if status.connection.mode == .demo {
                return [
                    "Omit `--demo` to request Windows notification listener consent from the live guest agent.",
                    "Run `veil-vmctl app-runtime-status --json` to inspect the real notification listener state."
                ]
            }

            return compactActions([
                status.connection.capabilities?.packageIdentity == true
                    ? nil
                    : "Run `veil-vmctl app-runtime-action --json --action prepare-sparse-package --wait-seconds 120` before requesting notification consent.",
                "Approve Windows notification listener access for Veil Agent if Windows shows the consent prompt.",
                "Run `veil-vmctl app-runtime-status --json` and inspect connection.notificationListener.recommendedAction before retrying."
            ])
        }

        return [
            "Run `veil-vmctl guest-agent-wait --json` to confirm the Windows guest agent is connected.",
            "Run `veil-vmctl app-runtime-status --json` and check the requested app or window id before retrying."
        ]
    }

    private static func proofNextAction(from proofPlan: WindowsAppRuntimeProofPlanStatus) -> String? {
        guard let command = proofPlan.recommendedProofCommand else {
            return nil
        }

        if proofPlan.recommendedProofKind == "mvp" {
            return "Run `\(command)` to verify the full Windows app runtime loop."
        }

        if proofPlan.recommendedProofKind == "coherence" {
            return "Run `\(command)` to verify input and clipboard before MVP release."
        }

        if proofPlan.recommendedProofKind == "app-window" {
            return "Run `\(command)` to verify launch, HWND tracking, and first frame capture."
        }

        return "Run `\(command)` to verify the Windows app runtime proof gate."
    }

    private static func compactActions(_ actions: [String?]) -> [String] {
        actions.compactMap { action in
            guard let action,
                  !action.isEmpty else {
                return nil
            }
            return action
        }
    }

    private static func launchRecoveryActions(from status: WindowsAppRuntimeStatusReport) -> [String] {
        var actions: [String] = []
        let launchPlan = status.launchPlan

        if launchPlan.recommendedAction == "prepare-local-runtime" {
            actions.append("Run `veil-vmctl qemu-install-status --json` and resolve the local Windows runtime blocker before starting Windows.")
            return actions
        }

        if launchPlan.recommendedAction == "rebuild-guest-tools-media-before-launch"
            || status.localRuntime.requiresGuestToolsMediaRebuild {
            return guestToolsMediaRebuildActions(from: status.localRuntime)
        }

        if let startCommand = launchPlan.recommendedStartCommand {
            actions.append("Run `\(startCommand)` to start the local Windows runtime for the selected app.")
        }

        if let waitCommand = launchPlan.recommendedWaitCommand {
            actions.append("Run `\(waitCommand)` to wait for the Windows guest agent.")
        }

        if let repairCommand = launchPlan.recommendedRepairCommand {
            actions.append("Run `\(repairCommand)` to repair or start the Windows guest agent from attached media.")
        }

        if let launchCommand = launchPlan.recommendedLaunchCommand {
            actions.append("Run `\(launchCommand)` after the guest agent connects.")
        }

        if actions.isEmpty {
            actions.append("Run `veil-vmctl app-runtime-status --json` and check the selected app before retrying.")
        }

        return actions
    }

    private static func guestToolsMediaRebuildActions(
        from localRuntime: WindowsAppRuntimeLocalRuntimeStatus
    ) -> [String] {
        compactActions([
            localRuntime.recommendedPowerDownCommand.map {
                "Run `\($0)` to stop Windows before rebuilding the attached guest tools media."
            },
            localRuntime.recommendedMediaRebuildCommand.map {
                "Run `\($0)` after Windows stops so the next launch attaches a current VeilAutoInstall.iso."
            },
            "Run `veil-vmctl app-runtime-status --json` after rebuilding media, then start Windows and retry the app connection."
        ])
    }
}
