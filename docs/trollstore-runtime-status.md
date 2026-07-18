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
- Script runtime: task `19/20` JavaScriptCore with a rootfull compatibility facade for common `device.*` APIs, `runTask`/task bridge, normalized storage responses, shared rootfull/TrollStore `device.openFile` handles, keyboard wrappers, color/frame/image/OCR wrappers, and app/process wrappers.
- Service bootstrap: opening StreamControl always ensures `streamd` is running. Task `97` exposes `serviceVersion=23`; the app replaces a responding process when its version is stale, its executable path is no longer resolvable, or it belongs to an older app bundle, then starts the bundled binary through `privhelper`. OCR workers, license config, and helper commands also resolve the currently installed bundle so a TrollStore reinstall does not leave them pointing at removed container.
- License MVP: Settings > License activates a Cloudflare Worker lease using a Secure Enclave P-256 device key with a `ThisDeviceOnly` Keychain fallback. Task `75` returns signed-lease status and task `76` forces a fresh check. `streamd`, H264 accepts, and sensitive `privhelper` commands enforce feature access when the release is built with license enforcement enabled. Initial test builds remain in observe mode.
- License lifecycle: `LicenseLifecycleCoordinator` refreshes a valid lease inside its final six hours and refreshes `offline_grace` immediately on foreground/BGTask triggers. Requests are single-flight with persisted exponential backoff and jitter at `/var/mobile/Library/TLinkauto/runtime/license_lifecycle.plist`. Activation, refresh, deactivate, and local removal invalidate app/streamd state through task `76` plus a Darwin signal; they do not restart `streamd`. Settings > License exposes server-side device deactivation separately from local recovery removal.
- License coherence: every successful lease save/remove atomically advances `/var/mobile/Library/TLinkauto/license/generation` under a cross-process file lock and posts `com.tlinkauto.license.changed`. The shared verifier used by app, `streamd`, H264, clipboardd and privhelper invalidates on that signal and also compares generation on every feature request. Task `76` advances generation when called without a body; `76reload` reloads without incrementing. Task `60/75/97` expose generation/source diagnostics.
- License runtime enforcement: task mapping is an explicit fail-closed C policy table checked against `license-task-policy.json`. Legacy task `10` remains fire-and-forget and increments `license_enforcement.task10_drop_count` when denied. Active H264 clients recheck `stream` every 5 seconds. Script sessions recheck `script` every second; revoke/expiry sets `stopRequested`, closes open script files and records `license_revoked_during_execution`. Timer and startup autolaunch paths call the same gated script launcher.
- License recovery: malformed or signature-corrupt `lease.json` is moved to `/var/mobile/Library/TLinkauto/license/quarantine/` under the generation lock and recorded in `recovery.plist`; runtime remains fail-closed. Settings > License reports private/public key presence and can rebuild a missing or damaged `device_public_key.bin` from the existing Keychain/Secure Enclave private key without allocating a new server slot. Device-limit errors include active/max counts and direct the user to deactivate the old device or request an admin reset. Task `60/75/97` expose recovery state and the 60-second not-before clock tolerance; large clock rollback hardening remains deferred.
- License release validation: CI builds separate observe/enforced TIPAs, embeds `observe_compile_time_v1` or `enforced_compile_time_v1` in every process, validates the packaged public config and service v23, scans for signing/admin secret markers, and publishes a SHA-256 manifest. Device regression and 24/72-hour soak evidence remain mandatory before release.
- Respring: Settings exposes a destructive-confirmation Respring Device action backed by task `74confirm` and `privhelper --respring`. The helper requires effective UID 0, validates the SpringBoard process name/path, sends SIGTERM, and only falls back to SIGKILL if the validated original PID remains alive.
- Update recovery: task `60` reports `launch_executable_path`, `capabilities.installedBundlePath`, `capabilities.resolvedStreamdPath`, and `capabilities.resolvedPrivhelperPath`. These paths should all belong to the currently installed `StreamControl.app`; opening the app replaces a daemon launched from an older TrollStore container.
- Color compatibility: frame and non-frame point tables accept both rootfull `x,,y,,r,,g,,b` entries and facade `x,y,r,g,b` entries.
- Shell fallback: when stock iOS has no `/bin/sh`, the gated mini-shell supports diagnostics plus quoted `cp` and `printf ... > file` operations. Respring does not use this shell fallback.
- Main navigation now has only Scripts and Settings tabs. The old Service tab was removed; Settings exposes Restart streamd and Respring Device directly, keeps Runtime Settings on the main page, and moves the previous diagnostics/compatibility matrix behind a DEBUG row.
- Script UI management: normal folders expose a visible ellipsis menu with Rename Folder, Duplicate, and Delete Folder. The Logs screen includes a confirmed Clear Log action backed by task `73`; it clears the current session log buffer while allowing a running script to append new lines afterward.
- Background recovery: after StreamControl has been opened once, it registers and submits `BGAppRefreshTask` plus `BGProcessingTask` requests. When iOS grants execution, the handler reschedules itself, calls the same supervisor/privhelper path, and completes only after tcp/6000 passes the service-version probe. This is `best_effort_bgtaskscheduler_after_first_launch`, not guaranteed boot startup. Scheduling/firing/completion diagnostics are stored in `/var/mobile/Library/TLinkauto/runtime/background_service_scheduler.plist` and included by Settings > Export Diagnostics.
- Script regression suite: the root `Scripts` tab auto-seeds a `Compatibility Tests` folder from packaged examples on first launch; `Scripts > + > Compatibility Suite` can install another copy manually. The eight `.tl` bundles exercise each compatibility API group independently, including shared file handles and license-revocation heartbeat behavior.
- Keyboard/text: task `24` uses `clipboardd` v12 on port `6012` with private background Pasteboard entitlements and the same signed-license gate as `streamd`. Every write is read-back verified before `streamd` trusts daemon reads. Subtask `1` inserts text using background clipboard plus HID `Command+V`; subtask `5` pastes the existing clipboard; subtasks `3/4` use HID arrows and Backspace. Devices that ignore the Pasteboard entitlements fall back to the foreground app bridge on port `6013`. Show/hide keyboard remains `limited_on_trollstore` because it needs the rootfull SpringBoard keyboard observer.
- Background UI bridge: `clipboardd` v12 receives toast/alert/dialog fallback events from `streamd`. Device validation proved that a UIDaemon `UIWindow` can exist in memory without being compositor-hosted above the active app, so that path is no longer reported as successful. Background toast/alert/dialog now use `CFUserNotificationDisplayAlert`. Background toast is visible but fixed at the system center; the rootfull position argument is preserved only for foreground UIKit toast and is reported as limited in background responses.
- Keep awake: task `40` updates both the foreground app idle timer and the persistent UIKit daemon. The daemon path is best-effort because TrollStore does not provide a public global power assertion equivalent to SpringBoard injection.
- App/process: `11`, `31-35`, `50-54` via streamd plus privhelper where needed.
- Admin extension: task `72` clears safe app data containers through privhelper. It refuses protected bundles and unsafe paths.
- Shell: task `13/71` is gated by settings and disabled by default.

