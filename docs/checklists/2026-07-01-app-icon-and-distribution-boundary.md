# App Icon And Distribution Boundary Checklist

Goal: make the generated Veil icon reliably appear at runtime and keep Windows media distribution out of hosted storage.

- [x] Apply the bundled `VeilAppIcon.icns` to `NSApp.applicationIconImage` at launch.
- [x] Add changing bundle build metadata so macOS is less likely to reuse stale icon metadata.
- [x] Keep generated app icon resources in the local `.app` bundle.
- [x] Document that Appwrite Storage must not host or mirror Windows ISO files for Veil.
- [x] Allow future Appwrite use only for metadata, official-link references, user-owned private references, or setup state.

Verification:

```sh
swift build --product veil-host-shell
swift script/generate_app_icon.swift /tmp/VeilAppIcon.icns
swift test
git diff --check
```
