# TLinkauto TrollStore Script Compatibility Regression

Use this checklist when validating that a JavaScript script written for the
rootfull runtime can run through the TrollStore `streamd` facade.

## Capability Checks

```powershell
Invoke-TLinkTask -HostIP $iphoneIP -Task "97"
Invoke-TLinkTask -HostIP $iphoneIP -Task "60"
```

Expected markers:

- `script=javascriptcore_rootfull_compat_facade`
- `scriptCompatFacade`
- `scriptRunTaskAlias`
- `scriptStorageAPI`
- `scriptFileHandleAPI`
- `scriptKeyboardAPI`
- `clipboardImage`
- `clipboardUIDaemon`
- `clipboardBackgroundEntitlement`
- `clipboardForegroundBroker`
- `scriptColorFrameAPI`
- `scriptImageAPI`
- `scriptOCRAPI`
- `scriptAppAPI`
- `smartWaitState=implemented`
- `smartWaitSchema=smart_wait_result_v1`
- `imageMatch=multiscale_vimage_rgba_v2`
- `ocr=tesseract_true_static_libs_memory_fallback`

## UI Smoke

1. Open `StreamControl.app`.
2. Go to `Scripts`.
3. Create or open `Demo Script.tl`.
4. Tap Play.
5. Confirm the log contains:
   - `Rootfull compat facade smoke`
   - `screen=`
   - `pickColor=`
   - `captureFrame=`
   - `framePickColors=`
   - `screenshot=`
   - `ocrLanguages=`

Packaged example scripts:

- On first launch after install, the root `Scripts` tab seeds a
  `Compatibility Tests` folder automatically when it is missing. The folder
  contains nine editable `.tl` bundles covering runtime/storage, file handles,
  license heartbeat, background
  clipboard, color/frame, screenshot/image, Tesseract OCR, and
  app/process/shell, plus Smart Wait stable-match and timeout behavior.
  Updating an existing eight-script suite adds only the missing Smart Wait
  bundle and does not overwrite edited compatibility scripts.
- In `Scripts`, tap `+` then `Compatibility Suite` only when you want to
  install another copy of the packaged suite manually.
- Every script logs `compat/<group> start`, normalized result objects, and a
  matching `finished` marker so failures can be isolated from the script log.

## Script API Smoke

The TrollStore facade should expose these rootfull-style APIs with a normalized
object response containing `ok`, `code`, `payload`, `raw`, and parsed fields
where available:

- Touch: `tap`, `swipe`, `longPress`, `gesture`, `batch`
- Visual feedback: `toast`, `alert`, `dialog`, `clearDialogValues`, `touchIndicator`
- Timing: `sleep`, `usleep`
- Screenshot: `screenshot`, `screenshotTo`, `screenshotRegion`, `saveScreenshotToAlbum`, `clearScreenshotAlbum`
- Color/frame: `pickColor`, `findColor`, `isColors`, `findMultiColor`, `captureFrame`, `releaseFrame`, `releaseAllFrames`, `framePickColor`, `framePickColors`, `frameFindColor`, `frameIsColors`, `frameFindMultiColor`
- Image: `openImage`, `captureImage`, `releaseImage`, `findImageInFrame`, `matchTemplate`
- OCR: `ocrLanguages`, `ocrFrame`, `ocr`
- Smart Wait: `waitUntil`, `waitForApp`, `waitForColor`, `waitForImage`, `waitForText`, `waitUntilGone`, `tapWhenVisible`
- App/process: `openApp`, `killApp`, `clearAppData`, `appState`, `appInfo`, `appPid`, `frontMostAppId`, `frontMostPid`, `appPaths`, `listBundles`, `openUrl`
- Paths/info: `rootDir`, `currentDir`, `botPath`, `info`, `batteryInfo`, `getScreenSize`
- Raw task/storage: `task`, `taskResult`, `runTask`, `readText`, `writeText`, `readJSON`, `writeJSON`, `fileExists`, `deleteFile`, `openFile`
- Keyboard/shell/connectivity: `showKeyboard`, `hideKeyboard`, `pasteFromClipboard`, `getClipboardText`, `setClipboardText`, `setClipboardImage`, `insertText`, `deleteCharacters`, `moveCursor`, `runShell`, `wifi`, `setWifi`, `bluetooth`, `setBluetooth`, `airplaneMode`, `setAirplaneMode`, `cellularData`, `setCellularData`

