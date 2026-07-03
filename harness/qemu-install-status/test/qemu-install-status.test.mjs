import { readFileSync } from "node:fs";
import { test } from "node:test";
import assert from "node:assert/strict";

import { validateQEMUInstallStatus } from "../src/validate-qemu-install-status.mjs";

test("validates running QEMU install status fixture", () => {
  const report = JSON.parse(readFileSync(new URL("../fixtures/qemu-install-status.running.json", import.meta.url), "utf8"));

  assert.equal(validateQEMUInstallStatus(report), report);
});

test("accepts running blocked reports without launch evidence", () => {
  const report = JSON.parse(readFileSync(new URL("../fixtures/qemu-install-status.running.json", import.meta.url), "utf8"));
  delete report.latestConsoleLaunch;
  report.bootReady = false;
  report.installEvidence.kind = "setupBlocked";
  report.installEvidence.title = "Setup blocked";
  report.installEvidence.detail = "Installer media requires re-selection.";
  report.nextActions = ["Installer media: Installer media requires re-selection."];

  assert.equal(validateQEMUInstallStatus(report), report);
});

test("rejects running reports with launch evidence but without capture guidance", () => {
  const report = JSON.parse(readFileSync(new URL("../fixtures/qemu-install-status.running.json", import.meta.url), "utf8"));
  report.nextActions = report.nextActions.filter((action) => !action.includes("qemu-capture"));

  assert.throws(
    () => validateQEMUInstallStatus(report),
    /qemu-capture/
  );
});

test("rejects live display surfaces without validation guidance", () => {
  const report = JSON.parse(readFileSync(new URL("../fixtures/qemu-install-status.running.json", import.meta.url), "utf8"));
  delete report.displaySurface.validationCommand;

  assert.throws(
    () => validateQEMUInstallStatus(report),
    /qemu-display-smoke/
  );
});
