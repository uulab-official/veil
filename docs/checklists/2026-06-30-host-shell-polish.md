# Host Shell Polish Checklist

Goal: raise the SwiftUI host shell from a basic smoke-test window to a safer operational shell.

## Checklist

- [x] Auto-select the first loaded Windows app.
- [x] Track selected app state in `HostDashboardModel`.
- [x] Expose `selectedApp`, `canLaunchSelectedApp`, and `launchSelectedApp()`.
- [x] Prevent unsupported app launches at the model boundary.
- [x] Replace raw enum error text with user-facing messages.
- [x] Add tests for missing selection and unsupported selected apps.
- [x] Add AppKit activation for SwiftPM app-bundle launches.
- [x] Wire SwiftUI table selection to the dashboard model.
- [x] Keep toolbar actions disabled while loading or launching.

## Current Harness Limit

The fake agent only launches `winapp_notepad`. Other app ids should remain visible in the app list when fixtures expand, but they must not dispatch launch requests until the protocol and fake agent support generic app launch flows.
