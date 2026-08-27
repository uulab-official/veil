import { readFileSync } from "node:fs";
import { fileURLToPath } from "node:url";

const VALID_TRANSPORTS = new Set(["binaryFrameChannel"]);
const DROPPED_TILE_REASONS = [
  "noSurface",
  "surfaceSizeChanged",
  "undecodablePayload",
  "payloadRectMismatch"
];
const SAMPLE_SERIES = ["frameIntervalMilliseconds", "tileCoveragePercent", "compositeMilliseconds"];

export function validateFramePipelineReport(report) {
  if (!report || typeof report !== "object" || Array.isArray(report)) {
    throw new TypeError("Frame pipeline report must be a JSON object.");
  }

  requireString(report.kind, "kind");
  if (report.kind !== "framePipelineReport") {
    throw new TypeError(`Unsupported frame pipeline report kind: ${report.kind}`);
  }

  requireString(report.generatedAt, "generatedAt");
  if (Number.isNaN(Date.parse(report.generatedAt))) {
    throw new TypeError("generatedAt must be an ISO date.");
  }

  requireNonNegativeNumber(report.observedSeconds, "observedSeconds");
  requireBoolean(report.didObserveFrames, "didObserveFrames");
  requireString(report.transport, "transport");
  if (!VALID_TRANSPORTS.has(report.transport)) {
    throw new TypeError(`Unsupported frame pipeline transport: ${report.transport}`);
  }

  requireNonNegativeInteger(report.totalWireBytes, "totalWireBytes");
  requireNonNegativeNumber(report.totalFramesPerSecond, "totalFramesPerSecond");
  requireNonNegativeNumber(report.totalWireBytesPerSecond, "totalWireBytesPerSecond");

  // The estimate is anchored to observed key-frame bytes per pixel, and PNG size is not linear in area.
  // Saying so in the report is what keeps a reader from treating it as a measurement.
  requireString(report.estimationBasis, "estimationBasis");
  if (!report.estimationBasis.includes("estimate")) {
    throw new TypeError("estimationBasis must state that the full-frame comparison is an estimate.");
  }

  if (!Array.isArray(report.windows)) {
    throw new TypeError("windows must be an array.");
  }

  let appliedUpdates = 0;
  let wireBytes = 0;
  const windowIds = new Set();
  for (const window of report.windows) {
    validateWindow(window, report.observedSeconds);
    if (windowIds.has(window.windowId)) {
      throw new TypeError(`windows contains a duplicate windowId: ${window.windowId}`);
    }
    windowIds.add(window.windowId);
    appliedUpdates += window.keyFrameCount + window.tileCount;
    wireBytes += window.wireBytes;
  }

  if (wireBytes !== report.totalWireBytes) {
    throw new TypeError("totalWireBytes must equal the sum of per-window wireBytes.");
  }

  // A report with no frames must never look like a measured result of zero, because the two lead to
  // completely different conclusions about the pipeline.
  if (report.didObserveFrames !== appliedUpdates > 0) {
    throw new TypeError("didObserveFrames must agree with whether any frames or tiles were applied.");
  }

  validateNextActions(report);
  return report;
}

function validateWindow(window, reportObservedSeconds) {
  if (!window || typeof window !== "object" || Array.isArray(window)) {
    throw new TypeError("windows[] entries must be objects.");
  }

  requireString(window.windowId, "windows[].windowId");
  requireNonNegativeInteger(window.surfaceWidth, "windows[].surfaceWidth");
  requireNonNegativeInteger(window.surfaceHeight, "windows[].surfaceHeight");
  requireNonNegativeNumber(window.observedSeconds, "windows[].observedSeconds");
  if (window.observedSeconds !== reportObservedSeconds) {
    throw new TypeError("windows[].observedSeconds must match the report's observation window.");
  }

  requireNonNegativeInteger(window.keyFrameCount, "windows[].keyFrameCount");
  requireNonNegativeInteger(window.tileCount, "windows[].tileCount");
  requireNonNegativeInteger(window.unchangedHeartbeatCount, "windows[].unchangedHeartbeatCount");
  requireNonNegativeInteger(window.wireBytes, "windows[].wireBytes");
  requireNonNegativeInteger(window.keyFrameWireBytes, "windows[].keyFrameWireBytes");
  requireNonNegativeInteger(window.tileWireBytes, "windows[].tileWireBytes");
  requireNonNegativeNumber(window.framesPerSecond, "windows[].framesPerSecond");
  requireNonNegativeNumber(window.wireBytesPerSecond, "windows[].wireBytesPerSecond");

  if (window.keyFrameWireBytes + window.tileWireBytes !== window.wireBytes) {
    throw new TypeError("windows[].wireBytes must equal keyFrameWireBytes plus tileWireBytes.");
  }
  if (window.keyFrameCount === 0 && window.keyFrameWireBytes !== 0) {
    throw new TypeError("windows[].keyFrameWireBytes requires at least one key frame.");
  }
  if (window.tileCount === 0 && window.tileWireBytes !== 0) {
    throw new TypeError("windows[].tileWireBytes requires at least one tile.");
  }

  validateDroppedTiles(window.droppedTiles);

  for (const series of SAMPLE_SERIES) {
    validateSampleSummary(window[series], `windows[].${series}`);
  }

  // A tile cannot cover more of the surface than exists, and a key frame covers exactly all of it, so
  // anything above 100 means the rectangle or the surface size is wrong.
  if (window.tileCoveragePercent.maximum > 100) {
    throw new TypeError("windows[].tileCoveragePercent cannot exceed 100.");
  }

  const appliedUpdates = window.keyFrameCount + window.tileCount;
  if (window.tileCoveragePercent.count > appliedUpdates) {
    throw new TypeError("windows[].tileCoveragePercent samples cannot exceed the number of applied updates.");
  }
  // Intervals are measured between consecutive updates, so there is always one fewer than updates.
  if (appliedUpdates > 0 && window.frameIntervalMilliseconds.count > appliedUpdates - 1) {
    throw new TypeError("windows[].frameIntervalMilliseconds samples cannot exceed applied updates minus one.");
  }

  validateFullFrameEstimate(window);
}

