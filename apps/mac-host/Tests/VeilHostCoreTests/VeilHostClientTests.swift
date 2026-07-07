import Foundation
import Testing

@testable import VeilHostCore

@Suite("Veil host client")
struct VeilHostClientTests {
    @Test("loads agent health without launching an app")
    func loadsAgentHealthOnly() async throws {
        let transport = RecordingTransport(responses: [
            #"{"type":"agent.health.response","requestId":"req_health","protocolVersion":1,"agentVersion":"0.1.0","os":"windows-arm64","session":{"interactive":true,"user":"veil-user"},"capabilities":{"appList":true,"appLaunch":true,"windowTracking":true,"windowCapture":false,"input":false,"clipboardText":false}}"#
        ])
        let client = VeilHostClient(transport: transport)

        let health = try await client.loadHealth()

        #expect(transport.sentTypes == ["agent.health.request"])
        #expect(transport.expectedReplyCounts == [1])
        #expect(health.agentVersion == "0.1.0")
        #expect(health.os == "windows-arm64")
    }

    @Test("diagnoses connected Windows agent")
    func diagnosesConnectedAgent() async throws {
        let transport = RecordingTransport(responses: [
            #"{"type":"agent.health.response","requestId":"req_health","protocolVersion":1,"agentVersion":"0.1.0","os":"windows-arm64","session":{"interactive":true,"user":"veil-user"},"capabilities":{"appList":true,"appLaunch":true,"windowTracking":true,"windowCapture":true,"input":true,"clipboardText":true}}"#
        ])
        let client = VeilHostClient(transport: transport)

        let diagnostic = await client.diagnoseAgentConnection(endpoint: "ws://127.0.0.1:18444")

        #expect(diagnostic.status == .connected)
        #expect(diagnostic.endpoint == "ws://127.0.0.1:18444")
        #expect(diagnostic.health?.agentVersion == "0.1.0")
        #expect(diagnostic.errorMessage == nil)
        #expect(diagnostic.nextActions.contains("Run veil-host-probe --launch-notepad-frame to verify HWND launch, tracking, and first frame capture."))
        #expect(transport.sentTypes == ["agent.health.request"])
    }

    @Test("diagnoses unavailable Windows agent with recovery actions")
    func diagnosesUnavailableAgentWithRecoveryActions() async throws {
        let transport = FailingTransport(error: DiagnosticTransportError.connectionRefused)
        let client = VeilHostClient(transport: transport)

        let diagnostic = await client.diagnoseAgentConnection(endpoint: "ws://127.0.0.1:18444")

        #expect(diagnostic.status == .unavailable)
        #expect(diagnostic.endpoint == "ws://127.0.0.1:18444")
        #expect(diagnostic.health == nil)
        #expect(diagnostic.errorMessage == "Connection refused.")
        #expect(diagnostic.nextActions.contains("Inside Windows, run Veil Shared\\Veil Guest Agent\\Install Veil Agent.cmd."))
        #expect(diagnostic.nextActions.contains("If macOS can open the forwarded port but health still times out, run Veil Shared\\Veil Guest Agent\\Repair Veil Agent Connectivity.cmd and approve the Windows administrator prompt."))
        #expect(diagnostic.nextActions.contains("If the agent still does not connect, run Veil Shared\\Veil Guest Agent\\Collect Veil Agent Diagnostics.cmd and inspect the desktop ZIP."))
    }

    @Test("diagnoses stalled Windows agent with bounded timeout")
    func diagnosesStalledAgentWithBoundedTimeout() async throws {
        let client = VeilHostClient(transport: HangingTransport(), hostForwardProbe: { _, _ in nil })

        let diagnostic = await client.diagnoseAgentConnection(
            endpoint: "ws://127.0.0.1:18444",
            timeoutNanoseconds: 1_000_000
        )

        #expect(diagnostic.status == .unavailable)
        #expect(diagnostic.errorMessage == "Timed out waiting for Windows agent health.")
        #expect(diagnostic.nextActions.contains("Confirm the Windows 11 Arm VM is running and has reached the desktop."))
    }

