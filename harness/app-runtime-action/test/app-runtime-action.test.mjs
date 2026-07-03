import { readFileSync } from "node:fs";
import { test } from "node:test";
import assert from "node:assert/strict";

import { validateAppRuntimeAction } from "../src/validate-app-runtime-action.mjs";

test("validates app runtime launch action fixture", () => {
  const report = JSON.parse(readFileSync(new URL("../fixtures/app-runtime-action.launch-demo.json", import.meta.url), "utf8"));

  assert.equal(validateAppRuntimeAction(report), report);
});

test("rejects accepted launch actions without a window", () => {
  const report = JSON.parse(readFileSync(new URL("../fixtures/app-runtime-action.launch-demo.json", import.meta.url), "utf8"));
  delete report.window;

  assert.throws(
    () => validateAppRuntimeAction(report),
    /window must be an object/
  );
});

test("rejects unsupported app runtime actions", () => {
  const report = JSON.parse(readFileSync(new URL("../fixtures/app-runtime-action.launch-demo.json", import.meta.url), "utf8"));
  report.action = "teleport";

  assert.throws(
    () => validateAppRuntimeAction(report),
    /Unsupported app runtime action/
  );
});
