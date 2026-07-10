#!/usr/bin/env node
import { readFileSync } from "node:fs";

export function validatePrinterBridgeProof(report) {
  requireObject(report, "report");
  requireString(report.kind, "kind");
  if (report.kind !== "windowsPrinterBridgeProof") {
    throw new TypeError("kind must be windowsPrinterBridgeProof.");
  }

  requireString(report.status, "status");
  if (report.status !== "proved") {
    throw new TypeError("status must be proved.");
  }
  requireString(report.provedAt, "provedAt");
  if (Number.isNaN(Date.parse(report.provedAt))) {
    throw new TypeError("provedAt must be an ISO date.");
  }
  requireString(report.evidencePath, "evidencePath");
  requireString(report.evidenceFileName, "evidenceFileName");
  requireNonNegativeInteger(report.evidenceByteCount, "evidenceByteCount");
  if (report.evidenceModifiedAt !== undefined) {
    requireString(report.evidenceModifiedAt, "evidenceModifiedAt");
    if (Number.isNaN(Date.parse(report.evidenceModifiedAt))) {
      throw new TypeError("evidenceModifiedAt must be an ISO date.");
    }
  }
  requireObject(report.plan, "plan");
  validatePlan(report.plan);
  requireArray(report.nextActions, "nextActions");

  if (report.savedProofPath !== undefined) {
    requireString(report.savedProofPath, "savedProofPath");
    if (!report.savedProofPath.endsWith(".json")
      || !report.savedProofPath.includes("/Printer Proof/")) {
      throw new TypeError("savedProofPath must point to a Printer Proof JSON file.");
    }
  }
  if (!report.nextActions.some((action) => action.includes("latestPrinterBridgeProofPath"))
    || !report.nextActions.some((action) => action.includes("does not copy printer output"))
    || !report.nextActions.some((action) => action.includes("manual-ipp-experiment"))) {
    throw new TypeError("nextActions must preserve status, privacy, and manual experiment guidance.");
  }

  return report;
}

function validatePlan(plan) {
  requireString(plan.kind, "plan.kind");
  if (plan.kind !== "windowsPrinterBridgePlan") {
    throw new TypeError("plan.kind must be windowsPrinterBridgePlan.");
  }
  requireString(plan.mode, "plan.mode");
  if (plan.mode !== "manual-ipp-experiment") {
    throw new TypeError("plan.mode must stay manual-ipp-experiment.");
  }
  requireString(plan.sharedPrinterName, "plan.sharedPrinterName");
  requireString(plan.windowsPrinterName, "plan.windowsPrinterName");
  requireString(plan.ippEndpoint, "plan.ippEndpoint");
  if (!plan.ippEndpoint.startsWith("http://10.0.2.2:631/printers/")) {
    throw new TypeError("plan.ippEndpoint must use the QEMU host IPP printer path.");
  }
}

function requireObject(value, name) {
  if (!value || typeof value !== "object" || Array.isArray(value)) {
    throw new TypeError(`${name} must be an object.`);
  }
}

function requireArray(value, name) {
  if (!Array.isArray(value) || value.length === 0) {
    throw new TypeError(`${name} must be a non-empty array.`);
  }
}

function requireString(value, name) {
  if (typeof value !== "string" || value.trim() === "") {
    throw new TypeError(`${name} must be a non-empty string.`);
  }
}

function requireNonNegativeInteger(value, name) {
  if (!Number.isInteger(value) || value < 0) {
    throw new TypeError(`${name} must be a non-negative integer.`);
  }
}

if (import.meta.url === `file://${process.argv[1]}`) {
  const input = readFileSync(0, "utf8");
  validatePrinterBridgeProof(JSON.parse(input));
}
