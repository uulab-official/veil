# Triton (UTM) DirectX 11 Acceleration, Evaluation

Date: 2026-11-10

Status: **interim**. Licensing, source analysis and the host-side build are done, and the built
QEMU passes a headless smoke test. Booting the existing VM on it, installing the guest driver and
the present-rate measurements are **not done yet**: they need a short stop of the user's VM, which
the user is told about first. (The build was first refused by the session's permission policy and
ran after the user allowed it.)

Source: <https://blog.getutm.app/2026/introducing-triton-directx-11-driver-for-qemu/> (2026-07-24).

## Question

DWM in the Windows 11 Arm guest presents only about 25-28 times a second while drawing in Paint,
because the guest has no GPU (bundled QEMU 11.1.3, `virtio-gpu-pci` 2D, viogpudo, WARP). The agent
itself handles a changed frame in about 8 ms. Can Triton (guest D3D11 UMD + KMD over Neptune on
virtio-gpu, host virglrenderer + DXMT) lift DWM to 60-120 presents a second, and should Veil adopt it?

## How Triton Works (from the post)

- Guest: Triton is a D3D11 **DDI** user-mode driver. It turns DDI calls back into D3D11 API calls,
  rebuilds the DXContainer metadata around the DXBC bytecode (the post calls this "the weakest and
  most error prone part"), and serializes the calls with the Neptune UMD into a ring buffer owned by
  the KMD (`viogpu3d.sys`, based on anonymix007's Venus KMD).
- Host: QEMU (`utmapp/qemu` `utm-edition`) hands Neptune commands to virglrenderer
  (`macos-next`), which runs one `virgl_render_server` process per guest context. The Neptune host
  module calls a native D3D11 implementation: DXMT (`libdxmt-native.dylib`, arm64) or D3DMetal
  (x86_64 under Rosetta, not redistributable).
- DWM works because shared textures cross render-server processes as linear `shm_open` buffers
  mapped as `MTLBuffer`s (Apple Silicon UMA), and cross-process fences are emulated: the producer
  writes a timeline value with `ClearUnorderedAccessViewUint`, the consumer **spin-polls it on the
  CPU**. The post notes this adds latency per completed frame.
- Devices: `-device virtio-ramfb-gl,hostmem=8G,blob=true,venus=true,neptune=true` (UTM fork only;
  vanilla QEMU needs `ramfb` for install, then `virtio-gpu-gl-pci`) and
  `-accel hvf,ipa-granule-size=0x1000` (4 KiB required for Venus, optional for Neptune).
- Display: the post runs `-display cocoa,gl=es`.
- Guest drivers: `osy/kvm-guest-drivers-windows` releases. Latest is **v0.5** (2026-10-29,
  `viogpu3d-arm64x-signed.zip`, 2.1 MB, plus a UTM guest tools ISO). The author warns the drivers
  are "very unstable" and should not be installed on a VM you care about.

## Checklist

### 1. Read architecture and build steps

- [x] Read. Build order: ANGLE (WebKit fork, pinned `6a7f4640`) → libepoxy (`macos-venus`) →
      DXMT native (needs **LLVM 15 exactly**) → virglrenderer arm64 (`-Dvenus -Dneptune
      -Drender-server-worker=process`) → QEMU `utm-edition` (`--target-list=aarch64-softmmu`).
      The x86_64 render-server slice and lipo step are only for D3DMetal and can be skipped for a
      DXMT-only build (`NPT_BACKEND=dxmt`).

### 2. Build the host side (scratch prefix `~/VeilTriton/prefix`, outside `dist/`)

- [x] Sources cloned to `~/VeilTriton/src` (shallow):

  | Repo | Branch | Commit |
  |---|---|---|
  | utmapp/qemu | utm-edition | `2934963d1778e4d74ac2f667820cf81c914ff0f5` (2026-10-28) |
  | utmapp/virglrenderer | macos-next | `b6c4d36e12409fa92eeef4d40322c75292f10bb9` (2026-10-27) |
  | utmapp/libepoxy | macos-venus | `15d904dcb1d5a8d626ffe11e8f3339499d6f7b09` (2026-02-22) |
  | utmapp/dxmt | main | `8b9d33470d6417734bf156d87d265ca2ede0aaa8` (2026-10-19) |
  | utmapp/WebKit (ANGLE only) | — | `6a7f464047e2f6f2b65fe315aaad5d1ff3229cb7` |

- [x] **LLVM 15.0.7** from source into `~/VeilTriton/llvm15` (arm64, no targets, no tools), because
      `brew install llvm@15` fails on macOS 27.0.1 ("unsatisfied requirement", Tier 3).
- [x] **ANGLE** (`xcodebuild archive`). Needed two build-setting overrides on Xcode 27.2:
      `MACOSX_DEPLOYMENT_TARGET=12.0` (11.0 is below the SDK's supported range) and `-Wno-error`
      (new `-Wunnecessary-virtual-specifier` warning in `src/libANGLE/Fence.h`).
- [x] **libepoxy** (`-Degl=yes -Dx11=false`).
- [x] **virglrenderer** arm64 with `-Dvenus=false -Dneptune=true -Drender-server-worker=process`
      (needs Python `PyYAML`; a venv at `~/VeilTriton/venv`). Venus is off: it needs Vulkan/MoltenVK
      and Triton does not use it. The x86_64/D3DMetal slice is skipped.
- [x] **DXMT** native (`libdxmt-native.dylib`, `-Dnative_llvm_path=~/VeilTriton/llvm15`).
- [x] **QEMU** `utm-edition` with `--disable-pvg --disable-docs`: `apple-gfx.m` no longer compiles
      against the macOS 27 SDK (`PGTask_t` obsoleted). Configure reports virglrenderer 1.3.0 with
      `VIRGL_RENDERER_NEPTUNE`, OpenGL (epoxy) 1.5.11, GBM no.
- [x] **Local patch for a windowless GL display** (`ui/egl-helpers.c`, `ui/egl-headless.c`,
      `ui/meson.build`, 18 lines): `egl_init` on macOS uses the fork's existing
      `qemu_egl_init_dpy_cocoa` (ANGLE on Metal, no window) instead of a GBM render node, the
      `egl-headless` module builds without GBM on Darwin, and Metal-native scanouts are ignored by
      the headless reader instead of being read as a GL texture id.
- [x] Smoke test (no disk, no VM state): `-accel hvf,ipa-granule-size=0x1000 -device
      virtio-ramfb-gl,hostmem=1G,blob=true,venus=false,neptune=true -display egl-headless,gl=es
      -vnc 127.0.0.1:9` realizes the device, shows the UEFI shell through `screendump`, opens no Mac
      window, and quits cleanly over QMP. The Neptune path itself is not exercised until a guest
      driver talks to it.
- Host toolchain present: meson, ninja, pkg-config, cmake, Xcode 27.2 with the Metal toolchain
  (`metal` 32023.922).

### 3. Licenses, and whether Veil may ship each piece

| Component | License | Shipping inside Veil.app |
|---|---|---|
| utmapp/qemu (utm-edition) | GPL-2.0 (whole emulator; files may be GPL-compatible) | Yes, same obligations as today's bundled QEMU 11.1.3: ship license, offer exact corresponding source (the fork's commit plus any Veil patches). |
| utmapp/virglrenderer | MIT ("derived from mesa in many parts") | Yes, keep notice. |
| utmapp/libepoxy | MIT | Yes, keep notice. |
| ANGLE (WebKit fork) | BSD-3-Clause | Yes, keep notice. |
| utmapp/dxmt | **LGPL-2.1-or-later** (MIT only up to v0.80) | Yes as a separate, replaceable `libdxmt-native.dylib` that the render server `dlopen`s by name; ship the LGPL text and source for the exact build. Do not statically link it into Veil code. Contains Microsoft DXBCParser (MIT); NVIDIA nvapi (MIT) is a submodule but only built with `enable_nvapi`. |
| LLVM 15 (statically linked into DXMT) | Apache-2.0 with LLVM exception | Yes, keep notice. |
| D3DMetal (Game Porting Toolkit) | Apple proprietary; evaluation of games only, non-commercial distribution | **No.** Excluded, as the task required. DXMT is the only shippable backend, and the post says D3DMetal under Rosetta outperforms native DXMT. |
| Guest KMD `osy/kvm-guest-drivers-windows` (neptune) | BSD-3-Clause | Code yes. Binaries: see signing below. |
| Guest UMD `osy/virtio-win-mesa` (neptune) | Mesa: MIT for most files, per-file licenses in `licenses/` | Yes, keep notices. |
| MoltenVK (only if `venus=true`) | Apache-2.0 | Not needed for Triton; leave `venus` off. |

Signing: the v0.5 release `viogpu3d-arm64x-signed.zip` (SHA-256
`155695ab7820f71e75c369aeae7b8c060691ba43646ac37edef72aa2428506d5`) has a catalog signed by
**Microsoft Windows Hardware Compatibility Publisher** (issuer Microsoft Windows Third Party
Component CA 2014), i.e. attestation-signed. It installs without test signing, so Secure Boot and
`edk2-aarch64-secure-code.fd` stay as they are. Self-built packages are test-signed
(`VirtIOTestCert.pfx`, per `BUILDING.md`), so a Veil build of the driver would need its own
attestation signing through a Microsoft Partner Center account. The INF (`DriverVer
10/29/2026,100.6.101.58000`) matches `PCI\VEN_1AF4&DEV_1050`, the same ID as today's
`virtio-gpu-pci`, so installing it replaces viogpudo on that device as well.

### 4. VM copy

- [x] `~/VeilTriton/vm/win.img`: APFS clone (`cp -c`) of `~/Virtual Machines/Veil/Windows 11 Arm.img`
      (128 GiB raw, 33 GiB allocated, no extra space used until written).
- [x] `~/VeilTriton/vm/uefi-vars.fd` (copy, SHA-1 identical to the original) and
      `~/VeilTriton/vm/tpm/tpm2-00.permall` (copy) for a separate `swtpm` instance.
- [x] Originals only read. The user's VM (QEMU pid 21548, swtpm pid 21547) was running and was not
      touched. Caveat: the disk was cloned while that VM was writing to it, so the copy is
      crash-consistent at best; Windows may run a disk check on first boot.

### 5. Boot the copy with Triton devices

- [ ] Not done (no Triton QEMU binary). Planned command, isolated from the user's VM:

  ```text
  DYLD_FALLBACK_LIBRARY_PATH=$PREFIX/lib:$ANGLE_LIB ANGLE_DEFAULT_PLATFORM=metal NPT_BACKEND=dxmt \
  $PREFIX/bin/qemu-system-aarch64 -machine virt,highmem=on -accel hvf,ipa-granule-size=0x1000 \
    -cpu host -smp 8 -m 8192 -nodefaults \
    -drive if=pflash,format=raw,readonly=on,file=<Veil Runtime>/share/qemu/edk2-aarch64-secure-code.fd \
    -drive if=pflash,format=raw,file=~/VeilTriton/vm/uefi-vars.fd \
    -chardev socket,id=chrtpm,path=~/VeilTriton/vm/tpm/swtpm.sock \
    -tpmdev emulator,id=tpm0,chardev=chrtpm -device tpm-tis-device,tpmdev=tpm0,ppi=off \
    -drive driver=raw,file=~/VeilTriton/vm/win.img,if=none,id=system -device nvme,drive=system,serial=veil-system \
    -device virtio-ramfb-gl,hostmem=8G,blob=true,venus=false,neptune=true \
    -netdev user,id=net0,hostfwd=tcp:127.0.0.1:28444-:18444 -device virtio-net-pci,netdev=net0 \
    -device qemu-xhci,id=usb0 -device usb-kbd -device usb-tablet \
    -display <see below> -vnc 127.0.0.1:7 -qmp unix:<short path>,server,nowait
  ```

- **Open problem found by reading the source: there is no headless GL display on macOS.**
  `virtio-gpu-gl` refuses to realize unless the display backend has OpenGL
  (`hw/display/virtio-gpu-gl.c:134`). In the fork, `egl-headless` needs `gbm`
  (`ui/meson.build:73`), which macOS lacks; `dbus` exports GL scanouts only with GBM or on Win32
  (`ui/dbus-listener.c:211`). The remaining
  GL backends are `cocoa,gl=es` (opens a Mac window, which this experiment must not do) and SPICE
  with the fork's Metal/IOSurface path (`ui/spice-display-metal.m`, the way UTM itself runs
  headless). The measurement run should use `-spice unix=on,addr=<sock>,disable-ticketing=on,gl=on`
  with no client attached, and VNC alone for setup. If SPICE GL without a client does not drive
  scanout, the fallback is a Cocoa window, which needs the user's go-ahead.

### 6. Guest drivers

- [ ] Not done. Plan: download `viogpu3d-arm64x-signed.zip` v0.5 on the host, check the `.cat`/`.sys`
      signer, serve it to the copy (user networking, host `10.0.2.2`), install with
      `pnputil /add-driver viogpu3d.inf /install` from an elevated prompt. Input into the copy goes
      through its own VNC/QMP (`input-send-event`) or the copy's agent `input.*` messages, never the
      Mac. The Veil agent has no command-execution message (by design), so driver install needs
      guest keyboard input.

### 7. Measurements

- [ ] DWM composition accelerated: **not measured.**
- [ ] DWM presents/s while drawing in Paint under Triton: **not measured.**
- [ ] Desktop Duplication under Triton: **not measured.**
- [x] Baseline reference read from the user's running agent (`agent.health.request`, read-only,
      agent `0.1.0+62bc0e017111`, idle, no drawing): `methods.duplication 16475`, `capture` mean
      0.35 ms, `changedTotal` mean 11.11 ms (n=48), `encode` 9.38 ms, `duplicationMode`
      `1184x848 @ 4294967294/4294967294 Hz, system memory True`. `dwmPresentInterval` was ~60 s
      because the desktop was idle; the 25-28 presents/s figure while drawing comes from the
      earlier session.

