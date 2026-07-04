import { readFileSync } from "node:fs";
import { describe, it } from "node:test";
import assert from "node:assert/strict";

import { validateQEMUPlan } from "../src/validate-qemu-plan.mjs";

const fixture = JSON.parse(
  readFileSync(new URL("../fixtures/windows-arm-install-plan.json", import.meta.url), "utf8")
);

describe("QEMU boot plan harness", () => {
  it("accepts the Windows Arm install plan fixture", () => {
    assert.equal(validateQEMUPlan(fixture), fixture);
  });

  it("accepts an installed Windows disk-first boot plan", () => {
    const plan = {
      ...fixture,
      summary: "Dry-run QEMU/HVF command plan for Windows 11 Arm. Windows boots from the installed system disk; installer media is not attached.",
      arguments: fixture.arguments
        .map((argument) => argument === "order=d" ? "order=c" : argument)
        .filter((argument) => !argument.includes("id=installer") && argument !== "usb-storage,drive=installer")
    };

    assert.equal(validateQEMUPlan(plan), plan);
  });

  it("accepts an installed Windows plan after guest agent media is no longer attached", () => {
    const plan = {
      ...fixture,
      automaticInstallMediaPath: null,
      summary: "Dry-run QEMU/HVF command plan for Windows 11 Arm. Windows boots from the installed system disk; installer media is not attached.",
      arguments: fixture.arguments
        .map((argument) => argument === "order=d" ? "order=c" : argument)
        .filter((argument) =>
          !argument.includes("id=installer")
            && !argument.includes("id=autounattend")
            && argument !== "usb-storage,drive=installer"
            && argument !== "usb-storage,drive=autounattend"
        )
    };

    assert.equal(validateQEMUPlan(plan), plan);
  });

  it("accepts Secure Boot firmware when secure code and vars are paired", () => {
    const plan = {
      ...fixture,
      isSecureBootFirmwareAvailable: true,
      firmwarePath: "/opt/homebrew/share/qemu/edk2-aarch64-secure-code.fd",
      firmwareVarsTemplatePath: "/Users/test/Library/Application Support/Veil/Firmware/edk2-arm-secure-vars.fd",
      arguments: fixture.arguments.map((argument) =>
        argument === `if=pflash,format=raw,readonly=on,file=${fixture.firmwarePath}`
          ? "if=pflash,format=raw,readonly=on,file=/opt/homebrew/share/qemu/edk2-aarch64-secure-code.fd"
          : argument
      )
    };

    assert.equal(validateQEMUPlan(plan), plan);
  });

  it("accepts optional read-only driver media", () => {
    const plan = {
      ...fixture,
      arguments: [
        ...fixture.arguments,
        "-drive",
        "driver=raw,file.driver=file,file.locking=off,file.filename=/Users/test/Downloads/virtio-win.iso,if=none,id=drivers,media=cdrom,readonly=on",
        "-device",
        "usb-storage,drive=drivers"
      ]
    };

    assert.equal(validateQEMUPlan(plan), plan);
  });

  it("accepts a declared alternate network adapter", () => {
    const plan = {
      ...fixture,
      networkAdapter: "e1000e",
      networkDeviceArgument: "e1000e,netdev=net0",
      arguments: fixture.arguments.map((argument) =>
        argument === "usb-net,netdev=net0" ? "e1000e,netdev=net0" : argument
      )
    };

    assert.equal(validateQEMUPlan(plan), plan);
  });

  it("rejects a network adapter declaration that does not match QEMU arguments", () => {
    const plan = {
      ...fixture,
      networkAdapter: "e1000e",
      networkDeviceArgument: "e1000e,netdev=net0"
    };

    assert.throws(() => validateQEMUPlan(plan), /network device: e1000e,netdev=net0/);
  });

  it("rejects writable driver media", () => {
    const plan = {
      ...fixture,
      arguments: [
        ...fixture.arguments,
        "-drive",
        "driver=raw,file.driver=file,file.locking=off,file.filename=/Users/test/Downloads/virtio-win.iso,if=none,id=drivers,media=cdrom",
        "-device",
        "usb-storage,drive=drivers"
      ]
    };

    assert.throws(() => validateQEMUPlan(plan), /driver media.*read-only cdrom/);
  });

  it("rejects plans that are not local", () => {
    assert.throws(
      () => validateQEMUPlan({ ...fixture, isServerBacked: true }),
      /non-server-backed/
    );
  });

  it("rejects plans without HVF acceleration", () => {
    const plan = {
      ...fixture,
      arguments: fixture.arguments.filter((argument) => argument !== "hvf")
    };

    assert.throws(() => validateQEMUPlan(plan), /-accel hvf/);
  });

  it("rejects plans without read-only installer media", () => {
    const plan = {
      ...fixture,
      arguments: fixture.arguments.map((argument) =>
        argument.includes("id=installer")
          ? "driver=raw,file.driver=file,file.locking=off,file.filename=/Users/test/Downloads/Win11.iso,if=none,id=installer,media=disk"
          : argument
      )
    };

    assert.throws(() => validateQEMUPlan(plan), /read-only cdrom/);
  });

  it("rejects plans without declared Arm UEFI pflash drives", () => {
    const plan = {
      ...fixture,
      arguments: fixture.arguments.filter((argument) =>
        !argument.includes("if=pflash") && argument !== "-drive"
      )
    };

    assert.throws(() => validateQEMUPlan(plan), /pflash/);
  });

  it("rejects legacy -bios firmware attachment", () => {
    const plan = {
      ...fixture,
      arguments: [
        ...fixture.arguments.filter((argument) => !argument.includes("if=pflash")),
        "-bios",
        fixture.firmwarePath
      ]
    };

    assert.throws(() => validateQEMUPlan(plan), /rather than -bios/);
  });

  it("rejects Secure Boot availability without secure code and vars", () => {
    const plan = {
      ...fixture,
      isSecureBootFirmwareAvailable: true,
      firmwarePath: "/opt/homebrew/share/qemu/edk2-aarch64-code.fd",
      firmwareVarsTemplatePath: "/opt/homebrew/share/qemu/edk2-arm-vars.fd"
    };

    assert.throws(() => validateQEMUPlan(plan), /Secure Boot firmware availability/);
  });

  it("rejects plans without guest agent port forwarding", () => {
    const plan = {
      ...fixture,
      arguments: fixture.arguments.map((argument) =>
        argument === "user,id=net0,hostfwd=tcp::18444-:18444" ? "user,id=net0" : argument
      )
    };

    assert.throws(() => validateQEMUPlan(plan), /hostfwd=tcp::18444-:18444/);
  });

  it("rejects plans without TPM 2.0 emulator devices", () => {
    const plan = {
      ...fixture,
      arguments: fixture.arguments.filter((argument) =>
        !argument.includes("chrtpm") && !argument.includes("tpm0")
      )
    };

    assert.throws(() => validateQEMUPlan(plan), /TPM 2.0 emulator/);
  });

  it("rejects VirtIO block as the install-time system disk", () => {
    const plan = {
      ...fixture,
      arguments: fixture.arguments.map((argument) =>
        argument === "nvme,drive=system,serial=veil-system"
          ? "virtio-blk-pci,drive=system"
          : argument
      )
    };

    assert.throws(() => validateQEMUPlan(plan), /NVMe system disk/);
  });
});
