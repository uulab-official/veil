import { readFileSync } from "node:fs";
import { test } from "node:test";
import assert from "node:assert/strict";

import { validateAppRuntimeReviewManifest } from "../src/validate-app-runtime-review-manifest.mjs";

function demoManifest() {
  return JSON.parse(readFileSync(new URL("../fixtures/app-runtime-review-manifest.demo.json", import.meta.url), "utf8"));
}

test("validates app runtime review manifest fixture", () => {
  const manifest = demoManifest();

  assert.equal(validateAppRuntimeReviewManifest(manifest), manifest);
});

test("rejects manifests with missing screenshot files", () => {
  const manifest = demoManifest();
  manifest.screenshotFiles.pop();

  assert.throws(
    () => validateAppRuntimeReviewManifest(manifest),
    /every required screenshot/
  );
});

test("rejects manifests with drifted screenshot file names", () => {
  const manifest = demoManifest();
  manifest.screenshotFiles[0].expectedFileName = "wrong.png";

  assert.throws(
    () => validateAppRuntimeReviewManifest(manifest),
    /file names/
  );
});