What to expect, from the agent code (`apps/windows-agent/src/VeilAgent/DesktopDuplicationCapture.cs`
on `refactor/split-large-files`):

- Today DXGI reports `DesktopImageInSystemMemory = true` (no GPU), so the agent uses
  `MapDesktopSurface`. With Triton the desktop image becomes a GPU texture; the agent then takes the
  `QueryInterface(ID3D11Texture2D)` → `CopyResource`/`CopySubresourceRegion` → staging `Map` path
  (lines ~214-251). Its own `D3D11CreateDevice` would also go through Triton/Neptune, so every
  staging `Map` becomes a host GPU→shared-memory readback plus a guest wait. That path has never run
  against a real GPU in this guest; its cost is the most important number to measure, because it
  could cancel the gain from faster DWM.
- Faster DWM is plausible: composition moves off WARP onto Metal. But each DWM frame depends on the
  CPU spin-poll fence emulation across render-server processes, so 60 Hz is not guaranteed and
  120 Hz is unproven.

## Interim Recommendation

Do **not** adopt Triton in Veil's runtime now. Finish the measurement first, and treat it as an
opt-in experiment even if it pays off.

1. Product risk: the upstream author calls the drivers very unstable; a GPU hang takes down the
   Windows desktop that Veil mirrors. Veil would also have to replace bundled QEMU 11.1.3 with the
   UTM fork plus virglrenderer, libepoxy, ANGLE, DXMT and a render server, and rebase on every UTM
   change until it is upstream.