## Deferred Or Limited

- Keychain clearing remains deferred because arbitrary target keychain access groups require separate entitlement handling.
- VPN control remains query-only unless a profile/private entitlement path is added.
- Vision OCR remains deferred for the `420f`/worker crash issue documented in `plan.md`; task `91` Tesseract is the stable OCR path.
- Activator/Siri equivalents remain `limited_on_trollstore`.
- Full SpringBoard overlay behavior is replaced by foreground app overlays plus background CFUserNotification system notices/alerts. The dialog result is not bridged back to the original synchronous task, and the touch indicator remains foreground-only.
- True immediate startup at boot remains unavailable on TrollStore. Background task execution is controlled by iOS, may be delayed, requires the app to have been opened once, and does not replace a platformized LaunchDaemon. Force-quitting StreamControl can prevent iOS background relaunch until the app is opened again.

## Quick Manual Checks

Background recovery registration (open StreamControl once after installing the
new build, then decode task `60` and inspect `background_service`):

```powershell
$raw = Invoke-TLinkTask -HostIP $iphoneIP -Task "60"
$b64 = ($raw -replace '^0;;', '').Trim()
$json = [Text.Encoding]::UTF8.GetString([Convert]::FromBase64String($b64)) | ConvertFrom-Json
$json.service_version
$json.capabilities.backgroundAutoStartMode
$json.background_service | Format-List
```

