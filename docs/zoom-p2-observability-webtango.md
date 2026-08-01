# Zoom P2 — runtime observability and WebTango integration

## Outcome

P2 keeps the P1 multi-touch implementation and `experimental` state, then adds
runtime evidence and first-class client tooling. The task `64` wire contract is
unchanged. Device validation is still required before production promotion.

Task `97` adds:

```text
zoomState=experimental
zoomTask=64
zoomWire=task64_additive_zoom_v1
zoomPhase=2
zoomDiagnostics=zoom_runtime_diagnostics_v1
zoomClients=task64_python_js_webtango_v1
zoomDeviceValidated=0
```

## Task 60 diagnostics

Rootfull exposes the object at `zoom.diagnostics`; TrollStore exposes the same
schema at `capabilities.zoomDiagnostics`:

```text
schema
attempt_count
success_count
validation_rejected_count
dispatch_exception_count
cleanup_count
frame_count
in_flight
last_at_ms
last_result
last_direction
last_finger_count
last_steps
last_duration_ms
```

`last_at_ms` is Unix epoch milliseconds on both runtimes. A validation failure
increments `attempt_count` and `validation_rejected_count` but must not increase
`frame_count`. A completed gesture increments `success_count` and adds exactly
`steps + 1` frames: one down, `steps - 1` moves, and one up.

Counters are process-lifetime evidence and reset when SpringBoard/rootfull or
streamd/TrollStore restarts. They do not claim that the target app visually
accepted the gesture; visual confirmation remains part of the device matrix.

## WebTango

`TLinkautoDeviceSdk.zoom()` now sends the native task rather than approximating
zoom with sequential one-finger swipes. Its response timeout is
`max(3000, durationMs + 2000)` so the five-second native limit has transport
headroom. Automation IDE type hints and completion include `device.zoom`, and
the Interaction panel can insert Zoom in/Zoom out snippets around the selected
point or screen center.

```javascript
await device.zoom(375, 667, 60, 160, {
  durationMs: 300,
  fingerCount: 2,
  steps: 20,
});
```

## Device check

The default check is non-visual: it verifies task `97`, then proves through
task `60` counters that an invalid four-finger request generated zero frames.

```powershell
./scripts/Test-TLinkZoomPhase2.ps1 `
  -HostIP "192.168.1.244" `
  -Runtime trollstore
```

To collect gesture/frame evidence, open Photos, Maps, or another zoomable app:

```powershell
./scripts/Test-TLinkZoomPhase2.ps1 `
  -HostIP "192.168.1.244" `
  -Runtime trollstore `
  -RunGesture `
  -Direction both `
  -CenterX 375 `
  -CenterY 667
```

Repeat for rootfull and for `-FingerCount 3`. A passing script proves dispatch
accounting; the tester must still report the visual pinch/spread result before
`zoomDeviceValidated` can change to `1`.
