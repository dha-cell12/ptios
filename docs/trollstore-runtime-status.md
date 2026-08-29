# TLinkauto TrollStore Runtime Status

This document captures the current implemented state of the `stream-app`
TrollStore runtime.

## Implemented

- Task server: port `6000`, legacy line protocol, success `0;;...`, error `-1;;...`.
- H.264 stream: ports `7001-7006`.
- Core automation: touch `10/61-65`, sleep `18`, device info `25`, screenshot `29`.
- Zoom P0 freezes an additive task `64` contract for two- or three-finger
  pinch/spread while leaving legacy task `64` and raw task `10` unchanged.
  This remains the historical contract baseline; see
  `docs/zoom-p0-baseline.md`.
- Zoom P1 implements that contract in `experimental` state. It preflights all
  generated coordinates, then emits synchronized down/move/up parent frames
  for two or three equally spaced fingers and performs best-effort all-fingers
  cleanup on an Objective-C dispatch exception. Task `10/64/65` legacy paths
  remain unchanged. Device promotion evidence is pending; see
  `docs/zoom-p1-multitouch.md`.
- Zoom P2 adds process-lifetime task `60` diagnostics for attempt/success/
  rejection/exception counts, exact HID parent-frame accounting, and last-run
  parameters. WebTango now has a timeout-aware `TLinkautoDeviceSdk.zoom()` API,
  editor types/completion, and Zoom in/out snippet actions. Capability remains
  `experimental` with device validation pending; see
  `docs/zoom-p2-observability-webtango.md`.
- Smart Wait v1 installs the same bounded `waitUntil`, `waitForApp`,
  `waitForColor`, `waitForImage`, `waitForText`, `waitUntilGone`, and
  `tapWhenVisible` APIs in rootfull JavaScriptCore, TrollStore JavaScriptCore,
  and WebTango. Image locators keep one template handle for the wait and use a
  fresh, always-released frame per attempt; text locators retain stable task 91
  Tesseract as the OCR engine. The implementation is present while device
  promotion remains pending; see `docs/smart-wait-visual-locator-v1.md`.
- Secure Pairing P0 freezes the current unauthenticated network baseline and
  additive `ZXSP` JSON wire contract v1 for rootfull and TrollStore. It defines
  local-UI QR bootstrap, mutual P-256 identity/ephemeral proof, AES-256-GCM
  sessions, replay rules, scopes, revocation, and downgrade policy. Runtime
  behavior remains `contract_only`/`observe_only`; legacy clients are unchanged
  and no pairing claim is device-validated. See
  `docs/secure-pairing-p0-baseline.md`.
- Run History & Failure Evidence v1 persists the newest 50 script runs with a
  common rootfull/TrollStore schema. Failed and license-revoked runs retain a
  bounded log tail, original error, evidence JSON and best-effort screenshot;
  capture failure is recorded without hiding the script failure. Task `60`,
  StreamControl Logs and WebTango expose the newest records. Device promotion
  remains pending; see `docs/run-history-failure-evidence-v1.md`.
- Event Channel v1 exposes task `95` long-poll with cursor resume, explicit
  retention-gap reporting and a bounded shared journal. `script.run` lifecycle
  events are available to rootfull, TrollStore and WebTango without blocking
  normal task dispatch. Device promotion remains pending; see
  `docs/event-channel-v1.md`.
