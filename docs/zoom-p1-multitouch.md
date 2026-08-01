# Zoom P1 — experimental multi-touch dispatch

> Historical implementation milestone: P2 keeps this gesture behavior and adds
> task `60` counters plus WebTango integration. See
> `docs/zoom-p2-observability-webtango.md`.

## Implemented result

Zoom P1 implements the additive task `64` contract frozen by P0 on both
rootfull and TrollStore. It is marked `experimental`, not production-ready,
until device evidence confirms the visual result and three-finger interaction
with iOS system gestures.

```text
64zoom;;center_x;;center_y;;start_radius;;end_radius;;duration_ms;;finger_count;;steps[;;angle_degrees;;base_finger]\r\n
```

`end_radius > start_radius` produces a spread and the reverse produces a
pinch. `finger_count` is exactly `2` or `3`. Defaults are angle `0` degrees and
base finger `0`.

## Geometry and timing

Fingers are equally spaced around a circle. At each step, radius is linearly
interpolated between the two requested radii while center and angle stay fixed.
`steps` includes both endpoints:

- Step `0`: one parent HID frame containing `DOWN` for every finger.
- Steps `1..steps-1`: one parent frame per step containing `MOVE` for every
  finger. The final move reaches `end_radius` exactly.
- Completion: one parent frame containing `UP` for every finger.

The interval is `duration_ms / (steps - 1)`, so requested duration measures
from the down frame to the final move. The up frame follows immediately.

## Validation and cleanup

Before the first down frame, both runtimes strictly parse and validate every
field, generate every step, and verify every point against the native screen
bounds. There is no coordinate clamping in the Zoom path. Limits remain those
frozen in P0:

- Duration: `50..5000` ms.
- Steps: `2..120`.
- Radius: positive and start must differ from end.
- Angle: `-360..360` degrees.
- Finger indexes: the complete contiguous range must fit `0..19`.

An invalid request returns a stable `-1;;zoom_*` error before any HID event.
After down, an Objective-C dispatch exception triggers a best-effort frame that
lifts every selected finger. The existing synchronous task path has no remote
cancellation signal; client disconnect does not interrupt an already accepted
gesture, which prevents a mid-gesture disconnect from abandoning held fingers.

Legacy task `10`, single-finger task `64`, and sequential task `65` behavior is
unchanged. Task `64` remains protected by the existing `automation` license
gate.

## Capability markers

Task `97` reports:

```text
multiTouchRaw=legacy_task10_parent_frames
zoomState=experimental
zoomTask=64
zoomWire=task64_additive_zoom_v1
zoomFingerCounts=2,3
zoomBackend=legacy_multitouch_parent_frames
zoomPhase=1
zoomGeometry=radial_linear_interpolation_v1
zoomValidation=preflight_bounds_v1
zoomCleanup=all_fingers_up_on_exception_v1
zoomDeviceValidated=0
```

Task `60` exposes equivalent structured fields. `zoomDeviceValidated=0` must
remain until both runtime builds pass the device procedure below.

## Client usage

Raw PowerShell request:

```powershell
Invoke-TLinkTask -HostIP $iphoneIP `
  -Task "64zoom;;375;;667;;60;;160;;300;;2;;20"
```

Python:

```python
ok, result = device.zoom(
    center_x=375,
    center_y=667,
    start_radius=60,
    end_radius=160,
    duration_ms=300,
    finger_count=2,
    steps=20,
)
```

On-device JavaScript (rootfull and TrollStore):

```javascript
const result = device.zoom(375, 667, 60, 160, {
  durationMs: 300,
  fingerCount: 2,
  steps: 20,
  angleDegrees: 0,
  baseFinger: 0,
});
assert(result.ok, result.error || result.raw);
```

The helper-process RPC timeout is seven seconds for `zoom`, allowing the
contract maximum duration of five seconds plus transport overhead.

## Device validation

Open a zoomable target such as Photos, Maps, or a web page. Coordinates must
use the same native coordinate space reported by task `25` subtask `1`. Start
with two fingers:

```powershell
./scripts/Test-TLinkZoomPhase1.ps1 `
  -HostIP "192.168.1.244" `
  -Runtime trollstore `
  -RunGesture `
  -Direction both `
  -CenterX 375 `
  -CenterY 667
```

Repeat with `-Runtime rootfull`, then with `-FingerCount 3`. Record:

1. Spread visibly enlarges content and pinch visibly reduces it.
2. Both fingers remain synchronized with no stuck touch after completion.
3. Three-finger behavior with Zoom, VoiceOver, and other Accessibility features
   disabled/enabled as applicable.
4. Task `97`, device/build version, target app, iOS version, and coordinate
   values used.

The no-switch form runs only capability and invalid-input checks and never
dispatches a gesture.
