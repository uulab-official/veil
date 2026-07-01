import { readFileSync } from "node:fs";
import { fileURLToPath } from "node:url";

const VALID_KINDS = new Set(["appleVirtualization", "qemuHypervisor"]);
const VALID_STATUS = new Set(["active", "planned", "unavailable"]);

export function validateProviderOutput(providers) {
  if (!Array.isArray(providers)) {
    throw new TypeError("Provider output must be a JSON array.");
  }

  if (providers.length < 2) {
    throw new TypeError("Provider output must include Apple Virtualization and QEMU/HVF candidates.");
  }

  const kinds = providers.map((provider) => provider.kind);
  if (!kinds.includes("appleVirtualization")) {
    throw new TypeError("Provider output must include appleVirtualization.");
  }

  if (!kinds.includes("qemuHypervisor")) {
    throw new TypeError("Provider output must include qemuHypervisor.");
  }

  for (const provider of providers) {
    validateProvider(provider);
  }

  return providers;
}

export function validateProvider(provider) {
  if (!provider || typeof provider !== "object" || Array.isArray(provider)) {
    throw new TypeError("Provider entry must be an object.");
  }

  requireString(provider.kind, "kind");
  requireString(provider.displayName, "displayName");
  requireString(provider.mode, "mode");
  requireString(provider.acceleration, "acceleration");
  requireString(provider.status, "status");
  requireString(provider.detail, "detail");

  if (!VALID_KINDS.has(provider.kind)) {
    throw new TypeError(`Unsupported provider kind: ${provider.kind}`);
  }

  if (!VALID_STATUS.has(provider.status)) {
    throw new TypeError(`Unsupported provider status: ${provider.status}`);
  }

  if (provider.isServerBacked !== false) {
    throw new TypeError(`${provider.kind} must be marked as a local, non-server-backed provider.`);
  }

  if (provider.executablePath !== undefined) {
    requireString(provider.executablePath, "executablePath");
  }
}

function requireString(value, fieldName) {
  if (typeof value !== "string" || value.length === 0) {
    throw new TypeError(`Provider field '${fieldName}' must be a non-empty string.`);
  }
}

function readStdin() {
  return readFileSync(0, "utf8");
}

function main() {
  const input = readStdin().trim();
  if (!input) {
    throw new TypeError("Expected provider JSON on stdin.");
  }

  validateProviderOutput(JSON.parse(input));
  process.stdout.write("provider output valid\n");
}

if (process.argv[1] === fileURLToPath(import.meta.url)) {
  main();
}
