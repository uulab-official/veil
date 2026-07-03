import { readFileSync } from "node:fs";
import { test } from "node:test";
import assert from "node:assert/strict";

import { validateAppRuntimeStatus } from "../src/validate-app-runtime-status.mjs";

test("validates app runtime status fixture", () => {
  const report = JSON.parse(readFileSync(new URL("../fixtures/app-runtime-status.demo.json", import.meta.url), "utf8"));

  assert.equal(validateAppRuntimeStatus(report), report);
});

test("rejects reports without required actions", () => {
  const report = JSON.parse(readFileSync(new URL("../fixtures/app-runtime-status.demo.json", import.meta.url), "utf8"));
  report.actions = report.actions.filter((action) => action.id !== "clipboard.setText");

  assert.throws(
    () => validateAppRuntimeStatus(report),
    /clipboard\.setText/
  );
});

test("rejects live agent reports outside agent mode", () => {
  const report = JSON.parse(readFileSync(new URL("../fixtures/app-runtime-status.demo.json", import.meta.url), "utf8"));
  report.connection.hasLiveAgentConnection = true;

  assert.throws(
    () => validateAppRuntimeStatus(report),
    /Only agent mode/
  );
});
