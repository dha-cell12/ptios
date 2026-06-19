# TLinkauto Rename Notes

This document records the two main runtime issues found after renaming the project from ZXTouch/zxtouch to TLinkauto/tlinkauto.

## App Signing Issue

After the app bundle and bundle identifiers were renamed, the app initially appeared on the Home Screen but was killed before `main()` ran.

Root cause:

- The app bundle produced by Xcode was being modified during packaging/install.
- `postinst` removed `_CodeSignature` and re-signed with `ldid` by default.
- After the rename, the app bundle identifier, entitlements, and installed signature needed to match exactly.
- The install-time `ldid` path could leave the renamed app with a signature/entitlement state that AMFI rejected, causing `Killed: 9` before application code executed.

Fix:

- Build the renamed app bundle with Xcode in GitHub Actions.
- Copy the built `TLinkauto.app` into `layout/Applications/TLinkauto.app`.
- Sign the app and extension in the workflow using `codesign --force --sign - --entitlements layout/entitlements.plist`.
- Keep install-time `ldid` re-signing disabled by default.
- Only run the `ldid` fallback when `/var/mobile/Library/TLinkauto/force_ldid_resign` exists.

Important rule:

- Do not remove `_CodeSignature` or re-sign the installed app in `postinst` during normal installs.

## Daemon Bind Issue

After the daemon was renamed from `zxtouchd` to `tlinkautod`, the daemon repeatedly restarted and logged:

```text
CFSocketSetAddress bind failure: 48
failed to bind socket
```

Root cause:

- Error `48` is `EADDRINUSE`: port `6000` was already in use.
- A previous daemon instance or the old LaunchDaemon label could remain loaded after upgrading from the old package name.
- Because the new LaunchDaemon has `KeepAlive`, failed starts were retried repeatedly, producing a restart loop.

Fix:

- `preinst` unloads both old and new LaunchDaemon labels before unpack/install.
- `preinst` kills old and new daemon processes before the new package is installed.
- `preinst` removes obsolete old daemon files:
  - `/Library/LaunchDaemons/com.zjx.zxtouchd.plist`
  - `/usr/bin/zxtouchd`
  - `/usr/bin/zxtouchb`
- `postinst` repeats the cleanup before loading `com.tlinkauto.tlinkautod`.

Important rule:

- When renaming a LaunchDaemon or daemon binary, always unload and remove the old label/binary during upgrade. Otherwise the old daemon can keep sockets, files, or privileges alive under the old name.

## Kept Fixes

- New app bundle id: `com.tlinkauto.tlinkauto`.
- New extension bundle id: `com.tlinkauto.tlinkauto.shortcutext`.
- New LaunchDaemon label: `com.tlinkauto.tlinkautod`.
- New daemon/helper paths:
  - `/usr/bin/tlinkautod`
  - `/usr/bin/tlinkautob`
- New data path: `/var/mobile/Library/TLinkauto`.
- Bridge/device capability key: `tlinkauto`.

## Removed Debug Changes

The temporary debugging added while diagnosing the rename was removed after the issues were understood:

- Early app launch log files under `/tmp` and `/var/mobile/Library/TLinkauto`.
- Install-time signature diagnostic log `install_app_check.log`.
- Workflow checks for temporary debug log strings.
- Extra daemon bind debug logs.
- Python playback output tail scanning.
