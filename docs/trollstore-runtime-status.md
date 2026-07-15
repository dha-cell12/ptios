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
- Script regression suite: the root `Scripts` tab auto-seeds a `Compatibility Tests` folder from packaged examples on first launch; `Scripts > + > Compatibility Suite` can install another copy manually. The six `.tl` bundles exercise each compatibility API group independently.
- Keyboard/text: task `24` uses `clipboardd` v7 on port `6012` with private background Pasteboard entitlements. Every write is read-back verified before `streamd` trusts daemon reads. Subtask `1` inserts text using background clipboard plus HID `Command+V`; subtask `5` pastes the existing clipboard; subtasks `3/4` use HID arrows and Backspace. Devices that ignore the Pasteboard entitlements fall back to the foreground app bridge on port `6013`. Show/hide keyboard remains `limited_on_trollstore` because it needs the rootfull SpringBoard keyboard observer.
- Background UI bridge: `clipboardd` v7 also receives toast/alert/dialog fallback events from `streamd`. It constructs the notification center with the containing app bundle identifier, because a process-default center is not authorized even when the app has permission. While StreamControl is active it keeps the UIKit overlay; after the foreground heartbeat expires, the daemon posts a local notification. Permission can be requested explicitly from `Settings > Notification Access`.
- Keep awake: task `40` updates both the foreground app idle timer and the persistent UIKit daemon. The daemon path is best-effort because TrollStore does not provide a public global power assertion equivalent to SpringBoard injection.
- App/process: `11`, `31-35`, `50-54` via streamd plus privhelper where needed.
- Admin extension: task `72` clears safe app data containers through privhelper. It refuses protected bundles and unsafe paths.
- Shell: task `13/71` is gated by settings and disabled by default.

## Deferred Or Limited

- Keychain clearing remains deferred because arbitrary target keychain access groups require separate entitlement handling.
- VPN control remains query-only unless a profile/private entitlement path is added.
- Vision OCR remains deferred for the `420f`/worker crash issue documented in `plan.md`; task `91` Tesseract is the stable OCR path.
- Activator/Siri equivalents remain `limited_on_trollstore`.
- Full SpringBoard overlay behavior is replaced by foreground app overlays plus background local notifications. Background dialog notifications are non-interactive, and the touch indicator remains foreground-only.

## Quick Manual Checks

```powershell
Invoke-TLinkTask -HostIP $iphoneIP -Task "97"
Invoke-TLinkTask -HostIP $iphoneIP -Task "60"
Invoke-TLinkTask -HostIP $iphoneIP -Task "91check_langs"
Invoke-TLinkTask -HostIP $iphoneIP -Task "249"
```

Background visual fallback (put StreamControl in the background first):

```powershell
Invoke-TLinkTask -HostIP $iphoneIP -Task "220;;Background toast test;;3;;2;;16"
Invoke-TLinkTask -HostIP $iphoneIP -Task "12TLinkauto;;Background alert test;;3"
Invoke-TLinkTask -HostIP $iphoneIP -Task "401"
Invoke-TLinkTask -HostIP $iphoneIP -Task "249"
```

The first two calls should appear as local notifications without bringing
StreamControl to the foreground. Task `249` should report `version=7`,
`background_ui_bridge=1`, and both `notification_auth` (daemon view) and
`app_notification_auth` (the containing app view). An authorized status is `2`;
if the app status remains `0`, use `Settings > Notification Access` while the
app is active.

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
