# Smart Wait & Visual Locator v1

Smart Wait v1 adds the same bounded wait semantics to the rootfull JavaScriptCore
runtime, TrollStore `streamd` JavaScriptCore runtime, and WebTango SDK. It is an
additive script/client feature and does not change any legacy task grammar.

Current capability markers are:

```text
smartWaitState=implemented
smartWaitPhase=1
smartWaitSchema=smart_wait_result_v1
smartWaitClients=rootfull_js_trollstore_js_webtango_v1
smartWaitLocators=predicate,app,color,image,text,image_gone,tap_when_visible
smartWaitFrameStrategy=fresh_frame_per_attempt_release_always_template_open_once
smartWaitDeviceValidated=0
```

Task `60` exposes the structured policy as `smart_wait` on rootfull and as
`capabilities.smartWait*` on TrollStore. Task `97` exposes the flattened markers
above. `smartWaitDeviceValidated` remains `0` until both packaged runtimes pass
the device smoke and visual image/text checks.

## API

The following names are installed on both `device` and `TLinkauto` inside an
iOS script:

- `waitUntil(predicate, options)`
- `waitForApp(bundleId, options)`
- `waitForColor(x, y, color, options)`
- `waitForImage(imagePath, options)`
- `waitForText(text, options)`
- `waitUntilGone(imagePath, options)`
- `tapWhenVisible(imagePath, options)`

The iOS JavaScriptCore APIs are synchronous because the existing script runtime
is synchronous. WebTango exposes the same names as `async` methods and accepts
an `AbortSignal` in `options.signal`.

Common options:

| Option | Default | Limit | Meaning |
|---|---:|---:|---|
| `timeoutMs` | 5000 | 0–300000 | Total bounded wait time |
| `intervalMs` | 200 | 20–10000 | Delay between attempts |
| `stableFrames` | 1 | 1–10 | Consecutive matches required |
| `ignoreErrors` | false/true | — | Defaults false for generic predicates and true for visual locators |
| `throwOnTimeout` | false | — | Throw instead of returning a timeout result |

Even when `timeoutMs=0`, the predicate or locator is evaluated exactly once.
Cancellation is checked before each attempt and during the bounded delay.

Every method returns `smart_wait_result_v1`:

```json
{
  "schema": "smart_wait_result_v1",
  "kind": "wait_for_image",
  "ok": true,
  "found": true,
  "timedOut": false,
  "cancelled": false,
  "attempts": 3,
  "elapsedMs": 421,
  "stableMatches": 2,
  "value": {},
  "lastError": ""
}
```

`waitUntilGone` reports `gone=true` and intentionally leaves `found=false` when
it succeeds. `tapWhenVisible` reports `tapped`, `tapX`, and `tapY`; a successful
image match is not reported as a successful operation if the tap itself fails.

## Image and OCR resource policy

`waitForImage`, `waitUntilGone`, and `tapWhenVisible` open the template once for
the complete wait. Each attempt captures one fresh grayscale frame, performs
task `68` matching, and releases that frame in `finally`. The template is also
released in `finally`, including timeout, cancellation, and exception paths.

`waitForText` captures and releases one frame per attempt and uses stable task
`91` Tesseract OCR. It does not promote the experimental Vision OCR path.
Supported text match modes are `contains` (default), `equals`, and `regex`, with
case-insensitive matching by default.

## Examples

iOS rootfull/TrollStore script:

```javascript
var login = device.waitForImage("/var/mobile/Library/TLinkauto/templates/login.png", {
  timeoutMs: 10000,
  intervalMs: 200,
  stableFrames: 2,
  acceptable: 0.9
});
if (!login.ok) throw new Error("Login button not found: " + login.lastError);
device.tap(login.value.centerX, login.value.centerY);

var ready = device.waitForText("Trang chủ", {
  region: [0, 0, 1170, 500],
  lang: "vie",
  stableFrames: 2,
  timeoutMs: 15000
});
if (!ready.ok) throw new Error("Home text not found");
```

WebTango:

```javascript
const tapped = await device.tapWhenVisible(
  "/var/mobile/Library/TLinkauto/templates/login.png",
  { timeoutMs: 10000, stableFrames: 2, acceptable: 0.9, signal }
);
assert(tapped.ok && tapped.tapped, tapped.lastError || "Login button missing");

const ready = await device.waitForText("Trang chủ", {
  region: [0, 0, 390, 200],
  lang: "vie",
  matchMode: "contains",
  signal
});
assert(ready.ok, ready.lastError || "Home text missing");
```

Coordinates in an on-device script remain native pixels. WebTango uses its
existing logical-coordinate conversion before sending frame/image requests.

## Validation

Static and mocked behavioral gate:

```powershell
node scripts/check-smart-wait-v1.mjs
```

Capability-only device check:

```powershell
./scripts/Test-TLinkSmartWaitV1.ps1 `
  -HostIP "192.168.1.244" `
  -Runtime trollstore
```

Run the packaged safe smoke:

```powershell
./scripts/Test-TLinkSmartWaitV1.ps1 `
  -HostIP "192.168.1.244" `
  -Runtime trollstore `
  -RunSmoke
```

For rootfull, replace the runtime with `rootfull`. The smoke validates API
installation, stable-match accounting, a one-attempt zero timeout, foreground
app matching, and current-screen color matching. Image and OCR promotion still
requires a tester-provided template/text region and visual confirmation.
