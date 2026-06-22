# TLinkauto JavaScriptCore Runtime

Bundle manifest:

```json
{
  "runtime": "javascriptcore",
  "entry": "main.js",
  "apiVersion": 1,
  "coordinateSpace": "native-pixels"
}
```

Core APIs:

- `device.toast(message, { type, duration, position, fontSize })` shows a visible on-screen toast.
- `device.tap(x, y)`
- `device.swipe(x1, y1, x2, y2, durationMs)`
- `device.pickColor(x, y)` returns `{ ok, red, green, blue }`
- `device.screenshot()` returns `{ ok, path }`
- `device.screenshotTo(path)` returns `{ ok, path }`
- `device.frontMostAppId()` returns `{ ok, bundleId }`
- `device.frontMostPid()` returns `{ ok, pid }`
- `device.orientation()` returns `{ ok, value }`
- `device.openApp(bundleId)` launches/brings an app forward.
- `device.killApp(bundleId)` terminates an app.
- `device.appState(bundleId)` returns `{ ok, state, running }`.
- `device.appInfo(bundleId)` returns `{ ok, bundleId, name, shortVersion, bundleVersion, state }`.
- `device.appPid(bundleId)` returns `{ ok, pid }`.
- `device.appPaths(bundleId)` returns `{ ok, bundlePath, dataPath }`.
- `device.listBundles(withInfo)` returns `{ ok, bundleIds }` or `{ ok, items }`.
- `device.openUrl(url)` opens a URL through SpringBoard/UIKit.
- `device.wifi()`, `device.bluetooth()`, `device.airplaneMode()`, `device.cellularData()` query connectivity state.
- `device.setWifi(enabled)`, `device.setBluetooth(enabled)`, `device.setAirplaneMode(enabled)`, `device.setCellularData(enabled)` set connectivity state when supported by the iOS build.
- `device.alert(title, message, duration)` shows a blocking native alert.
- `device.dialog({ title, message, ok, cancel })` shows a native dialog and returns `{ ok, response }`.
- `device.clearDialogValues()` clears stored dialog value.
- `device.showKeyboard()`, `device.hideKeyboard()`, `device.insertText(text)`, `device.deleteCharacters(count)`, `device.moveCursor(offset)`, `device.pasteFromClipboard()` control the active keyboard field.
- `device.getClipboardText()` returns `{ ok, text }`.
- `device.setClipboardText(text)` writes text to the general pasteboard.
- `device.hardwareKey(key, action)` sends hardware key down/up. Keys: `home`, `volume-up`, `volume-down`, `lock`. Actions: `down`, `up`.
- `device.pressHardwareKey(key)` sends down then up.
- `device.keepAwake(enabled)` toggles idle timer.
- `device.touchIndicator(action)` supports `show`, `hide`, `reload`.
- `device.rootDir()`, `device.currentDir()`, `device.botPath()` return runtime paths.
- `device.getScreenSize()` returns `{ width, height, scale, orientation, coordinateSpace }`
- `device.runtimeInfo()` returns runtime capabilities.

Frame/image APIs use opaque numeric handles and avoid moving image bytes through JavaScript:

- `device.captureFrame({ gray, bgra, ttlMs })` returns `{ ok, id, width, height, scale, hasGray, hasBGRA }`
- `device.releaseFrame(frameId)` releases one frame.
- `device.releaseAllFrames()` releases all cached frames.
- `device.openImage(path)` returns `{ ok, id, width, height }`
- `device.captureImage(x, y, width, height)` returns `{ ok, id, width, height }`
- `device.releaseImage(imageId)` releases one image handle.
- `device.framePickColor(frameId, x, y, { coord, maxAgeMs })` returns `{ ok, red, green, blue, ageMs }`
- `device.framePickColors(frameId, points, { coord, maxAgeMs })` returns `{ ok, colors, ageMs }`
- `device.findImageInFrame(frameId, imageId, options)` returns `{ ok, matched, x, y, width, height, centerX, centerY, score, ageMs }`
- `device.ocrLanguages()` returns `{ ok, languages }` from `/var/mobile/Library/TLinkauto/tessdata`.
- `device.ocrFrame(frameId, options)` runs Tesseract OCR on a captured frame region and returns `{ ok, text, confidence, ageMs, ocrMs, preprocessMs, totalMs }`.
- `device.ocr(options)` captures a temporary gray frame, runs OCR, releases the frame, and returns the same OCR result.

`findImageInFrame` options:

- `x`, `y`, `width`, `height`
- `acceptable`, default `0.95`
- `scaleMin`, `scaleMax`, `scaleStep`, defaults `1.0`
- `pixelSkip`, default `0`
- `coord`, default `pixel`
- `maxAgeMs`, default `1000`

`ocrFrame` / `ocr` options:

- `x`, `y`, `width`, `height`, defaults to full frame for `ocr`.
- `lang`, default `vie`.
- `oem`, default `1`.
- `psm`, default `7`.
- `whitelist`, optional string.
- `scaleUp`, default `2`, clamped by native OCR implementation.
- `thresholdMode`, default `0`; native supports `0` none, `1` Otsu, `2` adaptive.
- `coord`, default `pixel`.
- `maxAgeMs`, default `1000`.
- `ttlMs`, only for `device.ocr`, default `1000`.

`device.runTask(task, payload)` remains available for internal debugging, but public scripts should prefer typed APIs.