2. Display model: Veil runs QEMU with `-display none` and talks to the guest through VNC and the
   agent. Triton requires a GL-capable display backend, which on macOS means a Cocoa window or the
   SPICE + Metal/IOSurface path. Adopting it means adding a SPICE (or similar) client to Veil, not
   just new arguments in `QEMUWindowsBootPlan.swift`.
3. Signing: Veil cannot ship test-signed drivers to users. It needs its own attestation-signed
   `viogpu3d` build.
4. Capture path: Veil's mirroring copies pixels inside the guest. With Triton, the cheaper path may
   be to take the composed scanout on the host (the IOSurface/blob the SPICE path already
   produces) and crop it by the window rectangles the agent reports, instead of reading the GPU
   texture back into the guest. That is a design change and should wait for the numbers.

If the measurement shows DWM at or above 60 presents/s and a Desktop Duplication changed-frame cost
under ~8 ms, the next step is a separate design doc for an opt-in "GPU acceleration (experimental)"
VM setting: a second QEMU binary in `Runtime/` (keep 11.1.3 as default), the SPICE GL display
backend, `virtio-gpu-gl-pci` with `blob=true,hostmem=…,neptune=true` after a driver-installed flag
(mirroring `QEMUWindowsDisplayDevices`), and LGPL/GPL notices for DXMT and the fork.