function validateDroppedTiles(droppedTiles) {
  if (!droppedTiles || typeof droppedTiles !== "object" || Array.isArray(droppedTiles)) {
    throw new TypeError("windows[].droppedTiles must be an object.");
  }

  for (const reason of DROPPED_TILE_REASONS) {
    requireNonNegativeInteger(droppedTiles[reason], `windows[].droppedTiles.${reason}`);
  }
}

function validateSampleSummary(summary, fieldName) {
  if (!summary || typeof summary !== "object" || Array.isArray(summary)) {
    throw new TypeError(`${fieldName} must be an object.`);
  }

  requireNonNegativeInteger(summary.count, `${fieldName}.count`);
  for (const field of ["mean", "p50", "p95", "maximum"]) {
    requireNonNegativeNumber(summary[field], `${fieldName}.${field}`);
  }

  if (summary.count === 0) {
    for (const field of ["mean", "p50", "p95", "maximum"]) {
      if (summary[field] !== 0) {
        throw new TypeError(`${fieldName}.${field} must be zero when no samples were collected.`);
      }
    }
    return;
  }

  // Percentiles are nearest-rank over sorted samples, so this ordering is a structural guarantee, not a
  // statistical approximation. A violation means the summary was assembled wrong.
  if (summary.p50 > summary.p95 || summary.p95 > summary.maximum) {
    throw new TypeError(`${fieldName} percentiles must be ordered p50 <= p95 <= maximum.`);
  }
  if (summary.mean > summary.maximum) {
    throw new TypeError(`${fieldName}.mean cannot exceed ${fieldName}.maximum.`);
  }
}

function validateFullFrameEstimate(window) {
  const hasEstimate = window.estimatedFullFrameWireBytes !== undefined;
  const hasSaved = window.estimatedWireBytesSavedPercent !== undefined;

  if (hasEstimate !== hasSaved) {
    throw new TypeError(
      "windows[].estimatedFullFrameWireBytes and estimatedWireBytesSavedPercent must be present together."
    );
  }

  if (!hasEstimate) {
    // Without an observed key frame there is no measured basis, and inventing one would make a guess look
    // like data.
    if (window.keyFrameCount > 0 && window.keyFrameWireBytes > 0) {
      throw new TypeError("A window with an observed key frame must report a full-frame estimate.");
    }
    return;
  }

  requireNonNegativeInteger(window.estimatedFullFrameWireBytes, "windows[].estimatedFullFrameWireBytes");
  if (typeof window.estimatedWireBytesSavedPercent !== "number"
    || !Number.isFinite(window.estimatedWireBytesSavedPercent)) {
    throw new TypeError("windows[].estimatedWireBytesSavedPercent must be a finite number.");
  }
  // Negative is allowed and meaningful: it means tiles cost more than full frames would have.
  if (window.estimatedWireBytesSavedPercent > 100) {
    throw new TypeError("windows[].estimatedWireBytesSavedPercent cannot exceed 100.");
  }
}

function validateNextActions(report) {
  if (!Array.isArray(report.nextActions) || report.nextActions.length === 0) {
    throw new TypeError("nextActions must be a non-empty array.");
  }

  for (const action of report.nextActions) {
    requireString(action, "nextActions[]");
  }

  if (!report.didObserveFrames
    && !report.nextActions.some((action) => action.includes("app-runtime-status"))) {
    throw new TypeError(
      "a report with no observed frames must point at app-runtime-status to diagnose the stream."
    );
  }

  const droppedAnyTiles = report.windows.some((window) => {
    return DROPPED_TILE_REASONS.reduce((total, reason) => total + window.droppedTiles[reason], 0) > 0;
  });
  if (droppedAnyTiles && !report.nextActions.some((action) => action.includes("droppedTiles"))) {
    throw new TypeError("a report with dropped tiles must call them out in nextActions.");
  }
}

function requireString(value, fieldName) {
  if (typeof value !== "string" || value.length === 0) {
    throw new TypeError(`Frame pipeline field '${fieldName}' must be a non-empty string.`);
  }
}

function requireBoolean(value, fieldName) {
  if (typeof value !== "boolean") {
    throw new TypeError(`Frame pipeline field '${fieldName}' must be boolean.`);
  }
}

function requireNonNegativeInteger(value, fieldName) {
  if (!Number.isInteger(value) || value < 0) {
    throw new TypeError(`Frame pipeline field '${fieldName}' must be a non-negative integer.`);
  }
}

function requireNonNegativeNumber(value, fieldName) {
  if (typeof value !== "number" || !Number.isFinite(value) || value < 0) {
    throw new TypeError(`Frame pipeline field '${fieldName}' must be a non-negative finite number.`);
  }
}

function readStdin() {
  return readFileSync(0, "utf8");
}

function main() {
  const input = readStdin().trim();
  if (!input) {
    throw new TypeError("Expected frame pipeline report JSON on stdin.");
  }

  validateFramePipelineReport(JSON.parse(input));
  process.stdout.write("frame pipeline report valid\n");
}

if (process.argv[1] === fileURLToPath(import.meta.url)) {
  main();
}
