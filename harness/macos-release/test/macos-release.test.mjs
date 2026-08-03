import assert from "node:assert/strict";
import { readFile } from "node:fs/promises";
import { spawnSync } from "node:child_process";
import test from "node:test";
import { fileURLToPath } from "node:url";

const repositoryRoot = fileURLToPath(new URL("../../..", import.meta.url));
const releaseScriptPath = fileURLToPath(new URL("../../../script/release_macos.sh", import.meta.url));
const releaseEntitlementsPath = fileURLToPath(
  new URL("../../../apps/mac-host/VeilHostShell.release.entitlements", import.meta.url)
);

test("release help documents Developer ID and keychain profile inputs", () => {
  const result = spawnSync("bash", [releaseScriptPath, "--help"], {
    cwd: repositoryRoot,
    encoding: "utf8"
  });

  assert.equal(result.status, 0, result.stderr);
  assert.match(result.stdout, /VEIL_DEVELOPER_ID_APPLICATION/);
  assert.match(result.stdout, /VEIL_NOTARY_KEYCHAIN_PROFILE/);
  assert.match(result.stdout, /notarytool store-credentials/);
});

test("release preflight fails before building without a Developer ID identity", () => {
  const result = spawnSync("bash", [releaseScriptPath, "--preflight"], {
    cwd: repositoryRoot,
    encoding: "utf8",
    env: {
      ...process.env,
      VEIL_DEVELOPER_ID_APPLICATION: "",
      VEIL_NOTARY_KEYCHAIN_PROFILE: ""
    }
  });

  assert.equal(result.status, 2);
  assert.match(result.stderr, /release blocked: set VEIL_DEVELOPER_ID_APPLICATION/);
  assert.doesNotMatch(result.stdout, /Building for production/);
});

test("release preflight rejects development certificates", () => {
  const result = spawnSync("bash", [releaseScriptPath, "--preflight"], {
    cwd: repositoryRoot,
    encoding: "utf8",
    env: {
      ...process.env,
      VEIL_DEVELOPER_ID_APPLICATION: "Apple Development: Example",
      VEIL_NOTARY_KEYCHAIN_PROFILE: "veil-notary"
    }
  });

  assert.equal(result.status, 2);
  assert.match(result.stderr, /must use a Developer ID Application certificate/);
});

test("release entitlements keep virtualization and remove debugger attachment", async () => {
  const entitlements = await readFile(releaseEntitlementsPath, "utf8");

  assert.match(entitlements, /com\.apple\.security\.virtualization/);
  assert.doesNotMatch(entitlements, /com\.apple\.security\.get-task-allow/);
});

test("release workflow requires the current notarization and Gatekeeper sequence", async () => {
  const script = await readFile(releaseScriptPath, "utf8");

  assert.match(script, /codesign --force --timestamp --options runtime/);
  assert.match(script, /notarytool submit/);
  assert.match(script, /notarytool history/);
  assert.match(script, /notarytool log/);
  assert.match(script, /stapler staple/);
  assert.match(script, /stapler validate/);
  assert.match(script, /spctl --assess --type execute/);
  assert.doesNotMatch(script, /\baltool\b/);
  assert.doesNotMatch(script, /rm -rf "\$OUTPUT_DIR"/);
});
