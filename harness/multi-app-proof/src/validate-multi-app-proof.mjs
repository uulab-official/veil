import { readFileSync } from "node:fs";
import { fileURLToPath } from "node:url";

const TARGET_APP_IDS = ["winapp_notepad", "winapp_calculator", "winapp_paint"];
const FRESH_FRAME_BUDGET_MILLISECONDS = 1000;
const STALE_FRAME_TIMEOUT_MILLISECONDS = 5000;

export function validateMultiAppProof(report, options = {}) {
  const requireComplete = Boolean(options.requireComplete);
  if (!report || typeof report !== "object" || Array.isArray(report)) {
    throw new TypeError("Multi-app proof report must be a JSON object.");
  }

  requireString(report.kind, "kind");
  if (report.kind !== "windowsMultiAppProof") {
    throw new TypeError(`Unsupported multi-app proof kind: ${report.kind}`);
  }
  requireString(report.endpoint, "endpoint");
  if (!report.endpoint.startsWith("ws://")) {
    throw new TypeError("endpoint must be a WebSocket URL.");
  }
  requireIsoDate(report.provedAt, "provedAt");
  requireString(report.proofDirectory, "proofDirectory");
  requireJsonPath(report.aggregateReportPath, "aggregateReportPath");
  requireString(report.proofKind, "proofKind");
  if (report.proofKind !== "coherence") {
    throw new TypeError("proofKind must be coherence.");
  }
  requireInteger(report.waitSeconds, "waitSeconds");
  if (report.waitSeconds < 1 || report.waitSeconds > 60) {
    throw new TypeError("waitSeconds must be between 1 and 60.");
  }

  validateStringArray(report.appIds, "appIds", { exactLength: undefined });
  if (report.appIds.length === 0) {
    throw new TypeError("appIds must include at least one app.");
  }
  validateNoDuplicates(report.appIds, "appIds");
  validateStringArray(report.targetAppIds, "targetAppIds", { exactLength: TARGET_APP_IDS.length });
  if (report.targetAppIds.join(",") !== TARGET_APP_IDS.join(",")) {
    throw new TypeError(`targetAppIds must be ${TARGET_APP_IDS.join(",")}.`);
  }

  if (!Array.isArray(report.results) || report.results.length !== report.appIds.length) {
    throw new TypeError("results must contain one entry per appIds entry.");
  }

  let provedCount = 0;
  let failedCount = 0;
  report.results.forEach((result, index) => {
    validateResult(result, report.appIds[index]);
    if (result.status === "proved") {
      provedCount += 1;
    } else {
      failedCount += 1;
    }
  });

  requireInteger(report.provedAppCount, "provedAppCount");
  requireInteger(report.failedAppCount, "failedAppCount");
  if (report.provedAppCount !== provedCount) {
    throw new TypeError("provedAppCount must match proved results.");
  }
  if (report.failedAppCount !== failedCount) {
    throw new TypeError("failedAppCount must match failed results.");
  }

  requireString(report.coverageHealth, "coverageHealth");
  const expectedCoverageHealth = provedCount === report.appIds.length
    ? "complete"
    : provedCount > 0
      ? "partial"
      : "missing";
  if (report.coverageHealth !== expectedCoverageHealth) {
    throw new TypeError(`coverageHealth must be ${expectedCoverageHealth}.`);
  }
  if (requireComplete && report.coverageHealth !== "complete") {
    throw new TypeError("coverageHealth must be complete when --require-complete is used.");
  }

  validateNextActions(report.nextActions, report.aggregateReportPath, report.coverageHealth);
  return report;
}

function validateResult(result, expectedAppId) {
  if (!result || typeof result !== "object" || Array.isArray(result)) {
    throw new TypeError("results[] must be an object.");
  }
  requireString(result.appId, "results[].appId");
  if (result.appId !== expectedAppId) {
    throw new TypeError("results[].appId must match the appIds order.");
  }
  requireString(result.status, "results[].status");
  if (!["proved", "failed"].includes(result.status)) {
    throw new TypeError("results[].status must be proved or failed.");
  }
  requireString(result.proofKind, "results[].proofKind");
  if (result.proofKind !== "coherence") {
    throw new TypeError("results[].proofKind must be coherence.");
  }

  if (result.status === "proved") {
    requireJsonPath(result.proofPath, "results[].proofPath");
    validateLatency(result);
    requireString(result.windowId, "results[].windowId");
    if (!/^hwnd:[0-9A-Fa-f]+$/.test(result.windowId)) {
      throw new TypeError("results[].windowId must be an hwnd id.");
    }
    requireString(result.windowTitle, "results[].windowTitle");
    if (result.errorMessage !== undefined && result.errorMessage !== null) {
      throw new TypeError("proved results must not include errorMessage.");
    }
  } else {
    requireString(result.errorMessage, "results[].errorMessage");
    if (result.proofPath !== undefined && result.proofPath !== null) {
      throw new TypeError("failed results must not include proofPath.");
    }
  }
}

