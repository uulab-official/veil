import assert from "node:assert/strict";
import test from "node:test";
import { WebSocketServer } from "ws";

import { collectEventAfter, collectReplies, sendMessage } from "../src/client.mjs";

test("collects replies until the expected count is reached", async () => {
  const server = new WebSocketServer({ host: "127.0.0.1", port: 0 });
  await new Promise((resolve) => server.once("listening", resolve));
  const address = server.address();

  server.on("connection", (socket) => {
    socket.on("message", () => {
      socket.send(JSON.stringify({ type: "first" }));
      socket.send(JSON.stringify({ type: "second" }));
    });
  });

  const replies = await collectReplies(`ws://127.0.0.1:${address.port}`, { type: "probe" }, {
    expectedCount: 2,
    timeoutMs: 500
  });

  assert.deepEqual(replies.map((reply) => reply.type), ["first", "second"]);
  await new Promise((resolve) => server.close(resolve));
});

test("times out when expected replies do not arrive", async () => {
  const server = new WebSocketServer({ host: "127.0.0.1", port: 0 });
  await new Promise((resolve) => server.once("listening", resolve));
  const address = server.address();

  server.on("connection", () => {});

  await assert.rejects(
    collectReplies(`ws://127.0.0.1:${address.port}`, { type: "probe" }, {
      expectedCount: 1,
      timeoutMs: 20
    }),
    /Timed out waiting for 1 reply/
  );

  await new Promise((resolve) => server.close(resolve));
});

test("sends messages that do not have direct replies", async (t) => {
  const server = new WebSocketServer({ host: "127.0.0.1", port: 0 });
  t.after(() => {
    server.close();
  });
  await new Promise((resolve) => server.once("listening", resolve));
  const address = server.address();
  const received = [];

  server.on("connection", (socket) => {
    socket.on("message", (data) => {
      received.push(JSON.parse(data.toString("utf8")));
    });
  });

  await sendMessage(`ws://127.0.0.1:${address.port}`, {
    type: "window.frame.subscribe",
    requestId: "req_frame_subscribe_notepad",
    windowId: "hwnd:0003029A",
    format: "png"
  }, {
    timeoutMs: 500
  });

  assert.equal(received.length, 1);
  assert.equal(received[0].type, "window.frame.subscribe");
});

test("collects an event after opening the event socket and running a trigger", async (t) => {
  const server = new WebSocketServer({ host: "127.0.0.1", port: 0 });
  t.after(() => {
    server.close();
  });
  await new Promise((resolve) => server.once("listening", resolve));
  const address = server.address();
  const clients = new Set();

  server.on("connection", (socket) => {
    clients.add(socket);
    socket.on("close", () => {
      clients.delete(socket);
    });
    socket.on("message", () => {
      for (const client of clients) {
        client.send(JSON.stringify({
          type: "window.frame",
          windowId: "hwnd:0003029A",
          frameId: "frame_000001",
          sequence: 1,
          format: "png",
          width: 1,
          height: 1,
          scale: 1,
          encodedData: "fixture"
        }));
      }
    });
  });

  const event = await collectEventAfter(
    `ws://127.0.0.1:${address.port}`,
    () => sendMessage(`ws://127.0.0.1:${address.port}`, {
      type: "window.frame.subscribe",
      requestId: "req_frame_subscribe_notepad",
      windowId: "hwnd:0003029A",
      format: "png"
    }),
    {
      timeoutMs: 500
    }
  );

  assert.equal(event.type, "window.frame");
  assert.equal(event.windowId, "hwnd:0003029A");
});
