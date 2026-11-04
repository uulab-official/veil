// macOS integration: real URLSession sockets against an ephemeral fake guest.
// Build veil-vmctl first, then run: node --test script/test_operation_ack_transport.mjs
import assert from "node:assert/strict";
import { execFile } from "node:child_process";
import { once } from "node:events";
import { access, readFile } from "node:fs/promises";
import { createRequire } from "node:module";
import { fileURLToPath } from "node:url";
import { promisify } from "node:util";
import test from "node:test";

const require = createRequire(new URL("../harness/fake-agent/package.json", import.meta.url));
const { WebSocketServer } = require("ws");
const run = promisify(execFile);
const vmctl = process.env.VEIL_VMCTL
  ?? fileURLToPath(new URL("../apps/mac-host/.build/debug/veil-vmctl", import.meta.url));
const fixture = async (name) => JSON.parse(await readFile(
  new URL(`../harness/protocol-fixtures/${name}.json`, import.meta.url), "utf8"
));

for (const mode of ["ack", "silent", "events-without-ack", "mismatched", "rejected", "guest-error", "legacy"]) {
  test(`clipboard delivery over URLSession: ${mode}`, async () => {
    const result = await exercise(mode, ["--action", "clipboard", "--text", "ack transport check"]);
    assert.equal(result.operations.length, 1, "uncertain operations must never be retried");
    if (mode === "ack" || mode === "legacy") {
      assert.equal(result.code, 0, result.stderr);
      assert.equal(JSON.parse(result.stdout).accepted, true);
    } else {
      assert.notEqual(result.code, 0);
      assert.match(result.stderr, mode === "guest-error" ? /Clipboard is busy/ : /did not confirm/);
    }
    if (mode === "silent" || mode === "events-without-ack") {
      assert.ok(result.replyElapsed >= 1_800, "the configured two-second wait must not fail immediately");
      assert.ok(result.replyElapsed < 8_000, "a silent or event-only guest must not strand socket receive");
    }
  });
}

for (const [name, args] of [
  ["key", ["--action", "type-text", "--window-id", "hwnd:0003029A", "--text", "a"]],
  ["mouse", ["--action", "click", "--window-id", "hwnd:0003029A", "--x", "20", "--y", "30"]]
]) {
  test(`${name} input is correlated over real URLSession sockets`, async () => {
    const result = await exercise("ack", args);
    assert.equal(result.code, 0, result.stderr);
    assert.equal(JSON.parse(result.stdout).accepted, true);
    assert.ok(result.operations.length > 0);
    const ids = result.operations.map((message) => message.requestId);
    assert.ok(ids.every((id) => typeof id === "string" && id.length > 0));
    assert.equal(new Set(ids).size, ids.length);
  });
}

async function exercise(mode, args) {
  await access(vmctl);
  const health = await fixture("agent.health.response");
  health.capabilities.operationAcks = mode !== "legacy";
  const apps = await fixture("app.list.response");
  const operations = [];
  let firstOperationAt;
  const server = new WebSocketServer({ host: "127.0.0.1", port: 0 });
  await once(server, "listening");
  server.on("connection", (socket) => {
    let events;
    socket.on("error", () => {}); // timeout/cancellation deliberately closes clients
    socket.on("close", () => clearInterval(events));
    socket.on("message", (data) => {
      const message = JSON.parse(data.toString());
      if (message.type === "agent.health.request" || message.type === "app.list.request") {
        socket.send(JSON.stringify({
          ...(message.type === "agent.health.request" ? health : apps),
          requestId: message.requestId
        }));
        return;
      }
      operations.push(message);
      firstOperationAt ??= performance.now();
      if (mode === "legacy" || mode === "silent") return;
      if (mode === "events-without-ack") {
        events = setInterval(() => {
          if (socket.readyState === 1) socket.send(JSON.stringify({
            type: "window.frame.unchanged", windowId: "hwnd:0003029A", sequence: 1
          }));
        }, 100);
        return;
      }
      socket.send(JSON.stringify(mode === "guest-error" ? {
        type: "error", requestId: message.requestId, code: "clipboard_busy", message: "Clipboard is busy."
      } : {
        type: "operation.ack",
        requestId: mode === "mismatched" ? "unrelated-request" : message.requestId,
        accepted: mode !== "rejected"
      }));
    });
  });
  try {
    let stdout, stderr, code;
    try {
      ({ stdout, stderr } = await run(vmctl, ["app-runtime-action", "--json", ...args], {
        env: { ...process.env, VEIL_AGENT_URL: `ws://127.0.0.1:${server.address().port}` },
        timeout: 10_000,
        maxBuffer: 8 * 1024 * 1024
      }));
      code = 0;
    } catch (error) {
      assert.equal(error.killed, false, "the CLI exceeded the integration deadline");
      ({ stdout, stderr, code } = error);
    }
    return { stdout, stderr, code, operations, replyElapsed: performance.now() - firstOperationAt };
  } finally {
    for (const socket of server.clients) socket.terminate();
    await new Promise((resolve) => server.close(resolve));
  }
}
