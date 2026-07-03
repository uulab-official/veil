import { readFileSync } from "node:fs";
import { test } from "node:test";
import assert from "node:assert/strict";

import { validateAppWindowProof } from "../src/validate-app-window-proof.mjs";

test("validates app window proof fixture", () => {
  const report = JSON.parse(readFileSync(new URL("../fixtures/app-window-proof.notepad.json", import.meta.url), "utf8"));

  assert.equal(validateAppWindowProof(report), report);
});

test("rejects mismatched frame window id", () => {
  const report = JSON.parse(readFileSync(new URL("../fixtures/app-window-proof.notepad.json", import.meta.url), "utf8"));
  report.frame.windowId = "hwnd:00000001";

  assert.throws(
    () => validateAppWindowProof(report),
    /frame\.windowId/
  );
});

test("rejects proof without app runtime next action", () => {
  const report = JSON.parse(readFileSync(new URL("../fixtures/app-window-proof.notepad.json", import.meta.url), "utf8"));
  report.nextActions = ["Open the mirrored HWND in the Veil host shell as a macOS window."];

  assert.throws(
    () => validateAppWindowProof(report),
    /app-runtime-status/
  );
});
