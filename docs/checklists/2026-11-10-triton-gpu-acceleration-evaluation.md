# Triton (UTM) DirectX 11 Acceleration, Evaluation

Date: 2026-11-10

Updated: 2026-11-11

Status: **measured**. The existing Veil VM was snapshotted, booted on the Triton QEMU, given the
v0.5 `viogpu3d` driver and measured; it was then **reverted to the snapshot** and is running on
Veil's normal bundled QEMU again. Result: Triton roughly triples the mirrored frame rate (23.5 →
72 fps, DWM capped by the 75 Hz mode), but Windows can no longer shut down with the driver
installed, and the driver leaves the guest without a display on Veil's default runtime. See
[Recommendation](#recommendation).

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

### 5. Boot the existing VM with Triton devices

- [x] Booted the **existing** VM (not the copy; see [Decision](#decision-apply-to-the-existing-vm-after-a-snapshot))
      with `~/VeilTriton/run-triton-existing-vm.sh` (the install variant adds a driver ISO as a USB
      CD-ROM). It uses Veil's disk, UEFI variables, TPM state, firmware, port forwards and balloon
      device, plus `-accel hvf,ipa-granule-size=0x1000`,
      `-device virtio-ramfb-gl,hostmem=8G,blob=true,venus=false,neptune=true` and
      `-display egl-headless,gl=es -vnc 127.0.0.1:7`. No Mac window was opened.
- Fixes needed against the fork's QEMU 10.0.12 base:
  - `tpm-tis-device` has no `ppi` property there; drop `,ppi=off`.
  - `nohup` is SIP-protected and strips `DYLD_*`, so ANGLE's `libEGL.dylib` was not found; start
    QEMU without it.
- **Headless display, second patch.** The first patch made `egl-headless` start, but every
  screendump was black. Three causes, all fixed in `~/VeilTriton/qemu-egl-headless-darwin.patch`
  (now 5 files, +282 lines):
  1. Before the driver, scanouts are GL textures. The stock readback blits into a BGRA texture
     (`glTexImage2D(GL_RGBA, …, GL_BGRA)`, invalid on GLES) and reads with `GL_BGRA`, which ANGLE
     rejects (`GL_INVALID_FRAMEBUFFER_OPERATION`/`GL_INVALID_OPERATION`). The darwin path now reads
     the guest framebuffer directly as RGBA and swaps and flips it on the CPU.
  2. FBOs are per-context, and the display callbacks run with virgl's context current. The darwin
     path makes the display context current around each GL call and restores the previous one.
  3. After the driver, Neptune scanouts are Metal textures (`SCANOUT_TEXTURE_NATIVE_TYPE_METAL`).
     A new `ui/egl-headless-metal.m` blits the texture into a shared `MTLBuffer` on the display
     refresh tick (only when a flush marked it dirty) and copies it into the console surface, so
     VNC and `screendump` work.
  This readback is for setup and diagnostics only; Veil would not mirror through it (see below).

### 6. Guest drivers

- [x] v0.5 `viogpu3d-arm64x-signed.zip` (SHA-256 `155695ab…506d5`, as in section 3) served as an
      ISO. The Veil agent has no command execution by design, so the install went through guest
      keyboard input over QMP: Run dialog → `powershell -w h -c "start -verb runas D:\install.cmd"`
      → UAC consent answered with Alt+Y (a consent prompt; **no credentials were typed**).
      `install.cmd` runs `pnputil /add-driver viogpu3d.inf /install`. Result, read back through the
      agent's Notepad frame capture: published as `oem7.inf`, installed on three
      `PCI\VEN_1AF4&DEV_1050&SUBSYS_11001AF4` instances, exit code 0, no reboot required.
- [x] Neptune live right after install: scanouts switch to Metal, `virgl_render_server` processes
      start (`npt: loaded D3D11 library: libdxmt-native.dylib`, `backend library: directx-native
      ABI 1`, `Neptune renderer initialized`), and DXGI Desktop Duplication reports
      `system memory False`.
- Signals seen: `npt: failed to load D3D12CreateDevice` (DXMT has no D3D12; harmless for D3D11),
  `warn: Failed to open D3DKMT adapter` (from a render-server process; no visible effect).

### 7. Measurements

Method: `paintbench.mjs` (scratch script, not committed) opens Paint through the agent
(`app.launch.request`), subscribes to its frames on the `/frames` binary channel with
`bgra-deflate` tiles, draws circles with `input.mouse` at ~110 moves/s, counts delivered frames,
then reads the agent's `frameCapture` diagnostics. Guest-only input; nothing touched the Mac.
Agent `0.1.0+0fec7d5e1b54` (WARP rows on the Retina-session agent `a8f235dbec78` / `0fec7d5e1b54`).

| Run | Display | App frames/s | Frame gap p50 / p90 / p99 (ms) | DWM present interval mean | Changed frame (agent) | Encode | Duplication surface |
|---|---|---|---|---|---|---|---|
| WARP (bundled QEMU 11.1.3, viogpudo), before | 2048x1280 | **23.5** | 44.2 / 58.7 / 67.2 | 40.6 ms (~25/s) | 8.96 ms | 7.95 ms | system memory |
| WARP, after revert, 20 s | 2048x1280 | **24.6** | 41.7 / 58.6 / 71.2 | 40.0 ms | 13.85 ms | 12.21 ms | system memory |
| Triton QEMU, viogpudo (no driver yet) | 800x600 | 30.0 | — | 25.2 ms | — | — | system memory |
| Triton + viogpu3d | 1024x768 | **72.2** | 15.4 / 23.7 / 27.8 | 13.6 ms (~73/s) | 1.95 ms | 0.73 ms | GPU texture |
| Triton + viogpu3d | 1920x1200 | **70.8** | 15.8 / 23.5 / 28.0 | 13.6 ms | 1.99 ms | 0.75 ms | GPU texture |
| Triton + viogpu3d, 60 s soak | 1920x1200 | **71.5** (4289 frames) | 15.7 / 24.2 / 27.6 | 13.7 ms | 1.83 ms | — | GPU texture |

- DWM composition **is accelerated**: the present interval drops from ~40 ms to ~13.6 ms, i.e.
  the 75 Hz the driver's mode reports (`1920x1200 @ 75/1 Hz`). 60 fps is reached; **120 Hz is
  not**: the driver offers no faster mode, and the agent's `display.resize.request` sets only size.
- The feared readback cost did not appear: the agent's GPU path (`CopySubresourceRegion` →
  staging `Map`) costs 0.27-0.41 ms per map, and a changed frame costs ~2 ms in total instead of
  9-14 ms on WARP.
- Host CPU while drawing (5 s samples): Triton, QEMU plus render servers, 154-198 % (about 165 %);
  WARP, QEMU alone, 133-258 %. About the same CPU for three times the frames.
- `display.resize.request` with viogpu3d: 1920x1200, 1920x1080, 1680x1050, 1600x1200 and 1280x800
  are accepted; **2048x1280 is refused** (`display_mode_not_supported`), so Veil's Retina-sized
  modes need the driver's mode list extended.

#### Stability

- 60 s continuous drawing and repeated runs: no crash, no hang, no lost frames reported.
- **Windows does not shut down with viogpu3d installed.** Before the driver, all four agent-requested
  shutdowns on the Triton QEMU powered the VM off (PSCI SYSTEM_OFF) in 30-60 s. After it,
  `system.shutdown.request` (twice), the ACPI power button and the sign-in screen's own
  "시스템 종료" all end at the lock screen or an idle black screen with the VM still running
  (vCPUs idle, one QEMU thread at ~12 %). The VM had to be stopped with QMP `quit`.
  (Pending Windows updates were offered; "Shut down" without updates was chosen.)
- **The driver breaks Veil's default runtime.** The same disk booted on Veil's bundled QEMU with
  plain `virtio-gpu-pci` shows "Display output is not active", and the agent's capture fails with
  `EnumAdapters (no adapter with an output) 0x887A0002` (0 fps). viogpu3d binds the same PCI ID as
  viogpudo, so the driver cannot be installed unless the VM always runs on the Triton runtime.

## Recommendation

**Do not bundle Triton in Veil's default runtime.** Keep it as a tracked experiment, and build an
opt-in "GPU acceleration (experimental)" VM mode only after the two blockers below are fixed
upstream or by us.

Why it is worth pursuing: it is the only measured way past the WARP ceiling. Mirrored Paint goes
from ~24 to ~71 fps with DWM at the display's 75 Hz and a 5-7x cheaper changed-frame path in the
agent, at the same host CPU. That is the "Parallels-grade" target for 60 Hz content.

Blockers before any user sees it:

1. **Shutdown.** A VM that cannot shut down cleanly risks lost work and interrupted updates, and
   Veil's stop path relies on `system.shutdown.request`. Report it upstream
   (`osy/kvm-guest-drivers-windows`) with this repro; retest each driver release.
2. **Driver lock-in.** viogpu3d takes over `DEV_1050` and leaves no display on the 2D device.
   Switching a VM between runtimes would need driver swapping (`pnputil /delete-driver oem<N>.inf
   /uninstall` back to viogpudo) inside the guest, elevated, every time. The opt-in must therefore
   be per VM and effectively one-way, with a snapshot taken by Veil before the driver goes in.
3. **Mode list.** No 2048x1280 or high-refresh mode; 120 Hz needs driver work.
4. **Signing.** The v0.5 binaries are attestation-signed by Microsoft for osy's build. Veil can
   only redistribute them as-is or get its own attestation signing for a patched build.

Licensing, if it ships (from section 3): **DXMT only**, as a separate, replaceable
`libdxmt-native.dylib` loaded by the render server, with the LGPL-2.1 text and corresponding
source for the exact build; GPL-2.0 source offer for the UTM QEMU fork plus Veil's patches
(balloon patch, the headless patch above); MIT/BSD notices for virglrenderer, libepoxy and ANGLE;
Apache-2.0 notice for LLVM 15 (statically linked into DXMT). **Never D3DMetal**: Apple's Game
Porting Toolkit license forbids redistribution, and DXMT is what was measured here.

Architecture notes for the opt-in mode:

- Second QEMU binary in `Runtime/` (UTM fork + Veil patches), the default stays 11.1.3.
- Veil needs a GL display backend it can run windowless. The patched `egl-headless` works, but
  its CPU readback is for diagnostics. For mirroring, the agent's in-guest Desktop Duplication
  already costs only ~2 ms per changed frame under Triton, so the existing frame channel can stay;
  a host-side IOSurface path (crop the Metal scanout by the agent's window rectangles) is an
  optimisation, not a prerequisite.
- `veil-shm-display` (Veil's shared-memory scanout object) is a QEMU 11.1.3 patch and would need a
  port to the fork, or the mirror must run purely on the agent frame channel.

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
V=~/"Virtual Machines/Veil"; SNAP="$V/snapshots/pre-triton-20261111-1506"   # the snapshot actually taken
cp -c "$SNAP/Windows 11 Arm.img" "$V/Windows 11 Arm.img"
cp "$SNAP/uefi-vars.fd" "$V/uefi-vars.fd"
cp "$SNAP/tpm/tpm2-00.permall" "$V/tpm/tpm2-00.permall"
```

Then start the VM again with Veil's normal bundled QEMU 11.1.3 and `virtio-gpu-pci`.

Consequences for the plan:

- (Done: the Triton QEMU was built on 2026-11-10 and applied on 2026-11-11; see
  [What Was Done](#what-was-done-to-the-users-vm-2026-11-11).)
- The existing VM is launched by Veil.app's boot plan. Running it on the Triton QEMU means a manual
  launch with the same disk, firmware, TPM socket and port forwards as pid 21548, plus the Neptune
  device and a GL display backend (section 5). Veil's own launcher would not know about that QEMU.
- Installing `viogpu3d` needs an elevated prompt in Windows. If UAC asks for credentials, the
  install stops there and the user has to approve it in the guest. (On this VM UAC showed a
  consent prompt only, answered with Alt+Y.)
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

## What Was Done to the User's VM (2026-11-11)

- 15:02 Veil app quit (`pkill -x veil-host-shell`; QEMU kept running), `system.shutdown.request`
  accepted; VM idle and black for 20+ s, then QEMU stopped over QMP.
- 15:06 Snapshot `~/Virtual Machines/Veil/snapshots/pre-triton-20261111-1506` (APFS clone of the
  disk, `uefi-vars.fd` SHA-1 `1374e679…`, `tpm2-00.permall` SHA-1 `5c0148df…`).
- 15:07-16:15 Triton boots, driver install, measurements.
- 16:17 Triton state kept as `snapshots/post-triton-20261111-1617` (crash-consistent, taken
  after a forced stop because the guest would not shut down). Booting it needs the Triton QEMU.
- 16:18-16:21 Compatibility boot on bundled QEMU (no display, see Stability), forced stop.
- 16:21 **Reverted** to `pre-triton-20261111-1506` with the revert commands above (hashes match).
- 16:22 Veil restarted from the main checkout with `VEIL_LAUNCH_IN_BACKGROUND=1
  ./script/build_and_run.sh`; agent `0.1.0+0fec7d5e1b54` reconnected, interactive, back on
  `2048x1280 … system memory True` (WARP).

To go back to the Triton state later (VM shut down first):

```text
V=~/"Virtual Machines/Veil"; POST="$V/snapshots/post-triton-20261111-1617"
cp -c "$POST/Windows 11 Arm.img" "$V/Windows 11 Arm.img"
cp "$POST/uefi-vars.fd" "$V/uefi-vars.fd"; cp "$POST/tpm/tpm2-00.permall" "$V/tpm/tpm2-00.permall"
~/VeilTriton/run-triton-existing-vm.sh
```

Do not open that disk with Veil's normal runtime: it will have no display.

## Reproduce

Host build: section 2, then apply `~/VeilTriton/qemu-egl-headless-darwin.patch` to the fork and
rebuild. Scripts outside the repo: `~/VeilTriton/run-triton-existing-vm.sh` (Triton boot),
`~/VeilTriton/run-triton-install.sh` (same plus the driver ISO), `~/VeilTriton/run-compat-bundled.sh`
(bundled QEMU, headless, for compatibility checks). Logs land in `~/VeilTriton/run/`.
