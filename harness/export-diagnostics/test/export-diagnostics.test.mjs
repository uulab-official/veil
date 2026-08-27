import { readFileSync } from "node:fs";
import { test } from "node:test";
import assert from "node:assert/strict";

import { validateExportDiagnostics } from "../src/validate-export-diagnostics.mjs";

function loadFixture() {
  return JSON.parse(
    readFileSync(new URL("../fixtures/export-diagnostics.windows-installed.json", import.meta.url), "utf8")
  );
}

test("validates a Windows-installed diagnostics bundle fixture", () => {
  const bundle = loadFixture();

  assert.equal(validateExportDiagnostics(bundle), bundle);
});

test("accepts a bundle with no profile or boot report yet", () => {
  const bundle = loadFixture();
  bundle.profile = null;
  bundle.lastBootReport = null;

  assert.equal(validateExportDiagnostics(bundle), bundle);
});

test("rejects a profile carrying security-scoped bookmark bytes", () => {
  const bundle = loadFixture();
  bundle.profile.installerMediaBookmarkData = "base64==";

  assert.throws(
    () => validateExportDiagnostics(bundle),
    /must not include 'installerMediaBookmarkData'/
  );
});

test("rejects a bundle that hides whether the guest has a sound device", () => {
  const bundle = loadFixture();
  delete bundle.snapshot.deviceSummary.audioDevice;

  assert.throws(() => validateExportDiagnostics(bundle), /audioDevice/);
});

test("rejects a configuration summary missing the typed audio section", () => {
  const bundle = loadFixture();
  delete bundle.snapshot.configurationSummary.audio;

  assert.throws(() => validateExportDiagnostics(bundle), /'audio' typed section/);
});

test("rejects a configuration summary missing a typed section", () => {
  const bundle = loadFixture();
  delete bundle.snapshot.configurationSummary.network;

  assert.throws(
    () => validateExportDiagnostics(bundle),
    /missing the 'network' typed section/
  );
});

test("rejects a preflight check with an unsupported state", () => {
  const bundle = loadFixture();
  bundle.snapshot.preflightChecks[0].state = "unknown";

  assert.throws(
    () => validateExportDiagnostics(bundle),
    /Unsupported preflight check state/
  );
});

test("rejects a boot report profile carrying bookmark bytes", () => {
  const bundle = loadFixture();
  bundle.lastBootReport.profile.virtualDiskBookmarkData = "base64==";

  assert.throws(
    () => validateExportDiagnostics(bundle),
    /must not include 'virtualDiskBookmarkData'/
  );
});

test("rejects a bundle that hides whether the guest has a live shared folder", () => {
  const bundle = loadFixture();
  delete bundle.snapshot.deviceSummary.sharedFolderDevice;

  // The profile's `sharedFolderPath` is a macOS install-media staging directory despite its name, so a
  // bundle without this field could read as having sharing configured while the guest saw nothing.
  assert.throws(() => validateExportDiagnostics(bundle), /sharedFolderDevice/);
});
