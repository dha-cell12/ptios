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
- `device.orientation()` returns `{ ok, value }`
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

`findImageInFrame` options:

- `x`, `y`, `width`, `height`
- `acceptable`, default `0.95`
- `scaleMin`, `scaleMax`, `scaleStep`, defaults `1.0`
- `pixelSkip`, default `0`
- `coord`, default `pixel`
- `maxAgeMs`, default `1000`

`device.runTask(task, payload)` remains available for internal debugging, but public scripts should prefer typed APIs.