- Adaptive Streaming v1 accepts bounded WebTango health feedback on licensed
  task `94`, selects `high`, `balanced` or `survival` FPS/bitrate with
  hysteresis, and performs bounded encoder/client recovery. Existing H264
  ports and ZXH2 framing are unchanged. Device promotion remains pending; see
  `docs/adaptive-streaming-self-healing-v1.md`.
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
- Keyboard/text: task `24` uses `clipboardd` v16 on port `6012` with private background Pasteboard entitlements and the same signed-license gate as `streamd`. Every write is read-back verified before `streamd` trusts daemon reads. Subtask `1` inserts text using background clipboard plus HID `Command+V`; subtask `5` pastes the existing clipboard; subtasks `3/4` use HID arrows and Backspace. Devices that ignore the Pasteboard entitlements fall back to the foreground app bridge on port `6013`. Show/hide keyboard remains `limited_on_trollstore` because it needs the rootfull SpringBoard keyboard observer.
- Background UI bridge: `clipboardd` v16 sends toast to the hidden nested `TLinkUIService.app` on port `6017`. Toast uses this route in both foreground and background so a fresh app heartbeat cannot swallow an immediate script toast. The service runs as mobile, owns a secure pass-through host window at level `10000010` and a separate toast overlay at level `20000099.9`, supports top/center/bottom placement, and is declared for lock-screen UI. `privhelper` and `clipboardd` launch the executable directly with a mobile identity; they do not register it as a normal SpringBoard foreground app. A starting service receives bounded native-toast retries; `device.toast` is never converted into a system alert. Explicit alert/dialog requests retain `CFUserNotificationDisplayAlert`. This path does not inject SpringBoard or load Substrate.
- UI-service hosted lifecycle (v10): the service initializes GraphicsServices and BackBoardServices, instantiates `TLinkUIServiceApplication` as the principal `UIApplication`, makes its pass-through host window visible, creates a foreground `FBScene`, attaches that scene to `UIRootWindowScenePresentationBinder`, and only then creates the separate toast overlay. The scene settings use the main display, reference bounds, level `1`, portrait orientation, `SystemApp` occlusion exemption, and are refreshed every two seconds. The readiness probe accepts the hosted two-window lifecycle without incorrectly requiring the non-key toast overlay to be the key window. An explicit **Restart streamd** brings port `6000` up first, then performs UI/clipboard/VPN recovery in a detached helper so auxiliary startup cannot block streamd.
- Keep awake: task `40` updates both the foreground app idle timer and the persistent UIKit daemon. The daemon path is best-effort because TrollStore does not provide a public global power assertion equivalent to SpringBoard injection.
- App/process: `11`, `31-35`, `50-54` via streamd plus privhelper where needed.
- Admin extension: task `72` clears safe app data containers through privhelper. It refuses protected bundles and unsafe paths.
- Shell: task `13/71` is gated by settings and disabled by default.
- VPN P0 freezes the task `59` wire contract and exposes explicit task
  `60/97` capability markers. The historical P0 TrollStore backend was an
  interface query heuristic; profile creation and connect/disconnect were
  unsupported in that phase. VPN
  configuration and credentials are local-UI/Keychain only and are forbidden
  on port `6000`. See `docs/vpn-p0-baseline.md`.
- VPN P1 implements read-only task `592` diagnostics as base64 JSON using the
  same shared module as rootfull. It probes the current process with
  `SecTaskCopyValueForEntitlement`, checks NetworkExtension framework/class
  availability without exercising manager APIs, and reports the interface
  heuristic as `effective_connected`. Production entitlements and action `1`
  control were unchanged in that historical phase; see
  `docs/vpn-p1-diagnostics.md`.
- VPN P3 adds a foreground-only `NEVPNManager` candidate in StreamControl.
  The app carries the experimental `allow-vpn` entitlement and listens only
  on `127.0.0.1:6015`; streamd remains unentitled, forwards fixed task `59`
  commands, and preserves the interface query fallback. The capability stays
  `foreground_candidate` until device diagnostics prove the entitlement,
  profile lifecycle, terminal transitions, and real traffic. Live control was
  reported working on 2026-08-01. See `docs/vpn-p3-trollstore-foreground.md`.
- VPN P4 promotes the path to `app_side_control` and adds opt-in
  `NEOnDemandRuleConnect` auto-reconnect in the local Managed VPN UI. Task
  `591;;0` disables on-demand before stopping, while task `59` remains wire
  compatible and cannot carry credentials or policy changes. See
  `docs/vpn-p4-on-demand.md`.
- VPN P5 adds a dedicated `vpnagent` on loopback port `6016`.
  `privhelper` starts it with the mobile persona (UID/GID 501), and task 59
  tries it before the existing foreground app broker. It carries the same
  app identity, VPN entitlement, and Keychain group but accepts no profile or
  credential input. Device evidence promoted the state to `background_control`:
  agent v2 ran with UID/GID 501 and completed background connect/query; see
  `docs/vpn-p5-background-agent.md`.

## Deferred Or Limited

- Keychain clearing remains deferred because arbitrary target keychain access groups require separate entitlement handling.
- VPN P5 still requires a one-time foreground bootstrap after a fresh install
  or lost profile: enter the IKEv2 credentials locally, tap Save Profile, and
  accept the iOS VPN prompt. Afterward fresh task `591` requests use the mobile
  `vpnagent` without keeping the app foreground. A force-quit, reboot, deleted
  profile, or stripped entitlement can require reopening StreamControl or
  using the foreground/manual Settings fallback.
