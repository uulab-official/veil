import WebSocket from "ws";

export function sendMessage(url, message, options = {}) {
  const timeoutMs = options.timeoutMs ?? 2000;

  return new Promise((resolve, reject) => {
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
      finish(reject, new Error(`Timed out sending message to ${url}`));
    }, timeoutMs);

    socket.on("open", () => {
      socket.send(JSON.stringify(message), (error) => {
        if (error) {
          finish(reject, error);
          return;
        }

        socket.close();
      });
    });

    socket.on("close", () => {
      finish(resolve);
    });

    socket.on("error", (error) => {
      finish(reject, error);
    });
  });
}

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

export function collectEventAfter(url, trigger, options = {}) {
  const timeoutMs = options.timeoutMs ?? 2000;
  const predicate = options.predicate ?? (() => true);

  return new Promise((resolve, reject) => {
    const socket = new WebSocket(url);
    let settled = false;
    let matchedEvent;
    let triggerFinished = false;

    const finish = (callback, value) => {
      if (settled) {
        return;
      }

      settled = true;
      clearTimeout(timer);
      socket.close();
      callback(value);
    };

    const finishIfReady = () => {
      if (matchedEvent && triggerFinished) {
        finish(resolve, matchedEvent);
      }
    };

    const timer = setTimeout(() => {
      finish(reject, new Error(`Timed out waiting for event from ${url}`));
    }, timeoutMs);

    socket.on("open", async () => {
      try {
        await trigger();
        triggerFinished = true;
        finishIfReady();
      } catch (error) {
        finish(reject, error);
      }
    });

    socket.on("message", (data) => {
      const event = JSON.parse(data.toString("utf8"));
      if (predicate(event)) {
        matchedEvent = event;
        finishIfReady();
      }
    });

    socket.on("error", (error) => {
      finish(reject, error);
    });
  });
}
