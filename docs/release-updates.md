# Updates of Veil itself

Veil updates itself with [Sparkle](https://sparkle-project.org) 2.10.1, added as a Swift package
(`apps/mac-host/Package.swift`). A release build checks a feed once a day, after asking on its second
launch whether it may; Check for Updates… is in the Veil app menu and the menu bar menu. An update replaces
Veil only after the user agrees, and quitting for it asks about a running Windows as any quit does.

## How it fits together

- **Feed**: `https://github.com/uulab-official/veil/releases/download/appcast/appcast.xml`, an asset of a
  release tagged `appcast`. A fixed tag, because 0.x releases are pre-releases and GitHub's
  `releases/latest` skips those.
- **Signature**: every archive is signed with an EdDSA (Ed25519) key. The public key is in
  `script/sparkle-public-ed-key.txt` and goes into the release's Info.plist as `SUPublicEDKey`, next to
  `SUFeedURL`; Sparkle refuses an archive whose signature does not match. The private key is the
  `SPARKLE_ED_PRIVATE_KEY` repository secret and never enters the repository.
- **Which builds update**: only a release built with the public key carries `SUFeedURL` and
  `SUPublicEDKey`. Development builds (`script/build_and_run.sh`) carry neither and hide Check for Updates
  (`VeilUpdater`), so they never replace themselves with a release. Only a Developer ID signed, notarized
  build is published to the feed (`.github/workflows/release.yml`, steps Update feed and Publish update
  feed); Gatekeeper would refuse an ad-hoc one on the user's Mac.
- **Bundle**: `script/embed_sparkle.sh` copies `Sparkle.framework` into `Contents/Frameworks`, leaves out
  its XPC services (Veil is not sandboxed), adds the `@executable_path/../Frameworks` rpath, and signs
  Autoupdate, Updater.app, and the framework with the app's identity. An ad-hoc hardened build cannot load
  an ad-hoc framework ("different Team IDs"), so `release_macos.sh --unsigned` alone adds
  `com.apple.security.cs.disable-library-validation`.
- **Feed contents**: `script/make_appcast.sh` writes one item for the new archive, signed with
  `sign_update` from the Sparkle package's `bin/` folder; the private key comes on standard input.

## Setting it up once

1. Create the key pair on the release Mac. Sparkle keeps the private key in the login Keychain:

   ```bash
   apps/mac-host/.build/artifacts/sparkle/Sparkle/bin/generate_keys
   ```

2. Commit the public key it prints to `script/sparkle-public-ed-key.txt`.
3. Export the private key and store it as the `SPARKLE_ED_PRIVATE_KEY` repository secret, then delete
   the exported file:

   ```bash
   apps/mac-host/.build/artifacts/sparkle/Sparkle/bin/generate_keys -x sparkle-private-key.txt
   gh secret set SPARKLE_ED_PRIVATE_KEY --repo uulab-official/veil < sparkle-private-key.txt
   rm sparkle-private-key.txt
   ```

4. Make sure the Developer ID and notarization secrets listed at the top of `release.yml` are set.

Losing the private key means installed copies can never update again; keep a backup of the Keychain item.
Changing it requires a release signed with the old key that carries the new public key.