- Vision OCR CPU-only remains experimental for the former `420f`/worker crash issue documented in `plan.md`; task `91` Tesseract is still the stable/default OCR path. P1 keeps the CPU-only `app_cpu`/`worker_cpu` profiles. After the 2026-08-29 crash report identified `CI::GLContext` initialization in the headless root worker, P2 routes opt-in `xxt_compat` to the foreground app on port `6011`. The app uses a plain Vision request, compact BGRA `0x2002`, and automatic compute selection; background requests fail closed with `app_ocr_requires_foreground`. The 21:17 device probe reached `uid=501`, `state=0` and then returned `420f (-6662)`, so the current canary adds the focused IOSurface/IOAccel/AGX entitlement set plus a five-mode Core Video allocation probe. Task `273/274` reads/clears its bounded debug log. See `docs/ocr-p1-cpu-only.md` and `docs/ocr-p2-xxt-compat.md`.
- Activator/Siri equivalents remain `limited_on_trollstore`.
- Full SpringBoard injection remains absent. Foreground and background toast use `TLinkUIService.app` with bounded native retry, while explicit alert/dialog requests continue through system alerts. Dialog results are not bridged back to the original synchronous task, and the touch indicator remains foreground-only.
- Widget-assisted boot wake is implemented for the TrollStore build. `TLinkBootWidget.appex` invokes its wake helper from both non-preview snapshots and repeating timelines, checks task port `6000`, then tries the private full SpringBoardServices launch API with the unlock option, the simple SBS launch API, and LaunchServices in that order. It deliberately does not gate the wake attempt on a `/var/mobile` marker that may be unavailable before first unlock. Settings -> Boot Script stores the selected JavaScript as the priority `00-boot-script` autolaunch entry; disabling Boot Script prevents script execution but does not disable the widget's service wake-lock behavior. The widget displays the latest wake result and writes `/var/mobile/Library/TLinkauto/runtime/widget_boot_wake.plist`. This path remains best effort because WidgetKit controls actual refresh/launch timing; it is not a platformized LaunchDaemon. BGTaskScheduler remains the fallback after first launch.

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

Background visual service (put StreamControl in the background first):

```powershell
Invoke-TLinkTask -HostIP $iphoneIP -Task "220;;Background toast v15;;3;;2;;16"
Invoke-TLinkTask -HostIP $iphoneIP -Task "12TLinkauto;;Background alert test;;3"
Invoke-TLinkTask -HostIP $iphoneIP -Task "401"
Invoke-TLinkTask -HostIP $iphoneIP -Task "249"
```

The toast and alert should appear without bringing StreamControl to the
foreground. In **Settings -> DEBUG**, `Toast UI Service Status` should decode a
live `uiservice_ready;;version=10` response containing `uid=501`, `euid=501`,
`launch_mode=UIKitPluginHostedFrontBoardSceneTwoWindow`, `plugin_complete=1`,
`foreground_scene_setup_succeeded=1`, `foreground_scene_is_foreground=1`,
`presentation_binder_created=1` and `host_window_ready=1`; `window_ready` changes
to `1` after the first toast request, and
`passthrough=1`; `Show Background Toast Test` sends task
`2412`. Task `249` should report `version=16` and
`background_visual_mode=uiservice_positioned_toast_native_retry`.
The persisted service state is
`/var/mobile/Library/TLinkauto/runtime/uiservice_toast.plist`. If the response
instead says `background_visual_uiservice_retry_queued`, collect that plist
and `/var/mobile/Library/TLinkauto/uiservice.log`. This means port `6017` was
still starting and clipboardd queued bounded retries; it must not show an alert.

Direct Volume Up trigger:

1. Keep **Settings -> Double-click Popup** enabled.
2. Put StreamControl in the background or lock the screen.
3. Press and release Volume Up twice; each press must be shorter than 400 ms,
   with at most 500 ms between releases.
4. Confirm that `Launch / Record / Cancel` appears. Launch must list scripts;
   Record starts task `14` and a later Record selection stops/saves via task
   `15`.

Task `249` should show `volume_hid_listener=1`,
`volume_listener_state=registered_keyboard_page_12_usage_233`, and increment
`volume_double_clicks`; it should also report `mobile_identity=1`. The same state is persisted in
`/var/mobile/Library/TLinkauto/runtime/volume_trigger.plist`. This is a direct
IOHID observer in `clipboardd` v15 and does not require Substrate or an
Activator listener.

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
