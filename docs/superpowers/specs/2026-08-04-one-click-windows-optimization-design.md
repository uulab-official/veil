# One-Click Windows Optimization Design

Date: 2026-08-04

## Goal

Let a user repair an already-installed Windows VM without manually downloading media, opening installers, approving multiple in-guest steps, or choosing a recovery command. After one combined terms confirmation in Veil, the app prepares the media, installs the display integration and Veil guest agent, restarts Windows, and verifies the result.

## Product contract

- Show one primary action, **Optimize Windows**, only when Windows is installed and integration evidence is incomplete.
- Before starting, explain that Veil will install official UTM Guest Tools and the Veil guest agent, then restart Windows. The user explicitly confirms the applicable terms once in the macOS app.
- Preserve the Windows virtual disk and user data. This flow never recreates, formats, or replaces the system disk.
- Replace individual technical setup buttons with one progress surface and one recovery action.
- A successful command dispatch is not completion. Veil reports completion only after Windows returns and the guest agent connects. Display resolution improvement is reported separately so partial success remains honest.

## Chosen approach

Reuse Veil's existing QEMU/HVF boot, QMP keyboard/pointer input, attached read-only media, console-frame observation, and guest-agent connection checks. Add a bounded orchestration state machine around them instead of introducing a new privileged macOS helper or modifying the Windows system disk offline.

The automatic media contains a short Windows command script. The host only needs to open the Windows Run dialog and invoke that script. The script finds the attached UTM Guest Tools volume, runs its installer silently, installs and starts the Veil guest agent, and requests a normal Windows restart. The host verifies completion through the live agent connection instead of trusting a command-dispatch result or a writable marker.

This approach is preferable to a clean reinstall because it preserves user data, and preferable to exposing the installer because it removes repeated in-guest interaction. It also keeps the fallback bounded: if QMP input or verification fails, Veil stops claiming progress and offers a single retry.

## Components

### Optimization policy

A small, deterministic policy maps runtime evidence to one of these states:

1. `notNeeded`: Windows integration is already healthy.
2. `ready`: Windows is installed and optimization can begin.
3. `preparingMedia`: downloading and validating official Guest Tools and rebuilding Veil automation media.
4. `restartingForMedia`: stopping a running VM when required and starting it with the prepared media attached.
5. `waitingForDesktop`: waiting for a live console before injecting input.
6. `installing`: dispatching the short media command and handling the expected elevation prompt.
7. `restartingWindows`: waiting for the guest to restart.
8. `verifying`: waiting for guest-agent connectivity and checking the current framebuffer size.
9. `complete`: the agent is connected; display status says optimized or still limited.
10. `failed`: a bounded step failed with a user-facing explanation and one retry action.

The policy is pure and unit tested. UI labels and button availability derive from it instead of duplicating state checks across views.

### Media preparation

- Reuse `UTMGuestToolsDownloader` for HTTPS origin checks, plausible file size, and ISO 9660 validation.
- Persist the validated ISO in Veil Application Support and attach it read-only through the VM profile.
- Extend Veil's generated automation media with `Optimize.cmd`. Keep the existing `V.cmd` guest-agent repair path for compatibility.
- `Optimize.cmd` scans drive letters rather than assuming a fixed CD-ROM letter.
- The script exits nonzero if Guest Tools media or the Veil agent payload is absent. It does not alter partitions or activation state.

### Host orchestration

- If the VM is running without the required media, request a normal ACPI shutdown and wait for the process to exit before restarting it.
- Start Windows through the existing runtime model, then wait for a live RFB frame with a bounded timeout.
- Use the existing QMP Run-dialog command path to invoke `Optimize.cmd`; retain the tested pointer/keyboard fallback for Run and elevation dialogs.
- Wait through the expected reboot without replacing the last good frame with a transient error screen.
- Verify guest-agent connectivity after reboot. Record the observed framebuffer dimensions but do not fail agent installation solely because Windows still reports the fallback resolution.
- Never retry command injection automatically after it may have started. A retry begins from a fresh evidence check and the Windows script remains idempotent.

### User interface

The installed Windows home shows a single card when optimization is needed:

- Title: **Finish Windows Optimization**
- Detail: **Install display integration and Veil app support automatically. Windows will restart once.**
- Primary action: **Optimize Windows**

After confirmation, the card becomes a progress surface with a concise stage label and progress indicator. Advanced details remain available through Diagnostics, not as competing buttons. Before command dispatch the user may cancel; after installation starts the UI asks them to keep Veil open. On failure the only primary action is **Try Again**. On completion the card disappears when all evidence is healthy, or shows a non-blocking display follow-up if the agent is ready but the framebuffer remains at the fallback size.

## Error handling

- Download or validation failure: keep the existing VM untouched and offer retry.
- VM stop/start failure: preserve diagnostics and offer retry without deleting media or disk state.
- No live desktop before timeout: do not inject input; explain that Windows must reach the desktop.
- QMP dispatch failure: stop the workflow and retain the console for manual inspection.
- Reboot timeout: keep the last good frame and show retry/recovery diagnostics.
- Agent unavailable after reboot: classify as partial/failed integration and rerun the idempotent repair flow on explicit retry.
- Agent connected but resolution unchanged: report app integration ready and display integration incomplete; never label the whole flow fully optimized.

## Testing and acceptance

- Unit tests cover every policy transition, cancellation boundary, retry rule, and partial-success label.
- Boot-plan tests prove both read-only Guest Tools media and rebuilt Veil automation media are attached for an installed VM.
- Script-generation tests prove `Optimize.cmd` scans drives, silently starts Guest Tools, installs the Veil agent, and requests a normal restart without destructive disk commands.
- Mock orchestration tests cover stopped/running VM paths, download failure, desktop timeout, command failure, reboot timeout, agent success, and unchanged-resolution partial success.
- macOS lifecycle contracts prove the installed home exposes one optimization action and no manual installer sequence.
- The full repository regression gate must pass before integration.
- A live pass on the existing Windows VM must confirm: one macOS confirmation, automatic media preparation, one Windows restart, guest-agent connection, and observed post-reboot framebuffer dimensions. Any failed acceptance item remains explicitly unchecked rather than inferred from command dispatch.

## Scope boundaries

- No Windows image, proprietary driver, product key, UTM binary, or Guest Tools ISO is committed to the repository.
- No promise of Windows activation or Microsoft support is added.
- Printer setup, application installation, Windows Update, and unrelated VM settings are outside this optimization flow.
