import WebSocket from "ws";

export function collectReplies(url, message, options = {}) {
  const expectedCount = options.expectedCount ?? 1;
  const timeoutMs = options.timeoutMs ?? 2000;

  return new Promise((resolve, reject) => {
    const replies = [];
    const socket = new WebSocket(url);
    let settled = false;

    const finish = (callback, value) => {
      if (settled) {
        return;
      }

      settled = true;
      clearTimeout(timer);
      socket.close();
      callback(value);
    };

    const timer = setTimeout(() => {
      finish(reject, new Error(`Timed out waiting for ${expectedCount} reply/replies from ${url}`));
    }, timeoutMs);

    socket.on("open", () => {
      socket.send(JSON.stringify(message));
    });

    socket.on("message", (data) => {
      replies.push(JSON.parse(data.toString("utf8")));
      if (replies.length >= expectedCount) {
        finish(resolve, replies);
      }
    });

    socket.on("error", (error) => {
      finish(reject, error);
    });
  });
}