## Decision: Apply to the Existing VM, After a Snapshot

The user decided (2026-11-10) that Triton is tried on the existing Veil VM, not on a separate copy,
so the guest uses the Mac's GPU as a shared resource rather than a second allocated VM. Conditions:
snapshot first and document the revert, never erase Windows, never touch the Mac UI (restarts only
through background paths such as `VEIL_LAUNCH_IN_BACKGROUND=1`), tell the user before the VM
(QEMU pid 21548, `-m 16384M -smp 8`) goes down, and never type Windows credentials.

Snapshot (VM must be shut down so the disk is consistent; the user is told first):

```text
SNAP=~/"Virtual Machines/Veil/snapshots/pre-triton-$(date +%Y%m%d-%H%M)"
mkdir -p "$SNAP/tpm"
V=~/"Virtual Machines/Veil"
cp -c "$V/Windows 11 Arm.img" "$SNAP/Windows 11 Arm.img"   # APFS clone, no extra space
cp "$V/uefi-vars.fd" "$SNAP/uefi-vars.fd"
cp "$V/tpm/tpm2-00.permall" "$SNAP/tpm/tpm2-00.permall"
shasum "$V/uefi-vars.fd" "$SNAP/uefi-vars.fd"
```

Revert (VM shut down; restores disk, UEFI variables and TPM state together, since BitLocker or
Windows Hello may be sealed to the TPM):

