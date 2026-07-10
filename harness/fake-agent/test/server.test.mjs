import assert from "node:assert/strict";
import { once } from "node:events";
import test from "node:test";
import { WebSocket } from "ws";

import { createFakeAgentServer } from "../src/fake-agent-server.mjs";

test("broadcasts subscribed capture frames to separate event clients", async () => {
  const server = createFakeAgentServer({ host: "127.0.0.1", port: 0 });
  await once(server, "listening");
  const address = server.address();
  const url = `ws://${address.address}:${address.port}`;

  const eventClient = new WebSocket(url);
  const requestClient = new WebSocket(url);
  await Promise.all([once(eventClient, "open"), once(requestClient, "open")]);

  const nextEvent = once(eventClient, "message");
  requestClient.send(JSON.stringify({
    type: "window.frame.subscribe",
    requestId: "req_frame_subscribe_notepad",
    windowId: "hwnd:0003029A",
    format: "png"
  }));

  const [payload] = await nextEvent;
  const frame = JSON.parse(payload.toString("utf8"));

  assert.equal(frame.type, "window.frame");
  assert.equal(frame.windowId, "hwnd:0003029A");
  assert.equal(frame.format, "png");
  assert.equal(frame.sequence, 1);

  eventClient.close();
  requestClient.close();
  server.close();
  await once(server, "close");
});

test("shares launched app HWNDs across request and event clients", async () => {
  const server = createFakeAgentServer({ host: "127.0.0.1", port: 0 });
  await once(server, "listening");
  const address = server.address();
  const url = `ws://${address.address}:${address.port}`;

  const eventClient = new WebSocket(url);
  const requestClient = new WebSocket(url);
  await Promise.all([once(eventClient, "open"), once(requestClient, "open")]);

  const nextWindowCreated = waitForMessage(requestClient, (message) => message.type === "window.created");
  requestClient.send(JSON.stringify({
    type: "app.launch.request",
    requestId: "req_launch_calculator",
    appId: "winapp_calculator"
  }));
  await nextWindowCreated;

  const nextEvent = once(eventClient, "message");
  requestClient.send(JSON.stringify({
    type: "window.frame.subscribe",
    requestId: "req_frame_subscribe_calculator",
    windowId: "hwnd:0004029B",
    format: "png"
  }));

  const [payload] = await nextEvent;
  const frame = JSON.parse(payload.toString("utf8"));

  assert.equal(frame.type, "window.frame");
  assert.equal(frame.windowId, "hwnd:0004029B");
  assert.equal(frame.format, "png");

  eventClient.close();
  requestClient.close();
  server.close();
  await once(server, "close");
});

function waitForMessage(socket, predicate) {
  return new Promise((resolve, reject) => {
    const onMessage = (payload) => {
      const message = JSON.parse(payload.toString("utf8"));
      if (!predicate(message)) {
        return;
      }
      cleanup();
      resolve(message);
    };
    const onError = (error) => {
      cleanup();
      reject(error);
    };
    const cleanup = () => {
      socket.off("message", onMessage);
      socket.off("error", onError);
    };

    socket.on("message", onMessage);
    socket.on("error", onError);
  });
}
