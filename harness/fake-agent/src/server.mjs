import { WebSocketServer } from "ws";

import { createSession } from "./session.mjs";

const host = process.env.VEIL_FAKE_AGENT_HOST ?? "127.0.0.1";
const port = Number.parseInt(process.env.VEIL_FAKE_AGENT_PORT ?? "18444", 10);

const server = new WebSocketServer({ host, port });

server.on("connection", (socket) => {
  const session = createSession();

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

server.on("listening", () => {
  const address = server.address();
  const label = typeof address === "string" ? address : `${address.address}:${address.port}`;
  console.log(`Veil fake agent listening on ws://${label}`);
});
