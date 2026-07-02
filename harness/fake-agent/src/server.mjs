import { createFakeAgentServer } from "./fake-agent-server.mjs";

const host = process.env.VEIL_FAKE_AGENT_HOST ?? "127.0.0.1";
const port = Number.parseInt(process.env.VEIL_FAKE_AGENT_PORT ?? "18444", 10);

const server = createFakeAgentServer({ host, port });

server.on("listening", () => {
  const address = server.address();
  const label = typeof address === "string" ? address : `${address.address}:${address.port}`;
  console.log(`Veil fake agent listening on ws://${label}`);
});