```text
cp -c "$SNAP/Windows 11 Arm.img" "$V/Windows 11 Arm.img"
cp "$SNAP/uefi-vars.fd" "$V/uefi-vars.fd"
cp "$SNAP/tpm/tpm2-00.permall" "$V/tpm/tpm2-00.permall"
```

Then start the VM again with Veil's normal bundled QEMU 11.1.3 and `virtio-gpu-pci`.

Consequences for the plan:

- The Triton QEMU still has to be built first; without it there is nothing to apply.
- The existing VM is launched by Veil.app's boot plan. Running it on the Triton QEMU means a manual
  launch with the same disk, firmware, TPM socket and port forwards as pid 21548, plus the Neptune
  device and a GL display backend (section 5). Veil's own launcher would not know about that QEMU.
- Installing `viogpu3d` needs an elevated prompt in Windows. If UAC asks for credentials, the
  install stops there and the user has to approve it in the guest.
- `~/VeilTriton/vm` (the earlier copy, cloned while the VM was running) stays only as a spare; the
  snapshot above is the restore point.

## QEMU Base Version and Patches to Carry

- The Triton fork `utmapp/qemu` `utm-edition` @`2934963d` is based on **QEMU 10.0.12** (merge commit
  `6601422e1`, "Merge tag 'v10.0.12' into utm-edition"), one major version below Veil's bundled
  11.1.3. A Veil build of the fork must carry Veil's own QEMU patches.
- Apply the balloon patch to the Triton QEMU too:
  `script/qemu-patches/0001-virtio-balloon-release-discarded-pages-on-darwin.patch`
  (on `refactor/split-large-files` @`e7110fde`). It applies to the fork's
  `hw/virtio/virtio-balloon.c` without fuzz (`patch -p1 --dry-run`).

## To Resume

1. Allow the build (or run it yourself): LLVM 15.0.7 per `~/VeilTriton/src/dxmt/docs/DEVELOPMENT.md`
   (arm64) into `~/VeilTriton/llvm15`, then ANGLE, libepoxy, DXMT (`-Dnative_llvm_path`),
   virglrenderer arm64, QEMU, all with `--prefix=~/VeilTriton/prefix`.
2. Boot `~/VeilTriton/vm` with the command in section 5, SPICE GL, VNC on `127.0.0.1:7`.
3. Install v0.5 drivers, confirm `viogpu3d` in Device Manager and a non-WARP adapter in `dxdiag`.
4. Deploy the `refactor/split-large-files` agent to the copy, draw in Paint through the agent's
   `input.mouse`, read `frameCapture` from `ws://127.0.0.1:28444/`.
