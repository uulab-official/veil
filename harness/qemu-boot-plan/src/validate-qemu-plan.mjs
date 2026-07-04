import { readFileSync } from "node:fs";
import { fileURLToPath } from "node:url";

const REQUIRED_SEQUENCES = [
  ["-machine", "virt,highmem=on"],
  ["-accel", "hvf"],
  ["-cpu", "host"],
  ["-netdev", "user,id=net0,hostfwd=tcp::18444-:18444"],
  ["-display", "cocoa"]
];

const SUPPORTED_NETWORK_ADAPTERS = new Map([
  ["usb-net", "usb-net,netdev=net0"],
  ["e1000", "e1000,netdev=net0"],
  ["e1000e", "e1000e,netdev=net0"],
  ["rtl8139", "rtl8139,netdev=net0"],
  ["vmxnet3", "vmxnet3,netdev=net0"],
  ["virtio-net-pci", "virtio-net-pci,netdev=net0"],
  ["virtio-net-device", "virtio-net-device,netdev=net0"]
]);

const SUPPORTED_BOOT_ORDERS = new Set(["order=c", "order=d"]);

const REQUIRED_DEVICES = [
  "qemu-xhci,id=usb0",
  "nvme,drive=system,serial=veil-system",
  "virtio-rng-pci",
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
  requireString(plan.firmwareVarsTemplatePath, "firmwareVarsTemplatePath");
  requireString(plan.firmwareVarsPath, "firmwareVarsPath");
  requireString(plan.tpmEmulatorPath, "tpmEmulatorPath");
  requireString(plan.tpmStateDirectoryPath, "tpmStateDirectoryPath");
  requireString(plan.networkAdapter, "networkAdapter");
  requireString(plan.networkDeviceArgument, "networkDeviceArgument");
  requireString(plan.summary, "summary");
  if (plan.automaticInstallMediaPath != null) {
    requireString(plan.automaticInstallMediaPath, "automaticInstallMediaPath");
  }

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

  if (typeof plan.isFirmwareVarsTemplateAvailable !== "boolean") {
    throw new TypeError("QEMU plan field 'isFirmwareVarsTemplateAvailable' must be a boolean.");
  }

  if (typeof plan.isSecureBootFirmwareAvailable !== "boolean") {
    throw new TypeError("QEMU plan field 'isSecureBootFirmwareAvailable' must be a boolean.");
  }

  if (typeof plan.isTPMEmulatorAvailable !== "boolean") {
    throw new TypeError("QEMU plan field 'isTPMEmulatorAvailable' must be a boolean.");
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

  const bootIndex = plan.arguments.indexOf("-boot");
  const bootOrder = bootIndex === -1 ? undefined : plan.arguments[bootIndex + 1];
  if (!SUPPORTED_BOOT_ORDERS.has(bootOrder)) {
    throw new TypeError("QEMU plan arguments must include -boot order=c for installed disks or -boot order=d for installer media.");
  }

  const expectedNetworkDeviceArgument = SUPPORTED_NETWORK_ADAPTERS.get(plan.networkAdapter);
  if (!expectedNetworkDeviceArgument) {
    throw new TypeError(
      `QEMU plan networkAdapter must be one of: ${[...SUPPORTED_NETWORK_ADAPTERS.keys()].join(", ")}`
    );
  }

  if (plan.networkDeviceArgument !== expectedNetworkDeviceArgument) {
    throw new TypeError("QEMU plan networkDeviceArgument must match the declared networkAdapter.");
  }

  if (!containsSequence(plan.arguments, ["-device", plan.networkDeviceArgument])) {
    throw new TypeError(`QEMU plan arguments must include network device: ${plan.networkDeviceArgument}`);
  }

  if (containsSequence(plan.arguments, ["-device", "virtio-blk-pci,drive=system"])) {
    throw new TypeError("QEMU plan must attach an NVMe system disk for Windows setup inbox driver support.");
  }

  for (const device of REQUIRED_DEVICES) {
    if (!containsSequence(plan.arguments, ["-device", device])) {
      throw new TypeError(`QEMU plan arguments must include device: ${device}`);
    }
  }

  const driveArguments = plan.arguments.filter((argument) => argument.includes("if=none,"));
  const pflashDriveArguments = plan.arguments.filter((argument) => argument.includes("if=pflash,"));
  const installerDrive = driveArguments.find((argument) => argument.includes("id=installer"));
  const autoInstallDrive = driveArguments.find((argument) => argument.includes("id=autounattend"));
  const driverMediaDrive = driveArguments.find((argument) => argument.includes("id=drivers"));
  const systemDrive = driveArguments.find((argument) => argument.includes("id=system"));

  if (plan.arguments.includes("-bios")) {
    throw new TypeError("QEMU plan must attach Arm UEFI through pflash drives rather than -bios.");
  }

  const hasSecureFirmwareCode = plan.firmwarePath.endsWith("edk2-aarch64-secure-code.fd");
  const hasStandardFirmwareCode = plan.firmwarePath.endsWith("edk2-aarch64-code.fd");
  const hasSecureFirmwareVars = plan.firmwareVarsTemplatePath.endsWith("edk2-arm-secure-vars.fd");

  if (!hasStandardFirmwareCode && !hasSecureFirmwareCode) {
    throw new TypeError("QEMU plan firmware must point to edk2-aarch64-code.fd or edk2-aarch64-secure-code.fd.");
  }

  if (!plan.firmwareVarsTemplatePath.endsWith("edk2-arm-vars.fd") && !hasSecureFirmwareVars) {
    throw new TypeError("QEMU plan firmware vars template must point to edk2-arm-vars.fd or edk2-arm-secure-vars.fd.");
  }

  if (plan.isSecureBootFirmwareAvailable && (!hasSecureFirmwareCode || !hasSecureFirmwareVars)) {
    throw new TypeError("QEMU plan Secure Boot firmware availability requires edk2-aarch64-secure-code.fd and edk2-arm-secure-vars.fd.");
  }

  if (!plan.firmwareVarsPath.endsWith("uefi-vars.fd")) {
    throw new TypeError("QEMU plan firmware vars store must point to Veil's uefi-vars.fd.");
  }

  if (!pflashDriveArguments.some((argument) => argument === `if=pflash,format=raw,readonly=on,file=${plan.firmwarePath}`)
    || !pflashDriveArguments.some((argument) => argument === `if=pflash,format=raw,file=${plan.firmwareVarsPath}`)) {
    throw new TypeError("QEMU plan must attach Arm UEFI code and writable vars as pflash drives.");
  }

  if (!containsSequence(plan.arguments, ["-tpmdev", "emulator,id=tpm0,chardev=chrtpm"])
    || !containsSequence(plan.arguments, ["-device", "tpm-tis-device,tpmdev=tpm0"])) {
    throw new TypeError("QEMU plan must attach a TPM 2.0 emulator.");
  }

  const chardevIndex = plan.arguments.indexOf("-chardev");
  if (chardevIndex === -1
    || !plan.arguments[chardevIndex + 1]?.includes("socket,id=chrtpm")
    || !plan.arguments[chardevIndex + 1]?.includes(`${plan.tpmStateDirectoryPath}/swtpm.sock`)) {
    throw new TypeError("QEMU plan must attach the TPM chardev socket in the declared TPM state directory.");
  }

  if (!systemDrive || !systemDrive.includes("format=raw")) {
    throw new TypeError("QEMU plan must attach a writable raw system disk.");
  }

  if (bootOrder === "order=d" && !installerDrive) {
    throw new TypeError("QEMU installer boot plans must attach installer media as a read-only cdrom drive.");
  }

  if (installerDrive) {
    if (!installerDrive.includes("media=cdrom") || !installerDrive.includes("readonly=on")) {
      throw new TypeError("QEMU plan must attach installer media as a read-only cdrom drive.");
    }

    if (!installerDrive.includes("file.locking=off")) {
      throw new TypeError("QEMU installer media must disable file locking for read-only ISO reuse.");
    }

    if (!containsSequence(plan.arguments, ["-device", "usb-storage,drive=installer"])) {
      throw new TypeError("QEMU installer media drive must be exposed as USB mass storage.");
    }
  }

  if (plan.automaticInstallMediaPath != null) {
    if (!autoInstallDrive || !autoInstallDrive.includes("media=cdrom") || !autoInstallDrive.includes("readonly=on")) {
      throw new TypeError("QEMU plan must attach automatic install media as a read-only cdrom drive.");
    }

    if (!autoInstallDrive.includes(plan.automaticInstallMediaPath)) {
      throw new TypeError("QEMU automatic install drive must point to the declared automatic install media path.");
    }

    if (!containsSequence(plan.arguments, ["-device", "usb-storage,drive=autounattend"])) {
      throw new TypeError("QEMU automatic install media drive must be exposed as USB mass storage.");
    }
  } else if (autoInstallDrive || containsSequence(plan.arguments, ["-device", "usb-storage,drive=autounattend"])) {
    throw new TypeError("QEMU plan must not attach automatic install media when automaticInstallMediaPath is absent.");
  }

  if (driverMediaDrive) {
    if (!driverMediaDrive.includes("media=cdrom") || !driverMediaDrive.includes("readonly=on")) {
      throw new TypeError("QEMU driver media must attach as a read-only cdrom drive.");
    }

    if (!containsSequence(plan.arguments, ["-device", "usb-storage,drive=drivers"])) {
      throw new TypeError("QEMU driver media drive must be exposed as USB mass storage.");
    }
  }

  if (plan.automaticInstallMediaPath != null && !plan.automaticInstallMediaPath.endsWith("VeilAutoInstall.iso")) {
    throw new TypeError("QEMU automatic install media must point to VeilAutoInstall.iso.");
  }

  if (installerDrive && !installerDrive.includes(".iso")) {
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