    @Test("diagnoses host-forwarded TCP without WebSocket health")
    func diagnosesHostForwardedTCPWithoutWebSocketHealth() async throws {
        let client = VeilHostClient(
            transport: HangingTransport(),
            hostForwardProbe: { endpoint, _ in
                HostForwardProbeResult(
                    endpoint: endpoint,
                    host: "127.0.0.1",
                    port: 18444,
                    status: .tcpOpen,
                    detail: "TCP connection to the host-forwarded endpoint succeeded."
                )
            }
        )

        let diagnostic = await client.diagnoseAgentConnection(
            endpoint: "ws://127.0.0.1:18444",
            timeoutNanoseconds: 1_000_000
        )

        #expect(diagnostic.status == .unavailable)
        #expect(diagnostic.hostForwardProbe?.status == .tcpOpen)
        #expect(diagnostic.nextActions.contains("Mac can open the QEMU hostfwd TCP port, but WebSocket health did not respond; run the Veil connectivity repair command to refresh Windows Firewall rules and restart the agent."))
        #expect(diagnostic.nextActions.contains("If Windows shows a disconnected network icon, attach a driver ISO or retry with an alternate QEMU NIC before relying on hostfwd for app mirroring."))
    }

    @Test("waits for connected Windows guest agent")
    func waitsForConnectedWindowsGuestAgent() async throws {
        let transport = RecordingTransport(responses: [
            #"{"type":"agent.health.response","requestId":"req_health","protocolVersion":1,"agentVersion":"0.1.0","os":"windows-arm64","session":{"interactive":true,"user":"veil-user"},"capabilities":{"appList":true,"appLaunch":true,"windowTracking":true,"windowCapture":true,"input":true,"clipboardText":true}}"#
        ])
        let client = VeilHostClient(transport: transport)

        let report = await client.pollForAgentConnection(
            endpoint: "ws://127.0.0.1:18444",
            timeoutSeconds: 10,
            pollIntervalNanoseconds: 1,
            perAttemptTimeoutNanoseconds: 1_000_000
        )

        #expect(report.kind == "guestAgentWait")
        #expect(report.status == .connected)
        #expect(report.endpoint == "ws://127.0.0.1:18444")
        #expect(report.attempts == 1)
        #expect(report.connectedAt != nil)
        #expect(report.diagnostic.health?.agentVersion == "0.1.0")
        #expect(report.nextActions.contains("Run `veil-vmctl app-runtime-status --json` to inspect app launch readiness."))
        #expect(report.nextActions.contains("Run `veil-vmctl app-window-proof --json --app-id winapp_notepad` to verify HWND launch, tracking, and first frame capture."))
    }

    @Test("wait reports unavailable Windows guest agent with recovery actions")
    func waitReportsUnavailableWindowsGuestAgentWithRecoveryActions() async throws {
        let client = VeilHostClient(transport: FailingTransport(error: DiagnosticTransportError.connectionRefused))

        let report = await client.pollForAgentConnection(
            endpoint: "ws://127.0.0.1:18444",
            timeoutSeconds: 0,
            pollIntervalNanoseconds: 1,
            perAttemptTimeoutNanoseconds: 1_000_000
        )

        #expect(report.kind == "guestAgentWait")
        #expect(report.status == .unavailable)
        #expect(report.waitedSeconds == 0)
        #expect(report.attempts == 1)
        #expect(report.connectedAt == nil)
        #expect(report.diagnostic.errorMessage == "Connection refused.")
        #expect(report.nextActions.contains("Inside Windows, run Veil Shared\\Veil Guest Agent\\Install Veil Agent.cmd."))
    }

