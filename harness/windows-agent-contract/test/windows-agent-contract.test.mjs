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
  assert.doesNotMatch(program, /new BootstrapPngFrameCapture\(\)/);
  assert.match(capture, /PrintWindow/);
  assert.match(capture, /GetWindowRect/);
  assert.match(capture, /ImageFormat\.Png/);
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
