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
  assert.match(project, /<UseWindowsForms>true<\/UseWindowsForms>/);
  assert.match(project, /<RootNamespace>Veil\.Agent<\/RootNamespace>/);
});

test("windows agent is wired to real HWND capture by default", async () => {
  const program = await readFile(resolve(agentRoot, "src/VeilAgent/Program.cs"), "utf8");
  const capture = await readFile(resolve(agentRoot, "src/VeilAgent/GdiWindowFrameCapture.cs"), "utf8");

  assert.match(program, /new GdiWindowFrameCapture\(\)/);
  assert.match(program, /new WindowFrameStreamer\(/);
  assert.doesNotMatch(program, /new BootstrapPngFrameCapture\(\)/);
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
  assert.match(session, /SerializeFrame\(WindowFrame frame\)/);
  assert.match(server, /StartFrameStream/);
  assert.match(server, /WindowFrameStreamer/);
  assert.match(server, /SerializeFrame\(frame\)/);
  assert.match(streamer, /PeriodicTimer/);
  assert.match(streamer, /firstSequence/);
  assert.match(streamer, /CaptureFrameAsync\(window,\s*sequence/);
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
  assert.match(session, /MessageTypes\.WindowCloseResponse/);
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
});

test("windows agent accepts host clipboard text updates", async () => {
  const messageTypes = await readFile(resolve(agentRoot, "src/VeilAgent/MessageTypes.cs"), "utf8");
  const desktopInterface = await readFile(resolve(agentRoot, "src/VeilAgent/IWindowsDesktop.cs"), "utf8");
  const desktop = await readFile(resolve(agentRoot, "src/VeilAgent/WindowsDesktop.cs"), "utf8");
  const session = await readFile(resolve(agentRoot, "src/VeilAgent/AgentSession.cs"), "utf8");

  assert.match(messageTypes, /ClipboardTextSet\s*=\s*"clipboard\.text\.set"/);
  assert.match(desktopInterface, /SetClipboardTextAsync\(string text,\s*CancellationToken cancellationToken\)/);
  assert.match(desktop, /Clipboard\.SetText/);
  assert.match(desktop, /ApartmentState\.STA/);
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
  assert.match(desktop, /Clipboard\.GetText/);
  assert.match(desktop, /lastHostClipboardText/);
  assert.match(desktop, /lastHostClipboardSequence/);
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

  assert.match(install, /Register-ScheduledTask/);
  assert.match(install, /New-ScheduledTaskTrigger\s+-AtLogOn/);
  assert.match(install, /VeilAgent/);
  assert.match(install, /dotnet publish/);
  assert.match(install, /VEIL_AGENT_PORT/);
  assert.match(start, /VeilAgent\.exe/);
  assert.match(start, /127\.0\.0\.1/);
  assert.match(uninstall, /Unregister-ScheduledTask/);
  assert.match(uninstall, /VeilAgent/);
});

test("windows agent installs logon task against the local installed scripts", async () => {
  const install = await readFile(resolve(agentRoot, "scripts/Install-VeilAgent.ps1"), "utf8");

  assert.match(install, /\$InstalledScriptsRoot\s*=\s*Join-Path\s+\$InstallRoot\s+"scripts"/);
  assert.match(install, /Copy-Item[\s\S]+Start-VeilAgent\.ps1[\s\S]+-Destination\s+\$InstalledScriptsRoot/);
  assert.match(install, /\$StartScript\s*=\s*Join-Path\s+\$InstalledScriptsRoot\s+"Start-VeilAgent\.ps1"/);
  assert.doesNotMatch(install, /\$StartScript\s*=\s*Join-Path\s+\$AgentRoot\s+"scripts\\Start-VeilAgent\.ps1"/);
});

test("windows agent installer starts the installed agent immediately by default", async () => {
  const install = await readFile(resolve(agentRoot, "scripts/Install-VeilAgent.ps1"), "utf8");

  assert.match(install, /\[switch\]\$NoStart/);
  assert.match(install, /if\s*\(-not\s+\$NoStart\)\s*{/);
  assert.match(install, /&\s+\$StartScript\s+-InstallRoot\s+\$InstallRoot\s+-Port\s+\$Port/);
  assert.match(install, /Write-Host "VeilAgent started and listening on ws:\/\/127\.0\.0\.1:\$Port\/\."/);
});
