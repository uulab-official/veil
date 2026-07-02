import { WebSocket, WebSocketServer } from "ws";

import { createSession } from "./session.mjs";

export function createFakeAgentServer({ host = "127.0.0.1", port = 18444 } = {}) {
  const server = new WebSocketServer({ host, port });
  const clients = new Set();

  server.on("connection", (socket) => {
    clients.add(socket);
    socket.on("close", () => {
      clients.delete(socket);
    });

    const session = createSession({
      broadcast: async (event) => {
        const payload = JSON.stringify(event);
        for (const client of clients) {
          if (client.readyState === WebSocket.OPEN) {
            client.send(payload);
          }
        }
      }
    });

    socket.on("message", async (data) => {
      let message;

      try {
        message = JSON.parse(data.toString("utf8"));
      } catch {
        socket.send(JSON.stringify({
          type: "error",
          code: "invalid_json",
          message: "Message payload must be valid JSON"
        }));
        return;
      }

      const replies = await session.handle(message);
      for (const reply of replies) {
        socket.send(JSON.stringify(reply));
      }
    });
  });

  return server;
}
