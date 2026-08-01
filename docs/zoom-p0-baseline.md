# Zoom P0 baseline — contract only

## Outcome

P0 freezes one additive, shared contract for a future two- or three-finger
pinch/spread gesture on rootfull and TrollStore. It does not synthesize a zoom
gesture yet. Existing task `10`, legacy task `64`, and task `65` behavior stays
unchanged.

Both runtimes already have the necessary low-level foundation: one task `10`
frame can append multiple finger children to the same digitizer parent event.
The current wire format has one decimal count digit, so it can represent at
most nine touches per frame even though both native backends accept finger
indexes `0..19`. P0 reserves only two and three fingers.

## Frozen wire contract

The additive request is carried by the existing automation-gated task `64`:

```text
64zoom;;center_x;;center_y;;start_radius;;end_radius;;duration_ms;;finger_count;;steps[;;angle_degrees;;base_finger]\r\n
```

The body, excluding the numeric task prefix, is:

```text
zoom;;center_x;;center_y;;start_radius;;end_radius;;duration_ms;;finger_count;;steps[;;angle_degrees;;base_finger]
```

- `finger_count`: exactly `2` or `3`.
- `end_radius > start_radius`: spread, normally interpreted as zoom in.
- `end_radius < start_radius`: pinch, normally interpreted as zoom out.
- `duration_ms`: `50..5000`.
- `steps`: `2..120`, including the first and last geometry samples.
- Both radii must be positive. Equal radii are invalid.
- `angle_degrees`: optional, defaults to `0`, allowed range `-360..360`.
- `base_finger`: optional, defaults to `0`; Phase 1 must validate the complete
  contiguous index range against `0..19`.

Coordinates and radii use screen points in the same coordinate space as the
legacy native touch tasks. Phase 1 must reject any generated point outside the
current screen bounds; it must not silently clamp geometry because that would
distort the gesture.

## P0 runtime behavior

Task `97` exposes these exact additive markers on both runtimes:

```text
multiTouchRaw=legacy_task10_parent_frames
zoomState=contract_only
zoomTask=64
zoomWire=task64_additive_zoom_v1
zoomFingerCounts=2,3
zoomBackend=legacy_multitouch_parent_frames
zoomPhase=0
```

The structured task `60` capability payload also describes Zoom P0. TrollStore
reports `zoom=false`; rootfull reports the same state in its `zoom` object.

During P0, a request whose first task `64` field is exactly `zoom`
(case-insensitive) fails with:

```text
-1;;zoom_not_implemented_phase0\r\n
```

This stable rejection happens before the legacy single-finger parser. It is
important: a future-format request cannot be mistaken for a legacy path and no
HID event is dispatched. Other task `64` inputs retain the existing
`finger;;duration_ms;;x,y|x,y|...` parser and responses.

## Compatibility and safety boundary

- No new task number or license feature is introduced. Task `64` remains under
  the existing `automation` gate in both runtimes.
- Task `10` bytes and its response contract are untouched.
- Task `65` remains a sequential batch of existing native commands; P0 does
  not claim that it provides simultaneous multi-touch.
- P0 does not add Python, JavaScript, or UI methods that imply zoom is usable.
- Three-finger gestures may conflict with iOS Accessibility or system gestures.
  Phase 1 device validation must record enabled accessibility settings and test
  inside the target app before promotion.

The machine-readable source of truth is
`test/fixtures/zoom-p0-contract-v1.json`. CI runs
`scripts/check-zoom-p0-baseline.mjs` to keep the two implementations,
capabilities, fixture, and this document coherent.

## Device sanity check

Install the corresponding build, unlock the device, and run:

```powershell
$iphoneIP = "192.168.1.244"
./scripts/Test-TLinkZoomPhase0.ps1 `
  -HostIP $iphoneIP `
  -Runtime trollstore
```

For rootfull, change `-Runtime` to `rootfull`. Expected output is
`state=contract_only`, `legacy_task64_unchanged=True`, and
`gesture_dispatched=False`. The probe is intentionally non-visual.

## Phase 1 promotion gate

Phase 1 may switch `zoomState` from `contract_only` only after all of these are
demonstrated on both runtimes:

1. Down, every move step, and up contain all selected fingers in one parent HID
   event and use stable finger indexes.
2. Validation rejects invalid geometry before the first down event.
3. Cancellation or dispatch failure emits a best-effort all-fingers-up cleanup.
4. Two-finger pinch/spread passes on-device in at least two target apps.
5. Three-finger behavior is documented separately, including iOS system-gesture
   or Accessibility interception.
6. Task `10` and legacy task `64` regression fixtures still pass byte-for-byte.
