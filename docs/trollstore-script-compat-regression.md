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
- `scriptKeyboardAPI`
- `clipboardImage`
- `scriptColorFrameAPI`
- `scriptImageAPI`
- `scriptOCRAPI`
- `scriptAppAPI`
- `imageMatch=naive_rgba`
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

Packaged example script:

- `examples/Rootfull Compatibility Smoke.tl` exercises `runTask`, storage,
  clipboard text, color/frame, screenshot, OCR language listing, and app state
  wrappers without changing system settings.

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
- App/process: `openApp`, `killApp`, `clearAppData`, `appState`, `appInfo`, `appPid`, `frontMostAppId`, `frontMostPid`, `appPaths`, `listBundles`, `openUrl`
- Paths/info: `rootDir`, `currentDir`, `botPath`, `info`, `batteryInfo`, `getScreenSize`
- Raw task/storage: `task`, `taskResult`, `runTask`, `readText`, `writeText`, `readJSON`, `writeJSON`, `fileExists`, `deleteFile`
- Keyboard/shell/connectivity: `showKeyboard`, `hideKeyboard`, `pasteFromClipboard`, `getClipboardText`, `setClipboardText`, `setClipboardImage`, `insertText`, `deleteCharacters`, `moveCursor`, `runShell`, `wifi`, `setWifi`, `bluetooth`, `setBluetooth`, `airplaneMode`, `setAirplaneMode`, `cellularData`, `setCellularData`

Keyboard backend smoke:

```powershell
Invoke-TLinkTask -HostIP $iphoneIP -Task "247;;hello from tlinkauto"
Invoke-TLinkTask -HostIP $iphoneIP -Task "246"

# TrollStore currently reports limited for these instead of silent success:
Invoke-TLinkTask -HostIP $iphoneIP -Task "241;;hello from tlinkauto"
Invoke-TLinkTask -HostIP $iphoneIP -Task "244;;5"
Invoke-TLinkTask -HostIP $iphoneIP -Task "243;;-2"
```

## Known Limits

- Vision OCR remains deferred; task `91` Tesseract is the stable OCR path.
- OpenCV is not required for the MVP; image matching currently uses native RGBA.
- Keyboard API names are exposed for rootfull script compatibility. TrollStore
  supports clipboard text and native `UIPasteboard` clipboard images. Insert,
  paste, delete, cursor movement, and show/hide keyboard require the rootfull
  SpringBoard keyboard observer and return `limited_on_trollstore` instead of
  silent success.
- VPN control and arbitrary keychain clearing remain unsupported on TrollStore.
- Foreground overlays replace SpringBoard injection overlays.
