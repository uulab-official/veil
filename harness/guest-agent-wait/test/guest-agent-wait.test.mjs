import { readFileSync } from "node:fs";
import { test } from "node:test";
import assert from "node:assert/strict";

import { validateGuestAgentWait } from "../src/validate-guest-agent-wait.mjs";

test("validates connected guest agent wait fixture", () => {
  const report = JSON.parse(readFileSync(new URL("../fixtures/guest-agent-wait.connected.json", import.meta.url), "utf8"));

  assert.equal(validateGuestAgentWait(report), report);
});

test("rejects connected reports without app runtime next action", () => {
  const report = JSON.parse(readFileSync(new URL("../fixtures/guest-agent-wait.connected.json", import.meta.url), "utf8"));
  report.nextActions = report.nextActions.filter((action) => !action.includes("app-runtime-status"));

  assert.throws(
    () => validateGuestAgentWait(report),
    /app-runtime-status/
  );
});

test("rejects connected reports without app window proof next action", () => {
  const report = JSON.parse(readFileSync(new URL("../fixtures/guest-agent-wait.connected.json", import.meta.url), "utf8"));
  report.nextActions = report.nextActions.filter((action) => !action.includes("app-window-proof"));

  assert.throws(
    () => validateGuestAgentWait(report),
    /app-window-proof/
  );
});

test("rejects unavailable reports without install recovery guidance", () => {
  const report = JSON.parse(readFileSync(new URL("../fixtures/guest-agent-wait.connected.json", import.meta.url), "utf8"));
  report.status = "unavailable";
  report.diagnostic.status = "unavailable";
  delete report.connectedAt;
  delete report.diagnostic.health;
  report.diagnostic.errorMessage = "Connection refused.";
  report.nextActions = ["Confirm Windows is running."];

  assert.throws(
    () => validateGuestAgentWait(report),
    /Install Veil Agent/
  );
});