    @Test("runs the Notepad launch flow in protocol order")
    func runsNotepadLaunchFlow() async throws {
        let transport = RecordingTransport(responses: [
            #"{"type":"agent.health.response","requestId":"req_health","protocolVersion":1,"agentVersion":"0.1.0","os":"windows-arm64","session":{"interactive":true,"user":"veil-user"},"capabilities":{"appList":true,"appLaunch":true,"windowTracking":true,"windowCapture":false,"input":false,"clipboardText":false}}"#,
            #"{"type":"app.list.response","requestId":"req_apps","apps":[{"id":"winapp_notepad","name":"Notepad","exePath":"C:\\Windows\\System32\\notepad.exe","publisher":"Microsoft","iconId":"icon_notepad"}]}"#,
            #"{"type":"app.launch.response","requestId":"req_launch_notepad","accepted":true,"processId":4912}"#,
            #"{"type":"window.created","windowId":"hwnd:0003029A","processId":4912,"appId":"winapp_notepad","title":"Untitled - Notepad","bounds":{"x":10,"y":10,"width":1280,"height":800},"state":"normal","focused":true}"#
        ])
        let client = VeilHostClient(transport: transport)

        let result = try await client.launchNotepad()

        #expect(transport.sentTypes == [
            "agent.health.request",
            "app.list.request",
            "app.launch.request"
        ])
        #expect(result.health.agentVersion == "0.1.0")
        #expect(result.apps.map(\.id) == ["winapp_notepad"])
        #expect(result.launch.processId == 4912)
        #expect(result.window.windowId == "hwnd:0003029A")
    }

    @Test("launches a selected Windows app id")
    func launchesSelectedWindowsAppId() async throws {
        let transport = RecordingTransport(responses: [
            #"{"type":"agent.health.response","requestId":"req_health","protocolVersion":1,"agentVersion":"0.1.0","os":"windows-arm64","session":{"interactive":true,"user":"veil-user"},"capabilities":{"appList":true,"appLaunch":true,"windowTracking":true,"windowCapture":false,"input":false,"clipboardText":false}}"#,
            #"{"type":"app.list.response","requestId":"req_apps","apps":[{"id":"winapp_calculator","name":"Calculator","exePath":"calc.exe","publisher":"Microsoft","iconId":"icon_calculator"}]}"#,
            #"{"type":"app.launch.response","requestId":"req_launch_winapp_calculator","accepted":true,"processId":5010}"#,
            #"{"type":"window.created","windowId":"hwnd:0003030B","processId":5010,"appId":"winapp_calculator","title":"Calculator","bounds":{"x":10,"y":10,"width":520,"height":720},"state":"normal","focused":true}"#
        ])
        let client = VeilHostClient(transport: transport)

        let result = try await client.launchApp(appId: "winapp_calculator")

        #expect(transport.sentAppIds == ["winapp_calculator"])
        #expect(result.window.appId == "winapp_calculator")
        #expect(result.window.title == "Calculator")
    }

    @Test("opens a dropped file and launches the target app with it")
    func opensADroppedFileAndLaunchesTheTargetAppWithIt() async throws {
        let transport = RecordingTransport(responses: [
            #"{"type":"agent.health.response","requestId":"req_health","protocolVersion":1,"agentVersion":"0.1.0","os":"windows-arm64","session":{"interactive":true,"user":"veil-user"},"capabilities":{"appList":true,"appLaunch":true,"windowTracking":true,"windowCapture":false,"input":false,"clipboardText":false}}"#,
            #"{"type":"app.list.response","requestId":"req_apps","apps":[{"id":"winapp_notepad","name":"Notepad","exePath":"C:\\Windows\\System32\\notepad.exe","publisher":"Microsoft","iconId":"icon_notepad"}]}"#,
            #"{"type":"file.open.response","requestId":"req_open_winapp_notepad","accepted":true,"processId":4931}"#,
            #"{"type":"window.created","windowId":"hwnd:00010500","processId":4931,"appId":"winapp_notepad","title":"notes.txt - Notepad","bounds":{"x":10,"y":10,"width":1280,"height":800},"state":"normal","focused":true}"#
        ])
        let client = VeilHostClient(transport: transport)

        let result = try await client.openFile(appId: "winapp_notepad", fileName: "notes.txt", contentBase64: "aGVsbG8=")

        #expect(transport.sentTypes == [
            "agent.health.request",
            "app.list.request",
            "file.open.request"
        ])
        #expect(transport.sentAppIds == ["winapp_notepad"])
        #expect(result.launch.processId == 4931)
        #expect(result.window.windowId == "hwnd:00010500")
        #expect(result.window.title == "notes.txt - Notepad")
    }

    @Test("surfaces agent errors when opening a dropped file fails")
    func surfacesAgentErrorsWhenOpeningADroppedFileFails() async throws {
        let transport = RecordingTransport(responses: [
            #"{"type":"agent.health.response","requestId":"req_health","protocolVersion":1,"agentVersion":"0.1.0","os":"windows-arm64","session":{"interactive":true,"user":"veil-user"},"capabilities":{"appList":true,"appLaunch":true,"windowTracking":true,"windowCapture":false,"input":false,"clipboardText":false}}"#,
            #"{"type":"app.list.response","requestId":"req_apps","apps":[{"id":"winapp_notepad","name":"Notepad","exePath":"C:\\Windows\\System32\\notepad.exe","publisher":"Microsoft","iconId":"icon_notepad"}]}"#,
            #"{"type":"error","requestId":"req_open_winapp_notepad","code":"invalid_file_name","message":"fileName must be a non-empty file name with no path separators or traversal."}"#
        ])
        let client = VeilHostClient(transport: transport)

        await #expect(throws: VeilHostError.self) {
            _ = try await client.openFile(appId: "winapp_notepad", fileName: "../evil.exe", contentBase64: "aGVsbG8=")
        }
    }

    @Test("surfaces agent launch errors without waiting for a second launch reply")
    func surfacesAgentLaunchErrorsWithoutWaitingForSecondLaunchReply() async throws {
        let transport = RecordingTransport(responses: [
            #"{"type":"agent.health.response","requestId":"req_health","protocolVersion":1,"agentVersion":"0.1.0","os":"windows-arm64","session":{"interactive":true,"user":"veil-user"},"capabilities":{"appList":true,"appLaunch":true,"windowTracking":true,"windowCapture":false,"input":false,"clipboardText":false}}"#,
            #"{"type":"app.list.response","requestId":"req_apps","apps":[{"id":"winapp_notepad","name":"Notepad","exePath":"notepad.exe","publisher":"Microsoft","iconId":"icon_notepad"}]}"#,
            #"{"type":"error","requestId":"req_launch_winapp_notepad","code":"app_launch_failed","message":"notepad.exe started but no top-level window was discovered."}"#
        ])
        let client = VeilHostClient(transport: transport)

        await #expect(throws: VeilHostError.agentError(
            code: "app_launch_failed",
            message: "notepad.exe started but no top-level window was discovered."
        )) {
            try await client.launchApp(appId: "winapp_notepad")
        }

        #expect(transport.expectedReplyCounts == [1, 1, 2])
    }

    @Test("ignores unsolicited frame events mixed into app launch replies")
    func ignoresUnsolicitedFrameEventsMixedIntoAppLaunchReplies() async throws {
        let transport = BatchRecordingTransport(responseBatches: [
            [
                #"{"type":"agent.health.response","requestId":"req_health","protocolVersion":1,"agentVersion":"0.1.0","os":"windows-arm64","session":{"interactive":true,"user":"veil-user"},"capabilities":{"appList":true,"appLaunch":true,"windowTracking":true,"windowCapture":true,"input":true,"clipboardText":true}}"#
            ],
            [
                #"{"type":"app.list.response","requestId":"req_apps","apps":[{"id":"winapp_notepad","name":"Notepad","exePath":"notepad.exe","publisher":"Microsoft","iconId":"icon_notepad"}]}"#
            ],
            [
                WindowFrameEvent.notepadFirstFrameJSON,
                #"{"type":"app.launch.response","requestId":"req_launch_winapp_notepad","accepted":true,"processId":4912}"#,
                #"{"type":"window.created","windowId":"hwnd:0003029A","processId":4912,"appId":"winapp_notepad","title":"Untitled - Notepad","bounds":{"x":10,"y":10,"width":1280,"height":800},"state":"normal","focused":true}"#
            ]
        ])
        let client = VeilHostClient(transport: transport)

        let result = try await client.launchApp(appId: "winapp_notepad")

        #expect(result.launch.processId == 4912)
        #expect(result.window.windowId == "hwnd:0003029A")
        #expect(transport.expectedReplyCounts == [1, 1, 2])
    }

    @Test("proves Windows app window launch with first frame evidence")
    func provesWindowsAppWindowLaunchWithFirstFrameEvidence() async throws {
        let transport = RecordingTransport(responses: [
            #"{"type":"agent.health.response","requestId":"req_health","protocolVersion":1,"agentVersion":"0.1.0","os":"windows-arm64","session":{"interactive":true,"user":"veil-user"},"capabilities":{"appList":true,"appLaunch":true,"windowTracking":true,"windowCapture":true,"input":true,"clipboardText":true}}"#,
            #"{"type":"app.list.response","requestId":"req_apps","apps":[{"id":"winapp_notepad","name":"Notepad","exePath":"C:\\Windows\\System32\\notepad.exe","publisher":"Microsoft","iconId":"icon_notepad"}]}"#,
            #"{"type":"app.launch.response","requestId":"req_launch_winapp_notepad","accepted":true,"processId":4912}"#,
            #"{"type":"window.created","windowId":"hwnd:0003029A","processId":4912,"appId":"winapp_notepad","title":"Untitled - Notepad","bounds":{"x":10,"y":10,"width":1280,"height":800},"state":"normal","focused":true}"#
        ])
        let eventSource = BufferedEventSource(messages: [
            WindowFrameEvent.notepadFirstFrameJSON
        ])
        let client = VeilHostClient(transport: transport)

        let report = try await client.proveAppWindow(
            appId: "winapp_notepad",
            endpoint: "ws://127.0.0.1:18444",
            eventSource: eventSource,
            timeoutNanoseconds: 1_000_000_000
        )

        #expect(report.kind == "windowsAppWindowProof")
        #expect(report.endpoint == "ws://127.0.0.1:18444")
        #expect(report.appId == "winapp_notepad")
        #expect(report.launch.processId == 4912)
        #expect(report.window.windowId == "hwnd:0003029A")
        #expect(report.frame.windowId == "hwnd:0003029A")
        #expect(report.frame.format == "png")
        #expect(report.frame.encodedByteCount > 0)
        #expect(report.nextActions.contains("Run `veil-vmctl app-runtime-status --json` to inspect active mirrored sessions and supported actions."))
        #expect(transport.sentTypes == [
            "agent.health.request",
            "app.list.request",
            "app.launch.request",
            "window.frame.subscribe"
        ])
    }

    @Test("proves Windows app coherence with input and clipboard evidence")
    func provesWindowsAppCoherenceWithInputAndClipboardEvidence() async throws {
        let transport = RecordingTransport(responses: [
            #"{"type":"agent.health.response","requestId":"req_health","protocolVersion":1,"agentVersion":"0.1.0","os":"windows-arm64","session":{"interactive":true,"user":"veil-user"},"capabilities":{"appList":true,"appLaunch":true,"windowTracking":true,"windowCapture":true,"input":true,"clipboardText":true}}"#,
            #"{"type":"app.list.response","requestId":"req_apps","apps":[{"id":"winapp_notepad","name":"Notepad","exePath":"C:\\Windows\\System32\\notepad.exe","publisher":"Microsoft","iconId":"icon_notepad"}]}"#,
            #"{"type":"app.launch.response","requestId":"req_launch_winapp_notepad","accepted":true,"processId":4912}"#,
            #"{"type":"window.created","windowId":"hwnd:0003029A","processId":4912,"appId":"winapp_notepad","title":"Untitled - Notepad","bounds":{"x":10,"y":10,"width":1280,"height":800},"state":"normal","focused":true}"#
        ])
        let eventSource = BufferedEventSource(messages: [
            WindowFrameEvent.notepadFirstFrameJSON,
            WindowFrameEvent.notepadPostInputFrameJSON
        ])
        let client = VeilHostClient(transport: transport)

        let report = try await client.proveCoherenceAppWindow(
            appId: "winapp_notepad",
            endpoint: "ws://127.0.0.1:18444",
            eventSource: eventSource,
            timeoutNanoseconds: 1_000_000_000
        )

        #expect(report.kind == "windowsAppCoherenceProof")
        #expect(report.endpoint == "ws://127.0.0.1:18444")
        #expect(report.window.windowId == "hwnd:0003029A")
        #expect(report.initialFrame.sequence == 1)
        #expect(report.postInputFrame.sequence == 2)
        #expect(report.input.mouseEventsPosted == ["leftDown", "leftUp"])
        #expect(report.input.keyEventsPosted == [
            "keyDown:v",
            "keyUp:v",
            "keyDown:e",
            "keyUp:e",
            "keyDown:i",
            "keyUp:i",
            "keyDown:l",
            "keyUp:l"
        ])
        #expect(report.input.typedTextCharacterCount == 4)
        #expect(report.input.clipboardOrigin == "host")
        #expect(report.input.clipboardSequence == 1)
        #expect(report.input.clipboardTextByteCount > 0)
        #expect(transport.sentTypes == [
            "agent.health.request",
            "app.list.request",
            "app.launch.request",
            "window.frame.subscribe",
            "input.mouse",
            "input.mouse",
            "input.key",
            "input.key",
            "input.key",
            "input.key",
            "input.key",
            "input.key",
            "input.key",
            "input.key",
            "clipboard.text.set"
        ])
        #expect(transport.expectedReplyCounts == [1, 1, 2, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0])
    }

    @Test("proves Windows MVP runtime after guest agent wait")
    func provesWindowsMVPRuntimeAfterGuestAgentWait() async throws {
        let transport = RecordingTransport(responses: [
            #"{"type":"agent.health.response","requestId":"req_health","protocolVersion":1,"agentVersion":"0.1.0","os":"windows-arm64","session":{"interactive":true,"user":"veil-user"},"capabilities":{"appList":true,"appLaunch":true,"windowTracking":true,"windowCapture":true,"input":true,"clipboardText":true}}"#,
            #"{"type":"agent.health.response","requestId":"req_health","protocolVersion":1,"agentVersion":"0.1.0","os":"windows-arm64","session":{"interactive":true,"user":"veil-user"},"capabilities":{"appList":true,"appLaunch":true,"windowTracking":true,"windowCapture":true,"input":true,"clipboardText":true}}"#,
            #"{"type":"app.list.response","requestId":"req_apps","apps":[{"id":"winapp_notepad","name":"Notepad","exePath":"C:\\Windows\\System32\\notepad.exe","publisher":"Microsoft","iconId":"icon_notepad"}]}"#,
            #"{"type":"app.launch.response","requestId":"req_launch_winapp_notepad","accepted":true,"processId":4912}"#,
            #"{"type":"window.created","windowId":"hwnd:0003029A","processId":4912,"appId":"winapp_notepad","title":"Untitled - Notepad","bounds":{"x":10,"y":10,"width":1280,"height":800},"state":"normal","focused":true}"#
        ])
        let eventSource = BufferedEventSource(messages: [
            WindowFrameEvent.notepadFirstFrameJSON,
            WindowFrameEvent.notepadPostInputFrameJSON
        ])
        let client = VeilHostClient(transport: transport)

        let report = try await client.proveMVPAppRuntime(
            appId: "winapp_notepad",
            endpoint: "ws://127.0.0.1:18444",
            eventSource: eventSource,
            waitSeconds: 10,
            proofTimeoutNanoseconds: 1_000_000_000
        )

        #expect(report.kind == "windowsMVPProof")
        #expect(report.status == .proved)
        #expect(report.wait.status == .connected)
        #expect(report.coherence?.kind == "windowsAppCoherenceProof")
        #expect(report.coherence?.postInputFrame.sequence == 2)
        #expect(report.nextActions.contains("Attach the saved MVP proof artifact to release gates and app-runtime bug reports."))
        #expect(transport.sentTypes.first == "agent.health.request")
        #expect(transport.sentTypes.contains("clipboard.text.set"))
    }

    @Test("reports unavailable Windows MVP runtime without launching an app")
    func reportsUnavailableWindowsMVPRuntimeWithoutLaunchingApp() async throws {
        let client = VeilHostClient(transport: FailingTransport(error: DiagnosticTransportError.connectionRefused))

        let report = try await client.proveMVPAppRuntime(
            appId: "winapp_notepad",
            endpoint: "ws://127.0.0.1:18444",
            eventSource: BufferedEventSource(messages: []),
            waitSeconds: 0,
            proofTimeoutNanoseconds: 1_000_000
        )

        #expect(report.kind == "windowsMVPProof")
        #expect(report.status == .unavailable)
        #expect(report.wait.status == .unavailable)
        #expect(report.coherence == nil)
        #expect(report.nextActions.contains("Inside Windows, run Veil Shared\\Veil Guest Agent\\Install Veil Agent.cmd."))
    }

    @Test("fails when Notepad is missing from the app list")
    func failsWhenNotepadIsMissing() async throws {
        let transport = RecordingTransport(responses: [
            #"{"type":"agent.health.response","requestId":"req_health","protocolVersion":1,"agentVersion":"0.1.0","os":"windows-arm64","session":{"interactive":true,"user":"veil-user"},"capabilities":{"appList":true,"appLaunch":true,"windowTracking":true,"windowCapture":false,"input":false,"clipboardText":false}}"#,
            #"{"type":"app.list.response","requestId":"req_apps","apps":[]}"#
        ])
        let client = VeilHostClient(transport: transport)

        await #expect(throws: VeilHostError.self) {
            _ = try await client.launchNotepad()
        }
    }

    @Test("rejects Notepad launch when the HWND event does not match the launched process")
    func rejectsMismatchedNotepadWindowEvent() async throws {
        let transport = RecordingTransport(responses: [
            #"{"type":"agent.health.response","requestId":"req_health","protocolVersion":1,"agentVersion":"0.1.0","os":"windows-arm64","session":{"interactive":true,"user":"veil-user"},"capabilities":{"appList":true,"appLaunch":true,"windowTracking":true,"windowCapture":false,"input":false,"clipboardText":false}}"#,
            #"{"type":"app.list.response","requestId":"req_apps","apps":[{"id":"winapp_notepad","name":"Notepad","exePath":"C:\\Windows\\System32\\notepad.exe","publisher":"Microsoft","iconId":"icon_notepad"}]}"#,
            #"{"type":"app.launch.response","requestId":"req_launch_notepad","accepted":true,"processId":4912}"#,
            #"{"type":"window.created","windowId":"hwnd:0003029A","processId":9001,"appId":"winapp_notepad","title":"Untitled - Notepad","bounds":{"x":10,"y":10,"width":1280,"height":800},"state":"normal","focused":true}"#
        ])
        let client = VeilHostClient(transport: transport)

        await #expect(throws: VeilHostError.appWindowMismatch("winapp_notepad")) {
            _ = try await client.launchNotepad()
        }
    }

    @Test("sends a window close request to the agent")
    func sendsWindowCloseRequest() async throws {
        let transport = RecordingTransport(responses: [
            #"{"type":"window.close.response","requestId":"req_close_notepad","windowId":"hwnd:0003029A","accepted":true}"#
        ])
        let client = VeilHostClient(transport: transport)

        let response = try await client.closeWindow(windowId: "hwnd:0003029A")

        #expect(transport.sentTypes == ["window.close.request"])
        #expect(response.type == .windowCloseResponse)
        #expect(response.requestId == "req_close_notepad")
        #expect(response.windowId == "hwnd:0003029A")
        #expect(response.accepted)
    }

    @Test("sends a window focus request to the agent")
    func sendsWindowFocusRequest() async throws {
        let transport = RecordingTransport(responses: [
            #"{"type":"window.focus.response","requestId":"req_focus_hwnd_0003029A","windowId":"hwnd:0003029A","accepted":true}"#
        ])
        let client = VeilHostClient(transport: transport)

        let response = try await client.focusWindow(windowId: "hwnd:0003029A")

        #expect(transport.sentTypes == ["window.focus.request"])
        #expect(response.type == .windowFocusResponse)
        #expect(response.requestId == "req_focus_hwnd_0003029A")
        #expect(response.windowId == "hwnd:0003029A")
        #expect(response.accepted)
    }

    @Test("sends mouse input without waiting for a reply")
    func sendsMouseInputWithoutReply() async throws {
        let transport = RecordingTransport(responses: [])
        let client = VeilHostClient(transport: transport)

        try await client.sendMouseInput(
            InputMouseEvent(windowId: "hwnd:0003029A", event: "leftDown", x: 240, y: 130)
        )

        #expect(transport.sentTypes == ["input.mouse"])
        #expect(transport.expectedReplyCounts == [0])
    }

    @Test("sends key input without waiting for a reply")
    func sendsKeyInputWithoutReply() async throws {
        let transport = RecordingTransport(responses: [])
        let client = VeilHostClient(transport: transport)

        try await client.sendKeyInput(
            InputKeyEvent(
                windowId: "hwnd:0003029A",
                event: "keyDown",
                key: "c",
                windowsVirtualKey: 67,
                modifiers: ["ctrl"]
            )
        )

        #expect(transport.sentTypes == ["input.key"])
        #expect(transport.expectedReplyCounts == [0])
    }

    @Test("sends host clipboard text without waiting for a reply")
    func sendsHostClipboardTextWithoutReply() async throws {
        let transport = RecordingTransport(responses: [])
        let client = VeilHostClient(transport: transport)

        try await client.sendClipboardText(
            ClipboardTextSet(requestId: "req_clipboard_1", origin: "host", sequence: 1, text: "hello from macOS")
        )

        #expect(transport.sentTypes == ["clipboard.text.set"])
        #expect(transport.expectedReplyCounts == [0])
    }

    @Test("sends frame stream subscribe and unsubscribe without waiting for replies")
    func sendsFrameStreamControlWithoutReply() async throws {
        let transport = RecordingTransport(responses: [])
        let client = VeilHostClient(transport: transport)

        try await client.subscribeWindowFrames(windowId: "hwnd:0003029A")
        try await client.unsubscribeWindowFrames(windowId: "hwnd:0003029A")

        #expect(transport.sentTypes == [
            "window.frame.subscribe",
            "window.frame.unsubscribe"
        ])
        #expect(transport.expectedReplyCounts == [0, 0])
    }
}

