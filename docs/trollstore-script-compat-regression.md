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
- Keyboard/shell/connectivity: `getClipboardText`, `setClipboardText`, `insertText`, `runShell`, `wifi`, `setWifi`, `bluetooth`, `setBluetooth`, `airplaneMode`, `setAirplaneMode`, `cellularData`, `setCellularData`

## Known Limits

- Vision OCR remains deferred; task `91` Tesseract is the stable OCR path.
- OpenCV is not required for the MVP; image matching currently uses native RGBA.
- VPN control and arbitrary keychain clearing remain unsupported on TrollStore.
- Foreground overlays replace SpringBoard injection overlays.
