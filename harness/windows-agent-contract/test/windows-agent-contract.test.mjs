import assert from "node:assert/strict";
import { readFile } from "node:fs/promises";
import { resolve } from "node:path";
import test from "node:test";

import {
  MessageType,
  validateNotepadAcceptance,
  validateWindowFrame
} from "../../../packages/protocol/src/messages.mjs";

const repoRoot = resolve(import.meta.dirname, "../../..");
const agentRoot = resolve(repoRoot, "apps/windows-agent");

test("windows agent is scaffolded as a .NET 8 project", async () => {
  const project = await readFile(resolve(agentRoot, "src/VeilAgent/VeilAgent.csproj"), "utf8");

  assert.match(project, /<TargetFramework>net8\.0-windows<\/TargetFramework>/);
  assert.doesNotMatch(project, /<UseWindowsForms>true<\/UseWindowsForms>/);
  assert.match(project, /<RootNamespace>Veil\.Agent<\/RootNamespace>/);
});

test("windows agent enforces one process per forwarded port", async () => {
  const program = await readFile(resolve(agentRoot, "src/VeilAgent/Program.cs"), "utf8");
  const guard = await readFile(resolve(agentRoot, "src/VeilAgent/SingleInstanceGuard.cs"), "utf8");

  assert.match(program, /SingleInstanceGuard\.TryAcquire\(endpoint\)/);
  assert.match(program, /if\s*\(!instanceGuard\.HasOwnership\)/);
  assert.match(program, /already running for/);
  assert.match(guard, /new Mutex\(initiallyOwned:\s*false,\s*name:\s*mutexName\)/);
  assert.match(guard, /Local\\VeilAgent-\{endpoint\.Port\}/);
  assert.match(guard, /mutex\.WaitOne\(TimeSpan\.Zero\)/);
  assert.match(guard, /AbandonedMutexException/);
  assert.match(guard, /ReleaseMutex\(\)/);
});

