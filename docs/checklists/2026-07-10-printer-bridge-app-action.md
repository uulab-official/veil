# Printer Bridge App Action

Goal: move the manual printer bridge plan from a CLI-only contract into the
app action surface without claiming automatic printer provisioning.

## Checklist

- [x] Add `actions[].id=dailyUse.planPrinterBridge` with a product-facing
  `Printer Setup` title.
- [x] Route `dailyUse.planPrinterBridge` through the launcher and menu-bar
  action routers so app surfaces can treat it as an executable in-app handoff.
- [x] Surface the printer bridge endpoint and plan command in the Windows Apps
  panel.
- [x] Update app-runtime-status harness validation so the printer setup action
  cannot disappear or become unavailable while the manual IPP plan is active.

## CEO Review

This keeps the product honest: Veil still says printer support is a manual IPP
setup experiment, but the user no longer has to discover that path in docs or
terminal output only. It is now visible beside Daily Use app and notification
checks.

## Engineering Review

No macOS printer enumeration, CUPS mutation, Windows driver claim, or automatic
guest-side registration was added. The app action is a guided setup handoff
backed by `dailyUseReadiness.printerBridgePlanCommand` and the
`harness/printer-bridge-plan` validator.
