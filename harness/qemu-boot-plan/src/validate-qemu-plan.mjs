import { readFileSync } from "node:fs";
import { fileURLToPath } from "node:url";

const REQUIRED_SEQUENCES = [
  ["-machine", "virt,highmem=on"],
  ["-accel", "hvf"],
  ["-bios"],
  ["-boot", "order=d"],
  ["-cpu", "host"],
  ["-netdev", "user,id=net0"],
  ["-device", "virtio-net-pci,netdev=net0"],
  ["-display", "cocoa"]
];

const REQUIRED_DEVICES = [
  "usb-storage,drive=installer",
  "qemu-xhci,id=usb0",
  "virtio-blk-pci,drive=system",
  "ramfb",
  "virtio-gpu-pci",
  "usb-kbd",
  "usb-tablet"
];

export function validateQEMUPlan(plan) {
  if (!plan || typeof plan !== "object" || Array.isArray(plan)) {
    throw new TypeError("QEMU plan must be a JSON object.");
  }

  requireString(plan.kind, "kind");
  requireString(plan.provider, "provider");
  requireString(plan.executablePath, "executablePath");
  requireString(plan.firmwarePath, "firmwarePath");
  requireString(plan.summary, "summary");

  if (plan.kind !== "qemuWindowsArmBootPlan") {
    throw new TypeError(`Unsupported QEMU plan kind: ${plan.kind}`);
  }

  if (plan.provider !== "QEMU/HVF") {
    throw new TypeError("QEMU plan provider must be QEMU/HVF.");
  }

  if (plan.isServerBacked !== false) {
    throw new TypeError("QEMU plan must be local and non-server-backed.");
  }

  if (typeof plan.isExecutableAvailable !== "boolean") {
    throw new TypeError("QEMU plan field 'isExecutableAvailable' must be a boolean.");
  }

  if (typeof plan.isFirmwareAvailable !== "boolean") {
    throw new TypeError("QEMU plan field 'isFirmwareAvailable' must be a boolean.");
  }

  if (!Array.isArray(plan.arguments) || plan.arguments.length === 0) {
    throw new TypeError("QEMU plan field 'arguments' must be a non-empty array.");
  }

  for (const argument of plan.arguments) {
    requireString(argument, "arguments[]");
  }

  if (!Array.isArray(plan.warnings)) {
    throw new TypeError("QEMU plan field 'warnings' must be an array.");
  }

  for (const warning of plan.warnings) {
    requireString(warning, "warnings[]");
  }

  for (const sequence of REQUIRED_SEQUENCES) {
    if (!containsSequence(plan.arguments, sequence)) {
      throw new TypeError(`QEMU plan arguments must include sequence: ${sequence.join(" ")}`);
    }
  }

  for (const device of REQUIRED_DEVICES) {
    if (!containsSequence(plan.arguments, ["-device", device])) {
      throw new TypeError(`QEMU plan arguments must include device: ${device}`);
    }
  }

  const driveArguments = plan.arguments.filter((argument) => argument.includes("if=none,"));
  const biosIndex = plan.arguments.indexOf("-bios");
  const installerDrive = driveArguments.find((argument) => argument.includes("id=installer"));
  const systemDrive = driveArguments.find((argument) => argument.includes("id=system"));

  if (biosIndex === -1 || plan.arguments[biosIndex + 1] !== plan.firmwarePath) {
    throw new TypeError("QEMU plan must attach the declared Arm UEFI firmware with -bios.");
  }

  if (!plan.firmwarePath.endsWith("edk2-aarch64-code.fd")) {
    throw new TypeError("QEMU plan firmware must point to edk2-aarch64-code.fd.");
  }

  if (!installerDrive || !installerDrive.includes("media=cdrom") || !installerDrive.includes("readonly=on")) {
    throw new TypeError("QEMU plan must attach installer media as a read-only cdrom drive.");
  }

  if (!installerDrive.includes("file.locking=off")) {
    throw new TypeError("QEMU installer media must disable file locking for read-only ISO reuse.");
  }

  if (!systemDrive || !systemDrive.includes("format=raw")) {
    throw new TypeError("QEMU plan must attach a writable raw system disk.");
  }

  if (!installerDrive.includes(".iso")) {
    throw new TypeError("QEMU installer media should point to an ISO path.");
  }

  return plan;
}

function containsSequence(values, sequence) {
  if (values.length < sequence.length) {
    return false;
  }

  for (let index = 0; index <= values.length - sequence.length; index += 1) {
    if (sequence.every((value, offset) => values[index + offset] === value)) {
      return true;
    }
  }

  return false;
}

function requireString(value, fieldName) {
  if (typeof value !== "string" || value.length === 0) {
    throw new TypeError(`QEMU plan field '${fieldName}' must be a non-empty string.`);
  }
}

function readStdin() {
  return readFileSync(0, "utf8");
}

function main() {
  const input = readStdin().trim();
  if (!input) {
    throw new TypeError("Expected QEMU plan JSON on stdin.");
  }

  validateQEMUPlan(JSON.parse(input));
  process.stdout.write("qemu plan valid\n");
}

if (process.argv[1] === fileURLToPath(import.meta.url)) {
  main();
}