test("windows agent is wired to real HWND capture by default", async () => {
  const program = await readFile(resolve(agentRoot, "src/VeilAgent/Program.cs"), "utf8");
  const capture = await readFile(resolve(agentRoot, "src/VeilAgent/GdiWindowFrameCapture.cs"), "utf8");

  assert.match(program, /new GdiWindowFrameCapture\(\)/);
  assert.match(program, /new WindowFrameStreamer\(/);
  assert.doesNotMatch(program, /new BootstrapPngFrameCapture\(\)/);
  assert.match(capture, /Task\.Run/);
  assert.match(capture, /PrintWindow/);
  assert.match(capture, /GetWindowRect/);
  assert.match(capture, /ImageFormat\.Png/);
});

test("windows agent streams continuing window frames after launch", async () => {
  const session = await readFile(resolve(agentRoot, "src/VeilAgent/AgentSession.cs"), "utf8");
  const server = await readFile(resolve(agentRoot, "src/VeilAgent/WebSocketAgentServer.cs"), "utf8");
  const streamer = await readFile(resolve(agentRoot, "src/VeilAgent/WindowFrameStreamer.cs"), "utf8");
  const captureInterface = await readFile(resolve(agentRoot, "src/VeilAgent/IWindowFrameCapture.cs"), "utf8");

  assert.match(captureInterface, /CaptureFrameAsync\([^)]*int sequence/);
  assert.match(session, /StreamWindow:\s*launched/);
  assert.match(session, /NextFrameSequence:\s*2/);
  assert.match(session, /CaptureInitialFrameWithFallbackAsync/);
  assert.match(session, /BootstrapPngFrameCapture/);
  assert.match(session, /WaitAsync\(InitialFrameCaptureTimeout/);
  assert.match(session, /SerializeFrame\(WindowFrame frame\)/);
  assert.match(server, /StartFrameStream/);
  assert.match(server, /WindowFrameStreamer/);
  assert.match(server, /SerializeFrame\(frame\)/);
  assert.match(streamer, /PeriodicTimer/);
  assert.match(streamer, /firstSequence/);
  assert.match(streamer, /CaptureFrameWithFallbackAsync/);
  assert.match(streamer, /WaitAsync\(CaptureTimeout/);
  assert.match(streamer, /BootstrapPngFrameCapture/);
});

test("windows agent listens without HttpListener URL ACL requirements", async () => {
  const endpoint = await readFile(resolve(agentRoot, "src/VeilAgent/AgentEndpoint.cs"), "utf8");
  const server = await readFile(resolve(agentRoot, "src/VeilAgent/WebSocketAgentServer.cs"), "utf8");

  assert.match(endpoint, /VEIL_AGENT_HOST"\)\s*\?\?\s*"0\.0\.0\.0"/);
  assert.match(endpoint, /IPAddress\.Any/);
  assert.match(server, /TcpListener\(endpoint\.ListenAddress,\s*endpoint\.Port\)/);
  assert.match(server, /AcceptTcpClientAsync\(cancellationToken\)/);
  assert.match(server, /Sec-WebSocket-Accept/);
  assert.match(server, /WebSocket\.CreateFromStream/);
  assert.doesNotMatch(server, /HttpListener/);
});

test("windows agent supports host controlled frame stream subscribe and unsubscribe", async () => {
  const messageTypes = await readFile(resolve(agentRoot, "src/VeilAgent/MessageTypes.cs"), "utf8");
  const session = await readFile(resolve(agentRoot, "src/VeilAgent/AgentSession.cs"), "utf8");
  const server = await readFile(resolve(agentRoot, "src/VeilAgent/WebSocketAgentServer.cs"), "utf8");

  assert.match(messageTypes, /WindowFrameSubscribe\s*=\s*"window\.frame\.subscribe"/);
  assert.match(messageTypes, /WindowFrameUnsubscribe\s*=\s*"window\.frame\.unsubscribe"/);
  assert.match(session, /HandleWindowFrameSubscribeAsync/);
  assert.match(session, /HandleWindowFrameUnsubscribeAsync/);
  assert.match(session, /trackedWindowsById/);
  assert.match(server, /StopFrameStream/);
  assert.match(server, /StopStreamWindowId/);
});

test("windows agent accepts host window close requests", async () => {
  const messageTypes = await readFile(resolve(agentRoot, "src/VeilAgent/MessageTypes.cs"), "utf8");
  const desktopInterface = await readFile(resolve(agentRoot, "src/VeilAgent/IWindowsDesktop.cs"), "utf8");
  const desktop = await readFile(resolve(agentRoot, "src/VeilAgent/WindowsDesktop.cs"), "utf8");
  const session = await readFile(resolve(agentRoot, "src/VeilAgent/AgentSession.cs"), "utf8");

  assert.match(messageTypes, /WindowCloseRequest\s*=\s*"window\.close\.request"/);
  assert.match(messageTypes, /WindowCloseResponse\s*=\s*"window\.close\.response"/);
  assert.match(desktopInterface, /CloseWindowAsync\(string windowId,\s*CancellationToken cancellationToken\)/);
  assert.match(desktop, /WM_CLOSE/);
  assert.match(desktop, /PostMessage/);
  assert.match(session, /MessageTypes\.WindowCloseRequest/);
  assert.match(session, /HandleWindowCloseAsync/);
  assert.match(session, /TryGetTrackedWindow\(windowId,\s*out _\)/);
  assert.match(session, /MessageTypes\.WindowCloseResponse/);
});

test("windows agent accepts host window focus requests", async () => {
  const messageTypes = await readFile(resolve(agentRoot, "src/VeilAgent/MessageTypes.cs"), "utf8");
  const desktopInterface = await readFile(resolve(agentRoot, "src/VeilAgent/IWindowsDesktop.cs"), "utf8");
  const desktop = await readFile(resolve(agentRoot, "src/VeilAgent/WindowsDesktop.cs"), "utf8");
  const session = await readFile(resolve(agentRoot, "src/VeilAgent/AgentSession.cs"), "utf8");

  assert.match(messageTypes, /WindowFocusRequest\s*=\s*"window\.focus\.request"/);
  assert.match(messageTypes, /WindowFocusResponse\s*=\s*"window\.focus\.response"/);
  assert.match(desktopInterface, /FocusWindowAsync\(string windowId,\s*CancellationToken cancellationToken\)/);
  assert.match(desktop, /FocusWindowAsync/);
  assert.match(desktop, /EnsureWindowReadyForInput\(hwnd\)/);
  assert.match(session, /MessageTypes\.WindowFocusRequest/);
  assert.match(session, /HandleWindowFocusAsync/);
  assert.match(session, /TryGetTrackedWindow\(windowId,\s*out _\)/);
  assert.match(session, /MessageTypes\.WindowFocusResponse/);
});

test("windows agent accepts host mouse input events", async () => {
  const messageTypes = await readFile(resolve(agentRoot, "src/VeilAgent/MessageTypes.cs"), "utf8");
  const desktopInterface = await readFile(resolve(agentRoot, "src/VeilAgent/IWindowsDesktop.cs"), "utf8");
  const desktop = await readFile(resolve(agentRoot, "src/VeilAgent/WindowsDesktop.cs"), "utf8");
  const models = await readFile(resolve(agentRoot, "src/VeilAgent/WindowModels.cs"), "utf8");
  const session = await readFile(resolve(agentRoot, "src/VeilAgent/AgentSession.cs"), "utf8");

  assert.match(messageTypes, /InputMouse\s*=\s*"input\.mouse"/);
  assert.match(models, /WindowMouseInput/);
  assert.match(desktopInterface, /SendMouseInputAsync\(WindowMouseInput input,\s*CancellationToken cancellationToken\)/);
  assert.match(desktop, /WM_LBUTTONDOWN/);
  assert.match(desktop, /WM_LBUTTONUP/);
  assert.match(desktop, /WM_MOUSEMOVE/);
  assert.match(desktop, /PostMessage/);
  assert.match(session, /MessageTypes\.InputMouse/);
  assert.match(session, /HandleMouseInputAsync/);
  assert.match(session, /window_not_tracked/);
  assert.match(session, /\["input"\]\s*=\s*true/);
});

test("windows agent accepts host key input events", async () => {
  const messageTypes = await readFile(resolve(agentRoot, "src/VeilAgent/MessageTypes.cs"), "utf8");
  const desktopInterface = await readFile(resolve(agentRoot, "src/VeilAgent/IWindowsDesktop.cs"), "utf8");
  const desktop = await readFile(resolve(agentRoot, "src/VeilAgent/WindowsDesktop.cs"), "utf8");
  const models = await readFile(resolve(agentRoot, "src/VeilAgent/WindowModels.cs"), "utf8");
  const session = await readFile(resolve(agentRoot, "src/VeilAgent/AgentSession.cs"), "utf8");

  assert.match(messageTypes, /InputKey\s*=\s*"input\.key"/);
  assert.match(models, /WindowKeyInput/);
  assert.match(desktopInterface, /SendKeyInputAsync\(WindowKeyInput input,\s*CancellationToken cancellationToken\)/);
  assert.match(desktop, /WM_KEYDOWN/);
  assert.match(desktop, /WM_KEYUP/);
  assert.match(desktop, /VK_CONTROL/);
  assert.match(desktop, /PostMessage/);
  assert.match(session, /MessageTypes\.InputKey/);
  assert.match(session, /HandleKeyInputAsync/);
  assert.match(session, /window_not_tracked/);
});

test("windows agent foregrounds the HWND before forwarding host input", async () => {
  const desktop = await readFile(resolve(agentRoot, "src/VeilAgent/WindowsDesktop.cs"), "utf8");

  assert.match(desktop, /EnsureWindowReadyForInput\(hwnd\)/);
  assert.match(desktop, /SetForegroundWindow/);
  assert.match(desktop, /SetFocus/);
  assert.match(desktop, /ShowWindow/);
});

test("windows agent accepts host clipboard text updates", async () => {
  const messageTypes = await readFile(resolve(agentRoot, "src/VeilAgent/MessageTypes.cs"), "utf8");
  const desktopInterface = await readFile(resolve(agentRoot, "src/VeilAgent/IWindowsDesktop.cs"), "utf8");
  const desktop = await readFile(resolve(agentRoot, "src/VeilAgent/WindowsDesktop.cs"), "utf8");
  const session = await readFile(resolve(agentRoot, "src/VeilAgent/AgentSession.cs"), "utf8");

  assert.match(messageTypes, /ClipboardTextSet\s*=\s*"clipboard\.text\.set"/);
  assert.match(desktopInterface, /SetClipboardTextAsync\(string text,\s*CancellationToken cancellationToken\)/);
  assert.match(desktop, /SetClipboardUnicodeText/);
  assert.match(desktop, /OpenClipboard/);
  assert.match(desktop, /SetClipboardData/);
  assert.match(session, /MessageTypes\.ClipboardTextSet/);
  assert.match(session, /HandleClipboardTextSetAsync/);
  assert.match(session, /\["clipboardText"\]\s*=\s*true/);
});

test("windows agent broadcasts guest clipboard text changes without host echo loops", async () => {
  const program = await readFile(resolve(agentRoot, "src/VeilAgent/Program.cs"), "utf8");
  const server = await readFile(resolve(agentRoot, "src/VeilAgent/WebSocketAgentServer.cs"), "utf8");
  const desktopInterface = await readFile(resolve(agentRoot, "src/VeilAgent/IWindowsDesktop.cs"), "utf8");
  const desktop = await readFile(resolve(agentRoot, "src/VeilAgent/WindowsDesktop.cs"), "utf8");

  assert.match(program, /new ClipboardTextStreamer\(/);
  assert.match(server, /ClipboardTextStreamer/);
  assert.match(server, /StartClipboardStream/);
  assert.match(desktopInterface, /GetClipboardTextAsync\(CancellationToken cancellationToken\)/);
  assert.match(desktop, /GetClipboardUnicodeText/);
  assert.match(desktop, /GetClipboardData/);
  assert.match(desktop, /lastHostClipboardText/);
  assert.match(desktop, /lastHostClipboardSequence/);
});

test("windows agent exposes an inbox app catalog for native-style Mac windows", async () => {
  const session = await readFile(resolve(agentRoot, "src/VeilAgent/AgentSession.cs"), "utf8");
  const desktopInterface = await readFile(resolve(agentRoot, "src/VeilAgent/IWindowsDesktop.cs"), "utf8");
  const desktop = await readFile(resolve(agentRoot, "src/VeilAgent/WindowsDesktop.cs"), "utf8");
  const models = await readFile(resolve(agentRoot, "src/VeilAgent/WindowModels.cs"), "utf8");

  assert.match(models, /WindowsAppDescriptor/);
  assert.match(desktopInterface, /LaunchAppAsync\(WindowsAppDescriptor app,\s*CancellationToken cancellationToken\)/);
  assert.match(desktop, /LaunchAppAsync\(WindowsAppDescriptor app,\s*CancellationToken cancellationToken\)/);
  assert.match(session, /AppCatalog/);
  assert.match(session, /winapp_notepad/);
  assert.match(session, /winapp_calculator/);
  assert.match(session, /winapp_paint/);
  assert.match(session, /desktop\.LaunchAppAsync\(app,\s*cancellationToken\)/);
  assert.match(session, /app_launch_failed/);
  assert.match(session, /handler_failed/);
  assert.match(session, /WindowCreatedEvent\(app,\s*launched\)/);
  assert.match(desktop, /SnapshotAppWindowHandles\(app\)/);
  assert.match(desktop, /DoesProcessMatchApp\(windowProcessId,\s*app\)/);
  assert.match(desktop, /\.Append\(app\.Executable\)/);
  assert.match(desktop, /\.Select\(Path\.GetFileNameWithoutExtension\)/);
  assert.match(desktop, /OrderByDescending\(candidate\s*=>\s*candidate\.IsNewWindow\)/);
  assert.match(desktop, /TryFindTopLevelWindow\(app,\s*process\.Id,\s*existingWindowHandles,\s*out var launched\)/);
  assert.match(desktop, /EnumWindows/);
  assert.match(desktop, /GetWindowThreadProcessId/);
  assert.match(desktop, /GetWindowText/);
  assert.match(desktop, /GetWindowRect/);
});

test("windows agent sample launch flow emits Notepad window and first frame", async () => {
  const transcript = JSON.parse(
    await readFile(resolve(agentRoot, "fixtures/notepad-launch-with-frame.json"), "utf8")
  );

  assert.equal(transcript.scenario, "notepad-launch-with-frame");
  assert.equal(transcript.messages.length, 3);

  const [launch, window, frame] = transcript.messages;
  assert.equal(launch.type, MessageType.AppLaunchResponse);
  assert.equal(window.type, MessageType.WindowCreated);
  assert.equal(frame.type, MessageType.WindowFrame);

  assert.deepEqual(validateNotepadAcceptance(launch, window), {
    appId: "winapp_notepad",
    processId: launch.processId,
    windowId: window.windowId,
    title: window.title
  });

  validateWindowFrame(frame);
  assert.equal(frame.windowId, window.windowId);
  assert.equal(frame.format, "png");
});

test("windows agent includes user-logon install and uninstall scripts", async () => {
  const install = await readFile(resolve(agentRoot, "scripts/Install-VeilAgent.ps1"), "utf8");
  const uninstall = await readFile(resolve(agentRoot, "scripts/Uninstall-VeilAgent.ps1"), "utf8");
  const start = await readFile(resolve(agentRoot, "scripts/Start-VeilAgent.ps1"), "utf8");
  const diagnostics = await readFile(resolve(agentRoot, "scripts/Collect-VeilAgentDiagnostics.ps1"), "utf8");
  const repair = await readFile(resolve(agentRoot, "scripts/Repair-VeilAgentConnectivity.ps1"), "utf8");
  const bootstrap = await readFile(resolve(agentRoot, "scripts/Bootstrap-VeilAgentFromMedia.ps1"), "utf8");
  const publish = await readFile(resolve(agentRoot, "scripts/Publish-VeilAgentBundle.ps1"), "utf8");
  const publishShell = await readFile(resolve(agentRoot, "scripts/publish-veil-agent-bundle.sh"), "utf8");

  assert.match(install, /Register-ScheduledTask/);
  assert.match(install, /New-ScheduledTaskTrigger\s+-AtLogOn/);
  assert.match(install, /VeilAgent/);
  assert.match(install, /dotnet publish/);
  assert.match(install, /BundledAgentExe/);
  assert.match(install, /Using packaged VeilAgent app bundle/);
  assert.match(install, /VEIL_AGENT_PORT/);
  assert.match(install, /Start-Transcript/);
  assert.match(install, /install\.log/);
  assert.match(install, /Collect-VeilAgentDiagnostics\.ps1/);
  assert.match(install, /Repair-VeilAgentConnectivity\.ps1/);
  assert.match(install, /Get-Process\s+-Name\s+"VeilAgent"/);
  assert.match(install, /Stop-Process\s+-Force/);
  assert.match(install, /netsh\s+advfirewall\s+firewall\s+add\s+rule/);
  assert.match(install, /Windows Firewall inbound rule/);
  assert.match(start, /VeilAgent\.exe/);
  assert.match(start, /0\.0\.0\.0/);
  assert.match(start, /127\.0\.0\.1/);
  assert.match(start, /start\.log/);
  assert.match(start, /agent\.stdout\.log/);
  assert.match(start, /agent\.stderr\.log/);
  assert.match(start, /Test-VeilAgentPort/);
  assert.match(start, /Test-VeilAgentHealth/);
  assert.match(start, /Get-VeilGuestIPv4Addresses/);
  assert.match(start, /Test-VeilAgentGuestAddressHealth/);
  assert.match(start, /ClientWebSocket/);
  assert.match(start, /agent\.health\.request/);
  assert.match(start, /agent\.health\.response/);
  assert.match(start, /Guest IPv4 addresses visible to Windows/);
  assert.match(start, /Get-Process\s+-Name\s+"VeilAgent"/);
  assert.match(start, /VeilAgent is already running/);
  assert.match(start, /loopback plus guest IPv4 agent\.health\.response did not both succeed/);
  assert.match(start, /RedirectStandardOutput\s+\$StdOutLogPath/);
  assert.match(start, /RedirectStandardError\s+\$StdErrLogPath/);
  assert.match(diagnostics, /Compress-Archive/);
  assert.match(diagnostics, /veil-agent-diagnostics-\$Timestamp\.zip/);
  assert.match(diagnostics, /Get-ScheduledTask\s+-TaskName\s+\$TaskName/);
  assert.match(diagnostics, /bootstrap\.log|install\.log|start\.log|LogRoot/);
  assert.match(repair, /Start-Process[\s\S]+-Verb\s+RunAs/);
  assert.match(repair, /VeilAgent WebSocket Port/);
  assert.match(repair, /localport=\$Port/);
  assert.match(repair, /Repair-VeilAgentConnectivity/);
  assert.match(repair, /Start-VeilAgent\.ps1/);
  assert.match(repair, /StatusPath/);
  assert.match(repair, /repair-status\.json/);
  assert.match(repair, /Wait-VeilRepairStatus/);
  assert.match(repair, /Sync-VeilInstalledSupportScripts/);
  assert.match(repair, /Copy-Item[\s\S]+-Destination\s+\$InstalledScriptsRoot/);
  assert.match(repair, /"Start-VeilAgent\.ps1"/);
  assert.match(repair, /"Collect-VeilAgentDiagnostics\.ps1"/);
  assert.match(repair, /Sync-VeilInstalledAppBundle/);
  assert.match(repair, /function\s+Find-VeilSharedAgentRoot/);
  assert.match(repair, /\$BundledAppRoot\s*=\s*Join-Path\s+\(Find-VeilSharedAgentRoot\)\s+"app"/);
  assert.match(repair, /Resolved bundle source is the installed app folder itself/);
  assert.match(repair, /Resolved support script source is the installed scripts folder itself/);
  assert.match(repair, /Refreshed installed VeilAgent app bundle/);
  assert.match(repair, /Install-VeilVirtIONetworkDriver/);
  assert.match(repair, /NetKVM\\w11\\ARM64/);
  assert.match(repair, /pnputil\s+\/add-driver/);
  assert.match(repair, /networkDriverInstalled/);
  assert.match(repair, /guestAgentHealthSucceeded/);
  assert.match(bootstrap, /Bootstrap-VeilAgentFromMedia/);
  assert.match(bootstrap, /Install Veil Agent\.cmd/);
  assert.match(bootstrap, /bootstrap\.log/);
  assert.match(uninstall, /Unregister-ScheduledTask/);
  assert.match(uninstall, /VeilAgent/);
  assert.match(publish, /--runtime\s+\$Runtime/);
  assert.match(publish, /--self-contained:\$SelfContained/);
  assert.match(publish, /EnableWindowsTargeting=true/);
  assert.match(publish, /VeilAgent\.exe/);
  assert.match(publishShell, /--runtime "\$runtime"/);
  assert.match(publishShell, /--self-contained "\$self_contained"/);
  assert.match(publishShell, /EnableWindowsTargeting=true/);
  assert.match(publishShell, /VeilAgent\.exe/);
});

test("windows agent installs logon task against the local installed scripts", async () => {
  const install = await readFile(resolve(agentRoot, "scripts/Install-VeilAgent.ps1"), "utf8");

  assert.match(install, /\$InstalledScriptsRoot\s*=\s*Join-Path\s+\$InstallRoot\s+"scripts"/);
  assert.match(install, /Copy-Item[\s\S]+Start-VeilAgent\.ps1[\s\S]+-Destination\s+\$InstalledScriptsRoot/);
  assert.match(install, /Copy-Item[\s\S]+Collect-VeilAgentDiagnostics\.ps1[\s\S]+-Destination\s+\$InstalledScriptsRoot/);
  assert.match(install, /\$StartScript\s*=\s*Join-Path\s+\$InstalledScriptsRoot\s+"Start-VeilAgent\.ps1"/);
  assert.doesNotMatch(install, /\$StartScript\s*=\s*Join-Path\s+\$AgentRoot\s+"scripts\\Start-VeilAgent\.ps1"/);
});

test("windows agent installer starts the installed agent immediately by default", async () => {
  const install = await readFile(resolve(agentRoot, "scripts/Install-VeilAgent.ps1"), "utf8");

  assert.match(install, /\[switch\]\$NoStart/);
  assert.match(install, /if\s*\(-not\s+\$NoStart\)\s*{/);
  assert.match(install, /&\s+\$StartScript\s+-InstallRoot\s+\$InstallRoot\s+-Port\s+\$Port/);
  assert.match(install, /Write-Host "VeilAgent started inside Windows on 0\.0\.0\.0:\$Port\. The macOS host connects through QEMU at ws:\/\/127\.0\.0\.1:\$Port\/\."/);
});
