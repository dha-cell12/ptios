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

Manifest validation:

- JavaScript bundles support `apiVersion: 1`.
- `coordinateSpace` must be omitted or set to `native-pixels`.
- The manifest object is available at global `manifest`.
- `device.runtimeInfo()` includes manifest runtime, entry, apiVersion, and coordinateSpace metadata.

Helper runtime opt-in:

- Phase 2 can run pure JavaScript in the separate `tlinkauto-jsd` helper process.
- Enable it per bundle with `"helperRuntimeEnabled": true` or `"runtimeLocation": "helper"`.
- For safety during Phase 2, helper execution is additionally gated by marker file `/var/mobile/Library/TLinkauto/enable_js_helper_execution`.
- Phase 2 helper runs have a default 10 second timeout; override with `"helperTimeoutMs": 30000`.
- Helper execution currently supports pure JS, `console`, `sleep`, `require`, `include`, and `device.runtimeInfo()`.
- Native `device.*` automation APIs still run through the default in-process runtime unless a future phase enables native RPC.
- Helper logs are written to `_logs/<runId>-helper.log` and `_logs/latest-helper.log`.

Bundle modules:

- `require("./file")` loads `.js`, `.json`, or `index.js` files relative to the current module.
- `include("./file")` evaluates a bundle-relative `.js` file without CommonJS exports.
- Module paths are sandboxed to the current `.bdl` directory.
- Absolute paths, `..` escapes, and files larger than 512 KiB are rejected.
- Only `.js` and `.json` files are loadable through the module loader.

Bundle storage APIs:

- `device.readText(path)` returns `{ ok, path, text }`.
- `device.writeText(path, text)` writes UTF-8 text and returns `{ ok, path, bytes }`.
- `device.readJSON(path)` returns `{ ok, path, value }`.
- `device.writeJSON(path, value)` writes a JSON object or array.
- `device.fileExists(path)` returns `{ ok, path, exists, directory }`.
- `device.deleteFile(path)` deletes a bundle-relative file.
- Storage paths are sandboxed to the current `.bdl` directory.
- Writes reject `manifest.json`, `info.plist`, `.js` source files, path escapes, and files larger than 512 KiB.

Console file logs:

- `console.log/info/warn/error` writes to system `NSLog` and bundle files.
- Current run log: `_logs/<runId>.log` inside the `.bdl` bundle.
- Latest run log: `_logs/latest.log` inside the `.bdl` bundle.
- `device.runtimeInfo()` includes `consoleLogPath` and `consoleLatestLogPath`.
- Console log files rotate by deletion when they exceed 512 KiB.

Runtime helpers:

- `TLinkauto.version` exposes the helper API version.
- `TLinkauto.assert(condition, message)` throws an error when `condition` is false.
- `TLinkauto.ensureOk(result, message)` throws when a typed API result is missing or has `ok: false`, otherwise returns the result.
- `TLinkauto.waitUntil(predicate, { timeoutMs, intervalMs })` polls synchronously until `predicate(attempt)` returns a truthy value or timeout expires.
- `TLinkauto.retry(action, { retries, delayMs })` retries a synchronous action and returns `{ ok, value, attempts }` or `{ ok, error, attempts }`.
- `TLinkauto.waitForApp(bundleId, options)` waits until the frontmost app matches `bundleId`.
- `TLinkauto.waitForColor(x, y, { red, green, blue }, { timeoutMs, intervalMs, tolerance })` waits until a screen pixel matches the target color.
- `TLinkauto.withFrame(options, callback)` captures a frame, passes it to `callback(frame)`, and releases it in `finally`.
- `TLinkauto.withImage(path, callback)` opens an image handle and releases it in `finally`.
- `TLinkauto.withCapturedImage(x, y, width, height, callback)` captures an image handle and releases it in `finally`.

Core APIs:

- `device.toast(message, { type, duration, position, fontSize })` shows a visible on-screen toast.
- `device.tap(x, y)`
- `device.longPress(x, y, durationMs)`
- `device.swipe(x1, y1, x2, y2, durationMs)`
- `device.gesture(points, { finger, duration })`, where points are `[x, y]` arrays or `{ x, y }` objects.
- `device.pickColor(x, y)` returns `{ ok, red, green, blue }`
- `device.screenshot()` returns `{ ok, path }`
- `device.screenshotTo(path)` returns `{ ok, path }`
- `device.screenshotRegion(path, { x, y, width, height })` saves a cropped screenshot and returns `{ ok, path, x, y, width, height }`.
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
- `device.info()` returns `{ ok, name, systemName, systemVersion, model, identifierForVendor }`.
- `device.batteryInfo()` returns `{ ok, state, level }`.
- `device.runShell(command)` runs a privileged shell command through `tlinkautob` and returns `{ ok, output }`. Use for debugging/admin scripts only.
- `device.saveScreenshotToAlbum(path)` saves an image to the TLinkauto Photos album.
- `device.clearScreenshotAlbum()` clears the TLinkauto Photos album.
- `device.matchTemplate(path, { maxTryTimes, acceptable, scaleRatio })` returns `{ ok, matched, x, y, width, height, centerX, centerY }`.
- `device.findColor(options)` searches the current screen and returns `{ ok, matched, x, y, red, green, blue }`.
- `device.isColors(points, { mode, value, tolerance })` checks absolute point colors and returns `{ ok, matched }`.
- `device.findMultiColor(points, { x, y, width, height, mode, value, tolerance, skip })` searches for a relative multi-point color pattern and returns `{ ok, matched, x, y }`.
- `device.setAutoLaunch(name, script, enabled)` configures auto-launch metadata.
- `device.listAutoLaunch()` returns `{ ok, items }`.
- `device.setTimer(name, interval, repeat, script)` schedules a script timer.
- `device.removeTimer(name)` removes a scheduled script timer.
- `device.batch(commands)` supports typed `tap`, `swipe`, and `gesture` commands, plus allowlisted raw native commands `62`, `63`, `64`.
- `device.getScreenSize()` returns `{ width, height, scale, orientation, coordinateSpace }`
- `device.runtimeInfo()` returns runtime capabilities.

Frame/image APIs use opaque numeric handles and avoid moving image bytes through JavaScript:

Frame/image handles created by JavaScript are auto-released when the script exits. Explicit `releaseFrame` / `releaseImage` is still recommended for long-running scripts that create many handles.

- `device.captureFrame({ gray, bgra, ttlMs })` returns `{ ok, id, width, height, scale, hasGray, hasBGRA }`
- `device.releaseFrame(frameId)` releases one frame.
- `device.releaseAllFrames()` releases all cached frames.
- `device.openImage(path)` returns `{ ok, id, width, height }`
- `device.captureImage(x, y, width, height)` returns `{ ok, id, width, height }`
- `device.releaseImage(imageId)` releases one image handle.
- `device.framePickColor(frameId, x, y, { coord, maxAgeMs })` returns `{ ok, red, green, blue, ageMs }`
- `device.framePickColors(frameId, points, { coord, maxAgeMs })` returns `{ ok, colors, ageMs }`
- `device.frameFindColor(frameId, options)` searches a cached frame and returns `{ ok, matched, x, y, red, green, blue, ageMs }`.
- `device.frameIsColors(frameId, points, options)` checks absolute point colors in a cached frame and returns `{ ok, matched, ageMs }`.
- `device.frameFindMultiColor(frameId, points, options)` searches for a relative multi-point color pattern in a cached frame and returns `{ ok, matched, x, y, ageMs }`.
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
