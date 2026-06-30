import assert from "node:assert/strict";
import test from "node:test";
import { WebSocketServer } from "ws";

import { collectReplies } from "../src/client.mjs";

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
