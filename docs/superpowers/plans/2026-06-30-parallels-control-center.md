# Parallels-Style Control Center Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Turn the VM Runtime tab into a Control Center-style dashboard for Windows 11 Arm setup and Mac integration readiness.

**Architecture:** Keep the current SwiftUI `NavigationSplitView` shell and refactor only the VM Runtime surface plus small shared shell components. The core runtime model remains unchanged; UI derives setup progress and integration status from the existing snapshot and agent capability concepts.

**Tech Stack:** SwiftUI, Swift Package Manager, VeilHostCore runtime snapshots, existing shell design components.

---

### Task 1: Document Direction

**Files:**
- Create: `docs/superpowers/specs/2026-06-30-parallels-style-control-center-design.md`
- Create: `docs/superpowers/plans/2026-06-30-parallels-control-center.md`
- Create: `docs/checklists/2026-06-30-parallels-control-center.md`

- [x] **Step 1: Write a concise design spec**

Run: `test -f docs/superpowers/specs/2026-06-30-parallels-style-control-center-design.md`
Expected: command exits `0`.

- [x] **Step 2: Write this implementation plan**

Run: `test -f docs/superpowers/plans/2026-06-30-parallels-control-center.md`
Expected: command exits `0`.

### Task 2: Shared Shell Components

**Files:**
- Modify: `apps/mac-host/Sources/VeilHostShell/Views/ShellChrome.swift`

- [x] **Step 1: Add compact dashboard primitives**

Add reusable stat, action, and progress components that keep cards dense and macOS-like.

- [x] **Step 2: Build-check the shared components**

Run: `swift test` from `apps/mac-host`
Expected: all Swift tests pass.

### Task 3: VM Control Center

**Files:**
- Modify: `apps/mac-host/Sources/VeilHostShell/Views/VMRuntimeView.swift`

- [x] **Step 1: Replace the top runtime form with a Windows 11 Arm hero**

The hero must include machine name, runtime status, architecture, boot-ready state, and Start/Refresh actions.

- [x] **Step 2: Add setup assistant progress**

Show profile, installer media, virtual disk, and preflight readiness as visible checklist/progress items.

- [x] **Step 3: Add Mac Integration panel**

Show app launch, window tracking, window capture, clipboard, shared folders, Dock-style launching, and seamless app mode readiness.

- [x] **Step 4: Keep file import actions working**

The existing Select Installer and Select Disk buttons must still call `updateProfilePaths`.

### Task 4: Verification

**Files:**
- Modify: `docs/checklists/2026-06-30-parallels-control-center.md`

- [x] **Step 1: Run Swift tests**

Run: `swift test` from `apps/mac-host`
Expected: all Swift tests pass.

- [x] **Step 2: Run protocol and harness tests**

Run: `npm test` in `packages/protocol`, `harness/fake-agent`, and `harness/fake-host`.
Expected: all tests pass.

- [x] **Step 3: Run app verification**

Run: `./script/build_and_run.sh --verify`
Expected: the app builds and a `veil-host-shell` process starts.

- [x] **Step 4: Check diff hygiene**

Run: `git diff --check`
Expected: no output.

### Task 5: Commit and Push

**Files:**
- All files above.

- [ ] **Step 1: Commit the completed UI pass**

Run: `git commit -m "style: add parallels-style control center"`
Expected: commit succeeds.

- [ ] **Step 2: Fast-forward `main` and push**

Run: `git switch main && git merge --ff-only codex/parallels-control-center && git push origin main`
Expected: `origin/main` contains the new commit.
