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
  report.nextActions = [
    "Close existing QEMU/Windows PID 2345 before preparing or relaunching; Veil detected the configured disk is already attached but has no current launch record.",
    "Installer media: Installer media requires re-selection."
  ];

  assert.equal(validateQEMUInstallStatus(report), report);
});

test("rejects running reports without launch evidence or recovery guidance", () => {
  const report = JSON.parse(readFileSync(new URL("../fixtures/qemu-install-status.running.json", import.meta.url), "utf8"));
  delete report.latestConsoleLaunch;
  report.bootReady = false;
  report.installEvidence.kind = "setupBlocked";
  report.installEvidence.title = "Setup blocked";
  report.installEvidence.detail = "Installer media requires re-selection.";
  report.nextActions = ["Installer media: Installer media requires re-selection."];

  assert.throws(
    () => validateQEMUInstallStatus(report),
    /existing QEMU/
  );
});

test("rejects running reports without launch evidence or process evidence", () => {
  const report = JSON.parse(readFileSync(new URL("../fixtures/qemu-install-status.running.json", import.meta.url), "utf8"));
  delete report.latestConsoleLaunch;
  delete report.runningQEMUProcess;
  report.bootReady = false;
  report.installEvidence.kind = "setupBlocked";
  report.installEvidence.title = "Setup blocked";
  report.installEvidence.detail = "Installer media requires re-selection.";
  report.nextActions = [
    "Close existing QEMU/Windows PID 2345 before preparing or relaunching; Veil detected the configured disk is already attached but has no current launch record.",
    "Installer media: Installer media requires re-selection."
  ];

  assert.throws(
    () => validateQEMUInstallStatus(report),
    /runningQEMUProcess/
  );
});

test("rejects running reports with launch evidence but without capture guidance", () => {
  const report = JSON.parse(readFileSync(new URL("../fixtures/qemu-install-status.running.json", import.meta.url), "utf8"));
  report.nextActions = report.nextActions.filter((action) => !action.includes("qemu-capture"));

  assert.throws(
    () => validateQEMUInstallStatus(report),
    /qemu-capture/
  );
});

test("accepts stale automatic install media with rebuild guidance", () => {
  const report = JSON.parse(readFileSync(new URL("../fixtures/qemu-install-status.running.json", import.meta.url), "utf8"));
  report.automaticInstallMediaStatus.state = "stale";
  report.automaticInstallMediaStatus.isCurrent = false;
  report.automaticInstallMediaStatus.recommendedAction = "rebuild-media-and-relaunch";
  report.automaticInstallMediaStatus.requiresRelaunch = true;
  report.automaticInstallMediaStatus.mediaModifiedAt = "2026-07-03T11:55:00Z";
  report.automaticInstallMediaStatus.sourceModifiedAt = "2026-07-03T11:56:00Z";
  report.nextActions = [
    "Capture the current console before changing setup state, then shut down with `veil-vmctl qemu-powerdown --json` if you need to reselect media or relaunch.",
    "Validate the embedded console with `veil-vmctl qemu-display-smoke --json`.",
    "Refresh install evidence with `veil-vmctl qemu-capture --json` before changing recovery steps.",
    "Power down Windows with `veil-vmctl qemu-powerdown --json`, rebuild guest tools media with `veil-vmctl prepare --installer /Users/test/Downloads/Win11_25H2_Korean_Arm64_v2.iso --drivers /Users/test/Downloads/virtio-win.iso`, then restart Windows so QEMU attaches the refreshed `VeilAutoInstall.iso`.",
    "Continue Windows Setup in the console; use `veil-vmctl qemu-oobe-bypass --json` only when OOBE network setup blocks local account creation."
  ];

  assert.equal(validateQEMUInstallStatus(report), report);
});

test("rejects stale automatic install media without rebuild guidance", () => {
  const report = JSON.parse(readFileSync(new URL("../fixtures/qemu-install-status.running.json", import.meta.url), "utf8"));
  report.automaticInstallMediaStatus.state = "stale";
  report.automaticInstallMediaStatus.isCurrent = false;
  report.automaticInstallMediaStatus.recommendedAction = "rebuild-media-and-relaunch";
  report.automaticInstallMediaStatus.requiresRelaunch = true;

  assert.throws(
    () => validateQEMUInstallStatus(report),
    /rebuild and relaunch/
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
