#!/usr/bin/env node
import { readFileSync } from "node:fs";

export function validatePrinterBridgePlan(plan) {
  requireObject(plan, "plan");
  requireString(plan.kind, "kind");
  if (plan.kind !== "windowsPrinterBridgePlan") {
    throw new TypeError("kind must be windowsPrinterBridgePlan.");
  }

  requireString(plan.generatedAt, "generatedAt");
  requireString(plan.mode, "mode");
  requireString(plan.hostAddress, "hostAddress");
  requireNumber(plan.ippPort, "ippPort");
  requireString(plan.sharedPrinterName, "sharedPrinterName");
  requireString(plan.windowsPrinterName, "windowsPrinterName");
  requireString(plan.ippEndpoint, "ippEndpoint");
  requireString(plan.macOSSharingHint, "macOSSharingHint");
  requireString(plan.windowsAddPrinterCommand, "windowsAddPrinterCommand");
  requireString(plan.windowsVerifyPrinterCommand, "windowsVerifyPrinterCommand");
  requireString(plan.manualTestPageInstruction, "manualTestPageInstruction");
  requireArray(plan.setupSteps, "setupSteps");
  requireArray(plan.verificationSteps, "verificationSteps");
  requireArray(plan.limitations, "limitations");
  requireArray(plan.nextActions, "nextActions");

  if (plan.mode !== "manual-ipp-experiment") {
    throw new TypeError("mode must stay manual-ipp-experiment until live printer proof exists.");
  }
  if (plan.hostAddress !== "10.0.2.2") {
    throw new TypeError("hostAddress must use the QEMU user-network host address 10.0.2.2.");
  }
  if (plan.ippPort !== 631) {
    throw new TypeError("ippPort must use IPP port 631.");
  }
  if (!plan.ippEndpoint.startsWith("http://10.0.2.2:631/printers/")) {
    throw new TypeError("ippEndpoint must use the QEMU host IPP printer path.");
  }
  if (!plan.macOSSharingHint.includes("Printer Sharing")
    || !plan.macOSSharingHint.includes(plan.sharedPrinterName)) {
    throw new TypeError("macOSSharingHint must explain macOS Printer Sharing for the shared printer.");
  }
  if (!plan.windowsAddPrinterCommand.includes("Add-Printer")
    || !plan.windowsAddPrinterCommand.includes("-IppURL")
    || !plan.windowsAddPrinterCommand.includes(plan.ippEndpoint)
    || !plan.windowsAddPrinterCommand.includes(plan.windowsPrinterName)) {
    throw new TypeError("windowsAddPrinterCommand must add the IPP endpoint with Add-Printer -IppURL.");
  }
  if (!plan.windowsVerifyPrinterCommand.includes("Get-Printer")
    || !plan.windowsVerifyPrinterCommand.includes(plan.windowsPrinterName)) {
    throw new TypeError("windowsVerifyPrinterCommand must verify the named Windows printer with Get-Printer.");
  }
  if (!plan.manualTestPageInstruction.toLowerCase().includes("test page")) {
    throw new TypeError("manualTestPageInstruction must require a Windows test page.");
  }
  if (!plan.setupSteps.some((step) => step.includes("windowsAddPrinterCommand"))) {
    throw new TypeError("setupSteps must reference the generated Windows add-printer command.");
  }
  if (!plan.verificationSteps.some((step) => step.includes("windowsVerifyPrinterCommand"))) {
    throw new TypeError("verificationSteps must reference the generated Windows verify command.");
  }
  if (!plan.limitations.some((item) => item.includes("manual IPP experiment"))
    || !plan.limitations.some((item) => item.includes("real Windows test page proof"))) {
    throw new TypeError("limitations must prevent claiming automatic printer support before live proof.");
  }
  if (!plan.nextActions.some((action) => action.includes("veil-vmctl printer-bridge-plan"))
    || !plan.nextActions.some((action) => action.includes("Add-Printer"))
    || !plan.nextActions.some((action) => action.includes("test-page evidence"))) {
    throw new TypeError("nextActions must cover plan generation, Windows Add-Printer, and test-page evidence.");
  }

  return plan;
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

function requireNumber(value, name) {
  if (typeof value !== "number" || !Number.isFinite(value)) {
    throw new TypeError(`${name} must be a finite number.`);
  }
}

if (import.meta.url === `file://${process.argv[1]}`) {
  const input = readFileSync(0, "utf8");
  validatePrinterBridgePlan(JSON.parse(input));
}