function validateLatency(result) {
  requireString(result.latencyHealth, "results[].latencyHealth");
  requireString(result.slowestLatencyMeasurement, "results[].slowestLatencyMeasurement");
  requireInteger(result.slowestLatencyMilliseconds, "results[].slowestLatencyMilliseconds");
  requireInteger(result.latencyBudgetMilliseconds, "results[].latencyBudgetMilliseconds");
  requireInteger(result.staleTimeoutMilliseconds, "results[].staleTimeoutMilliseconds");
  requireString(result.latencyRecommendedAction, "results[].latencyRecommendedAction");
  if (result.latencyBudgetMilliseconds !== FRESH_FRAME_BUDGET_MILLISECONDS) {
    throw new TypeError(`results[].latencyBudgetMilliseconds must be ${FRESH_FRAME_BUDGET_MILLISECONDS}.`);
  }
  if (result.staleTimeoutMilliseconds !== STALE_FRAME_TIMEOUT_MILLISECONDS) {
    throw new TypeError(`results[].staleTimeoutMilliseconds must be ${STALE_FRAME_TIMEOUT_MILLISECONDS}.`);
  }

  const expectedHealth = result.slowestLatencyMilliseconds <= result.latencyBudgetMilliseconds
    ? "healthy"
    : result.slowestLatencyMilliseconds <= result.staleTimeoutMilliseconds
      ? "delayed"
      : "stale";
  const expectedAction = result.slowestLatencyMilliseconds <= result.latencyBudgetMilliseconds
    ? "none"
    : result.slowestLatencyMilliseconds <= result.staleTimeoutMilliseconds
      ? "measure-again"
      : "tune-frame-latency";
  if (result.latencyHealth !== expectedHealth) {
    throw new TypeError(`results[].latencyHealth must be ${expectedHealth}.`);
  }
  if (result.latencyRecommendedAction !== expectedAction) {
    throw new TypeError(`results[].latencyRecommendedAction must be ${expectedAction}.`);
  }
}

function validateNextActions(actions, aggregateReportPath, coverageHealth) {
  if (!Array.isArray(actions) || actions.length === 0) {
    throw new TypeError("nextActions must be a non-empty array.");
  }
  for (const action of actions) {
    requireString(action, "nextActions[]");
  }
  if (!actions.some((action) => action.includes("app-runtime-status"))) {
    throw new TypeError("nextActions must include app-runtime-status verification.");
  }
  if (!actions.some((action) => action.includes(aggregateReportPath))) {
    throw new TypeError("nextActions must reference aggregateReportPath.");
  }
  if (coverageHealth !== "complete" && !actions.some((action) => action.includes("multi-app-proof"))) {
    throw new TypeError("incomplete coverage must include a multi-app-proof retry action.");
  }
}

function validateStringArray(value, fieldName, options = {}) {
  if (!Array.isArray(value)) {
    throw new TypeError(`${fieldName} must be an array.`);
  }
  if (options.exactLength !== undefined && value.length !== options.exactLength) {
    throw new TypeError(`${fieldName} must contain ${options.exactLength} entries.`);
  }
  for (const item of value) {
    requireString(item, `${fieldName}[]`);
  }
}

function validateNoDuplicates(values, fieldName) {
  if (new Set(values).size !== values.length) {
    throw new TypeError(`${fieldName} must not contain duplicates.`);
  }
}

function requireJsonPath(value, fieldName) {
  requireString(value, fieldName);
  if (!value.endsWith(".json")) {
    throw new TypeError(`${fieldName} must point to a JSON artifact.`);
  }
}

function requireIsoDate(value, fieldName) {
  requireString(value, fieldName);
  if (Number.isNaN(Date.parse(value))) {
    throw new TypeError(`${fieldName} must be an ISO date.`);
  }
}

function requireString(value, fieldName) {
  if (typeof value !== "string" || value.length === 0) {
    throw new TypeError(`Multi-app proof field '${fieldName}' must be a non-empty string.`);
  }
}

function requireInteger(value, fieldName) {
  if (!Number.isInteger(value)) {
    throw new TypeError(`Multi-app proof field '${fieldName}' must be an integer.`);
  }
}

function readStdin() {
  return readFileSync(0, "utf8");
}

if (process.argv[1] === fileURLToPath(import.meta.url)) {
  const input = readStdin();
  const report = JSON.parse(input);
  validateMultiAppProof(report, {
    requireComplete: process.argv.includes("--require-complete")
  });
  process.stdout.write("multi-app proof ok\n");
}