Keyboard backend smoke:

```powershell
# Open StreamControl.app once after install so privhelper installs clipboardd v16
# on 6012. Port 6013 is clipboard fallback only.
Invoke-TLinkTask -HostIP $iphoneIP -Task "247;;hello from tlinkauto"
Invoke-TLinkTask -HostIP $iphoneIP -Task "246"
Invoke-TLinkTask -HostIP $iphoneIP -Task "249"

# Focus a text field first. These should insert, delete five characters, then
# move the cursor two positions left using HID keyboard events:
Invoke-TLinkTask -HostIP $iphoneIP -Task "241;;hello from tlinkauto"
Invoke-TLinkTask -HostIP $iphoneIP -Task "244;;5"
Invoke-TLinkTask -HostIP $iphoneIP -Task "243;;-2"
```

File-handle parity smoke:

1. Open `Scripts > Compatibility Tests > 07 File Handle.tl`.
2. Tap Play and inspect its log.
3. Confirm `open.ok=true`, both writes succeed, `readLine.data` is
   `first line`, `readRest.data` contains `second line`, and `finalText.text`
   contains the appended third line.
4. Run the same `.tl` bundle under rootfull once with the in-process runtime
   and once with the helper runtime. All three paths expose the same methods
   and normalized result objects.

`device.openFile` is bundle-relative and deliberately does not expose
arbitrary absolute paths. Writable modes cannot modify `.js`, `manifest.json`,
or `info.plist`. Handles are closed automatically when an evaluation ends.

License heartbeat smoke:

1. Open `Scripts > Compatibility Tests > 08 License Heartbeat.tl` and tap Play.
2. While it logs one heartbeat per second, revoke/deactivate the lease or
   remove it from `Settings > License`.
3. Within about one second, task `60` script status should report
   `state=license_revoked`, `license_revoked=true`, and
   `last_error=license_revoked_during_execution`.
4. The script log must contain `license_revoked_during_execution`; its open
   file handle is closed by the runtime. Reactivation permits a new run without
   restarting `streamd`.

Smart Wait smoke:

1. Open `Scripts > Compatibility Tests > 09 Smart Wait.tl` and tap Play.
2. Confirm the log reports `stable.ok=true`, `stable.attempts=3`, and
   `stable.stableMatches=2`.
3. Confirm the zero-timeout check reports `timedOut=true` and `attempts=1`.
4. Foreground app and current-screen color checks must finish without a leaked
   frame/image handle or a non-empty `last_error`.

Task `249` should contain `clipboard_backend_ready`, `version=16` in its decoded
diagnostic, and `daemon_direct_write=1` after a successful task `247`. Task
`246` should then return `0;;hello from tlinkauto`. When another app is active,
StreamControl should not appear. A short app switch means the daemon entitlement
was ignored and the foreground fallback ran.

## Known Limits

- Vision OCR CPU-only is an experimental `app_cpu`/`worker_cpu` canary; task
  `91` Tesseract remains the stable/default OCR path.
- OpenCV is not required for the MVP; image matching currently uses native RGBA.
- Keyboard API names are exposed for rootfull script compatibility. The v3
  UIDaemon failed because it lacked the private background Pasteboard entitlement,
  not because background clipboard access is categorically impossible. Version 9
  adds the entitlement set and keeps the foreground bridge only as a verified
  fallback. Insert and paste use HID `Command+V`; delete and cursor movement use
  HID Backspace and arrow keys. Show/hide keyboard still requires the rootfull
  SpringBoard keyboard observer and returns `limited_on_trollstore`.
- VPN control and arbitrary keychain clearing remain unsupported on TrollStore.
- Foreground overlays use UIKit and toast preserves position `0/1/2`.
  Background toast uses the `TLinkUIService.app` pass-through window and preserves
  position `0/1/2`; clipboardd v16 retries the native UI-service toast without
  converting it to an alert. Background alert/dialog continue through
  CFUserNotification. Dialog responses are not bridged
  back to the original synchronous task, and a global touch indicator still
  requires SpringBoard injection.
