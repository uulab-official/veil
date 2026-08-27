import { readFileSync } from "node:fs";
import { test } from "node:test";
import assert from "node:assert/strict";

import { validateFramePipelineReport } from "../src/validate-frame-pipeline-report.mjs";

function readFixture(name) {
  return JSON.parse(readFileSync(new URL(`../fixtures/${name}`, import.meta.url), "utf8"));
}

test("validates a typing measurement and an empty measurement", () => {
  for (const name of ["frame-pipeline-report.typing.json", "frame-pipeline-report.no-frames.json"]) {
    const report = readFixture(name);
    assert.equal(validateFramePipelineReport(report), report, name);
  }
});

test("rejects a report that claims frames while none were applied", () => {
  // A report with no frames must never be mistaken for a measured result of zero: the two lead to
  // completely different conclusions about the pipeline.
  const report = readFixture("frame-pipeline-report.no-frames.json");
  report.didObserveFrames = true;

  assert.throws(() => validateFramePipelineReport(report), /didObserveFrames must agree/);
});

test("rejects a report with no frames that does not say how to diagnose it", () => {
  const report = readFixture("frame-pipeline-report.no-frames.json");
  report.nextActions = ["Try again."];

  assert.throws(() => validateFramePipelineReport(report), /app-runtime-status/);
});

test("rejects wire byte totals that do not add up", () => {
  const report = readFixture("frame-pipeline-report.typing.json");
  report.totalWireBytes += 1;

  assert.throws(() => validateFramePipelineReport(report), /sum of per-window wireBytes/);
});

test("rejects per-window wire bytes that do not split into key frames and tiles", () => {
  const report = readFixture("frame-pipeline-report.typing.json");
  report.windows[0].tileWireBytes += 10;

  assert.throws(() => validateFramePipelineReport(report), /keyFrameWireBytes plus tileWireBytes/);
});

test("rejects tile coverage above the surface size", () => {
  const report = readFixture("frame-pipeline-report.typing.json");
  report.windows[0].tileCoveragePercent.maximum = 140;

  assert.throws(() => validateFramePipelineReport(report), /cannot exceed 100/);
});

test("rejects percentiles that are not ordered", () => {
  // Nearest-rank percentiles over sorted samples make this a structural guarantee, so a violation means
  // the summary was assembled wrong rather than that the data was unusual.
  const report = readFixture("frame-pipeline-report.typing.json");
  report.windows[0].frameIntervalMilliseconds.p50 = 900;

  assert.throws(() => validateFramePipelineReport(report), /percentiles must be ordered/);
});

test("rejects a non-empty summary whose mean exceeds its maximum", () => {
  const report = readFixture("frame-pipeline-report.typing.json");
  report.windows[0].compositeMilliseconds.mean = 99;

  assert.throws(() => validateFramePipelineReport(report), /cannot exceed/);
});

test("rejects a zero-sample summary carrying non-zero statistics", () => {
  const report = readFixture("frame-pipeline-report.typing.json");
  report.windows[0].compositeMilliseconds = { count: 0, mean: 1, p50: 0, p95: 0, maximum: 0 };

  assert.throws(() => validateFramePipelineReport(report), /must be zero when no samples/);
});

test("rejects more interval samples than consecutive updates allow", () => {
  const report = readFixture("frame-pipeline-report.typing.json");
  report.windows[0].frameIntervalMilliseconds.count = 999;

  assert.throws(() => validateFramePipelineReport(report), /applied updates minus one/);
});

test("rejects a window with an observed key frame but no full-frame estimate", () => {
  // The estimate is the number that answers "did tiles help", so a report that could compute it and did
  // not is incomplete rather than merely terse.
  const report = readFixture("frame-pipeline-report.typing.json");
  delete report.windows[0].estimatedFullFrameWireBytes;
  delete report.windows[0].estimatedWireBytesSavedPercent;

  assert.throws(() => validateFramePipelineReport(report), /must report a full-frame estimate/);
});

test("rejects an estimate present without its savings percentage", () => {
  const report = readFixture("frame-pipeline-report.typing.json");
  delete report.windows[0].estimatedWireBytesSavedPercent;

  assert.throws(() => validateFramePipelineReport(report), /must be present together/);
});

test("accepts a negative savings percentage", () => {
  // Negative is meaningful, not invalid: it means tiles cost more wire bytes than full frames would have,
  // which is a real outcome for content that changes everywhere.
  const report = readFixture("frame-pipeline-report.typing.json");
  report.windows[0].estimatedWireBytesSavedPercent = -18.4;
  report.nextActions.push(
    "Tiles cost more wire bytes than full frames would have. Lower the key-frame promotion threshold."
  );

  assert.equal(validateFramePipelineReport(report), report);
});

test("rejects dropped tiles that are not called out in next actions", () => {
  const report = readFixture("frame-pipeline-report.typing.json");
  report.windows[0].droppedTiles.noSurface = 3;

  assert.throws(() => validateFramePipelineReport(report), /call them out in nextActions/);
});

test("rejects an estimation basis that does not admit it is an estimate", () => {
  const report = readFixture("frame-pipeline-report.typing.json");
  report.estimationBasis = "Full-frame cost measured exactly.";

  assert.throws(() => validateFramePipelineReport(report), /must state that the full-frame comparison is an estimate/);
});

test("rejects duplicate windows", () => {
  const report = readFixture("frame-pipeline-report.typing.json");
  report.windows.push({ ...report.windows[0] });
  report.totalWireBytes *= 2;

  assert.throws(() => validateFramePipelineReport(report), /duplicate windowId/);
});
