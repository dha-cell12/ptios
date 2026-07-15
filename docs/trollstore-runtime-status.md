# TLinkauto TrollStore Runtime Status

This document captures the current implemented state of the `stream-app`
TrollStore runtime.

## Implemented

- Task server: port `6000`, legacy line protocol, success `0;;...`, error `-1;;...`.
- H.264 stream: ports `7001-7006`.
- Core automation: touch `10/61-65`, sleep `18`, device info `25`, screenshot `29`.
- Screenshot album: task `29` action `2` saves to the `TLinkauto` Photos album; action `3` removes assets from that album only. Grant Photos permission from `StreamControl > Settings > Photo Access` first.
- Image/color/frame: `21`, `23`, `28`, `47-49`, `66-70`.
- OCR: task `91` uses true Tesseract static libs and `/var/mobile/Library/TLinkauto/tessdata/*.traineddata`.
- Script runtime: task `19/20` JavaScriptCore with a rootfull compatibility facade for common `device.*` APIs, `runTask`/task bridge, normalized storage responses, keyboard wrappers, color/frame/image/OCR wrappers, and app/process wrappers.
- Keyboard/text: task `24` uses `clipboardd` v4 on port `6012` with private background Pasteboard entitlements. Every write is read-back verified before `streamd` trusts daemon reads. Devices that ignore these entitlements fall back to the foreground app bridge on port `6013`, with best-effort restoration of a recent frontmost cache. Insert, paste, delete, cursor movement, and show/hide keyboard still depend on the rootfull SpringBoard keyboard observer and return `limited_on_trollstore` instead of silent success.
- App/process: `11`, `31-35`, `50-54` via streamd plus privhelper where needed.
- Admin extension: task `72` clears safe app data containers through privhelper. It refuses protected bundles and unsafe paths.
- Shell: task `13/71` is gated by settings and disabled by default.

## Deferred Or Limited

- Keychain clearing remains deferred because arbitrary target keychain access groups require separate entitlement handling.
- VPN control remains query-only unless a profile/private entitlement path is added.
- Vision OCR remains deferred for the `420f`/worker crash issue documented in `plan.md`; task `91` Tesseract is the stable OCR path.
- Activator/Siri equivalents remain `limited_on_trollstore`.
- Full SpringBoard overlay behavior is replaced by foreground app overlays and fallback behavior.

## Quick Manual Checks

```powershell
Invoke-TLinkTask -HostIP $iphoneIP -Task "97"
Invoke-TLinkTask -HostIP $iphoneIP -Task "60"
Invoke-TLinkTask -HostIP $iphoneIP -Task "91check_langs"
```

Script compatibility smoke:

```text
StreamControl.app -> Scripts -> Demo Script.tl -> Play
```

The demo log should include `pickColor`, `captureFrame`, `framePickColors`,
`screenshot`, and `ocrLanguages`.

Screenshot album:

```powershell
$path = "/var/mobile/Library/TLinkauto/screenshots/test.png"
Invoke-TLinkTask -HostIP $iphoneIP -Task "291;;$path"
Invoke-TLinkTask -HostIP $iphoneIP -Task "292;;$path"
Invoke-TLinkTask -HostIP $iphoneIP -Task "293"
```

Clear app data extension:

```powershell
Invoke-TLinkTask -HostIP $iphoneIP -Task "72com.example.testapp"
```