private final class RecordingTransport: HostTransport, @unchecked Sendable {
    private var responses: [String]
    private(set) var sentTypes: [String] = []
    private(set) var sentAppIds: [String] = []
    private(set) var expectedReplyCounts: [Int] = []

    init(responses: [String]) {
        self.responses = responses
    }

    func send(_ message: Data, expectedReplies: Int) async throws -> [Data] {
        let object = try JSONSerialization.jsonObject(with: message) as? [String: Any]
        sentTypes.append(object?["type"] as? String ?? "")
        if let appId = object?["appId"] as? String {
            sentAppIds.append(appId)
        }
        expectedReplyCounts.append(expectedReplies)

        let replyStrings = Array(responses.prefix(expectedReplies))
        responses.removeFirst(replyStrings.count)
        return replyStrings.map { Data($0.utf8) }
    }
}

private final class BatchRecordingTransport: HostTransport, @unchecked Sendable {
    private var responseBatches: [[String]]
    private(set) var expectedReplyCounts: [Int] = []

    init(responseBatches: [[String]]) {
        self.responseBatches = responseBatches
    }

    func send(_ message: Data, expectedReplies: Int) async throws -> [Data] {
        expectedReplyCounts.append(expectedReplies)
        guard !responseBatches.isEmpty else {
            return []
        }

        let batch = responseBatches.removeFirst()
        return batch.map { Data($0.utf8) }
    }
}