Expected immediately after first launch: service version `22`, both
`refresh_registered` and `processing_registered` are true, and both submit
results are true. A later `last_fired_at_ms` plus `last_result=success` proves
that iOS actually launched a handler; submit success alone does not prove a
post-reboot launch. Do not force-quit StreamControl before this test. Reboot,
unlock once, then probe port 6000 periodically because iOS does not promise an
exact execution time. The same state is visible at Settings > Background
Service Status and Settings > Export Diagnostics.

License lifecycle check (activate from Settings > License, without pressing
Restart streamd):

```powershell
$raw = Invoke-TLinkTask -HostIP $iphoneIP -Task "60"
$b64 = ($raw -replace '^0;;', '').Trim()
$json = [Text.Encoding]::UTF8.GetString([Convert]::FromBase64String($b64)) | ConvertFrom-Json
$json.service_version
$json.license | Format-List
$json.license_lifecycle | Format-List
Invoke-TLinkTask -HostIP $iphoneIP -Task "75"
```

Expected: service version `22`, activation becomes effective without a manual
restart, `last_change_reason=activation`, and `streamd_invalidate_response`
starts with `0;;`. Use a test Worker with a short `LEASE_SECONDS` value to
exercise the six-hour refresh window and backoff. `Deactivate This Device`
must change task `75` to `not_activated` and release the Worker device slot.

Cross-process generation check:

```powershell
function Get-TLinkLicenseStatus {
    param([string]$Task = "75")
    $raw = Invoke-TLinkTask -HostIP $iphoneIP -Task $Task
    $b64 = ($raw -replace '^0;;', '').Trim()
    [Text.Encoding]::UTF8.GetString([Convert]::FromBase64String($b64)) | ConvertFrom-Json
}

$before = Get-TLinkLicenseStatus
$advanced = Get-TLinkLicenseStatus -Task "76"
$reloaded = Get-TLinkLicenseStatus -Task "76reload"
$before.license_generation
$advanced.license_generation
$advanced.generation_action
$reloaded.license_generation
$reloaded.generation_action
```

Expected: `76` increments generation and reports `advance`; `76reload` keeps
the same value and reports `reload`. Activation/deactivation from the app must
also increase generation and become visible on port 6000 without restart.

```powershell
Invoke-TLinkTask -HostIP $iphoneIP -Task "97"
Invoke-TLinkTask -HostIP $iphoneIP -Task "60"
Invoke-TLinkTask -HostIP $iphoneIP -Task "75"
Invoke-TLinkTask -HostIP $iphoneIP -Task "91check_langs"
Invoke-TLinkTask -HostIP $iphoneIP -Task "249"
```

Background visual fallback (put StreamControl in the background first):

```powershell
Invoke-TLinkTask -HostIP $iphoneIP -Task "220;;Background toast v12;;3;;2;;16"
Invoke-TLinkTask -HostIP $iphoneIP -Task "12TLinkauto;;Background alert test;;3"
Invoke-TLinkTask -HostIP $iphoneIP -Task "401"
Invoke-TLinkTask -HostIP $iphoneIP -Task "249"
```

The toast and alert should appear without bringing StreamControl to the
foreground. Task `249` should report `version=12`,
`background_visual_mode=cfusernotification_toast_alert_fixed_center`, the
requested toast position, and `toast_effective_position=center`. A background
position other than center remains `limited_on_trollstore`; arbitrary global
positioning needs a proven SpringBoard/BackBoard compositor-hosting mechanism.

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