private enum DiagnosticTransportError: Error, LocalizedError {
    case connectionRefused

    var errorDescription: String? {
        switch self {
        case .connectionRefused:
            "Connection refused."
        }
    }
}

private struct FailingTransport: HostTransport {
    var error: any Error

    func send(_ message: Data, expectedReplies: Int) async throws -> [Data] {
        throw error
    }
}

private struct HangingTransport: HostTransport {
    func send(_ message: Data, expectedReplies: Int) async throws -> [Data] {
        try await Task.sleep(nanoseconds: 5_000_000_000)
        return []
    }
}

private struct BufferedEventSource: HostEventSource {
    var messages: [String]

    func eventMessages() -> AsyncThrowingStream<Data, any Error> {
        AsyncThrowingStream { continuation in
            Task {
                for message in messages {
                    continuation.yield(Data(message.utf8))
                }
                continuation.finish()
            }
        }
    }
}

private extension WindowFrameEvent {
    static var notepadFirstFrameJSON: String {
        #"{"type":"window.frame","windowId":"hwnd:0003029A","frameId":"frame_000001","sequence":1,"format":"png","width":1,"height":1,"scale":1,"encodedData":"iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+/p9sAAAAASUVORK5CYII="}"#
    }

    static var notepadPostInputFrameJSON: String {
        #"{"type":"window.frame","windowId":"hwnd:0003029A","frameId":"frame_000002","sequence":2,"format":"png","width":1,"height":1,"scale":1,"encodedData":"iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+/p9sAAAAASUVORK5CYII="}"#
    }
}
