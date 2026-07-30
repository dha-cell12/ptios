# OCR P0 Baseline And Legacy Protocol Contract

This document freezes the state before Vision OCR recovery work begins. P0
does not enable CPU-only Vision, add an engine selector, change entitlements,
or change OCR result formats.

This is a historical baseline. The current experimental implementation is
documented in `docs/ocr-p1-cpu-only.md`; P1 does not rewrite this evidence.

## Current Runtime Baseline

### Rootfull

- Task `27` is routed to the SpringBoard-injected runtime.
- Task `27` subtask `1` returns zero or more
  `text,,x,,y,,width,,height` observations separated by `;;`.
- Task `91` is the Tesseract region/frame path.
- The rootfull JavaScript `device.ocr()` and `device.ocrFrame()` facade currently
  use task `91`.

### TrollStore

- Task `27` starts an isolated worker.
- The worker captures and crops the screen, encodes PNG, and then immediately
  calls the foreground app bridge on port `6011`.
- Direct Vision code in `streamd` exists after that return but is disabled by
  control flow.
- Task `27` has no automatic fallback to task `91`.
- Task `91` is the stable Tesseract path and is used by the JavaScript OCR
  facade.
- Known evidence recorded before P0:
  - direct/headless Vision previously terminated the worker with signal `11`
    during `vision_perform_requests`;
  - app-side Vision returned
    `Could not create buffer with format '420f' (-6662)` on the test device.

The error history is evidence, not a proven ANE-entitlement root cause.

## Frozen Wire Contract

Task `27` and task `91` remain byte-compatible during P0.

- Do not append `;;engine=...` or other metadata to task `27`: the legacy
  Python client treats every `;;` payload item as a five-field observation.
- Do not reorder the first seven task `91` response fields.
- Engine metadata belongs in a future opt-in OCR v2 response, not these legacy
  tasks.

Machine-readable request/response fixtures live in
`test/fixtures/ocr-wire-contract-v1.json`. CI runs
`scripts/check-ocr-p0-baseline.mjs` to protect the contract.

## Task 97 P0 Fields

Task `97` retains all legacy capability tokens. TrollStore adds:

```text
visionOCRState=deferred
visionOCRProfiles=app_bridge_experimental,worker_direct_disabled
visionOCRRoute=isolated_worker_to_app_6011
visionOCRFallback=none
ocrDefaultEngine=tesseract
ocrEngineSelector=none
ocrProtocolVersion=legacy_v1
ocrLegacyTasks=27,91
```

`visionOCRState=deferred` is the authoritative status during P0. The older
`visionOCR` capability token is retained only for compatibility.

Rootfull reports the same field names with its current route:

```text
visionOCRState=ready
visionOCRProfiles=springboard_default
visionOCRRoute=daemon_to_springboard
visionOCRFallback=none
ocrDefaultEngine=tesseract
ocrEngineSelector=none
ocrProtocolVersion=legacy_v1
ocrLegacyTasks=27,91
```

`visionOCRState=ready` describes legacy task `27`, while
`ocrDefaultEngine=tesseract` describes the current JavaScript facade. P0 does
not unify those two entry points.

## Collecting A Device Baseline

Run the safe baseline first. It collects task `60/97`, Tesseract languages, and
one task `91` OCR attempt; Vision is skipped:

```powershell
./scripts/Collect-TLinkOCRBaseline.ps1 `
  -HostIP "192.168.1.244" `
  -DeviceModel "iPhone10,6" `
  -SoC "A11" `
  -IOSVersion "15.8.4" `
  -BuildIdentifier "streamd-service-23" `
  -Context foreground `
  -RegionX 0 -RegionY 0 -RegionWidth 640 -RegionHeight 320
```

To reproduce the known Vision failure on a disposable/test device, add
`-RunVision`. Keep StreamControl foreground when testing the current app bridge:

```powershell
./scripts/Collect-TLinkOCRBaseline.ps1 `
  -HostIP "192.168.1.244" `
  -DeviceModel "iPhone10,6" `
  -SoC "A11" `
  -IOSVersion "15.8.4" `
  -Context foreground `
  -RunVision `
  -DeviceLogPath "./device-vision.log"
```

Repeat with a separate output directory for each context:

- `foreground`
- `background`
- `locked`
- `after_respring`
- `after_reboot`

Do not claim background Vision support merely because task `auto` or Tesseract
works. The current Vision route requires the app bridge on port `6011`.

## Required Evidence Before P1

Each device baseline should contain:

- device model, SoC, iOS version, and tested build identifier;
- foreground/background/lock/restart context;
- exact OCR region and language;
- raw task `60`, `97`, `27`, and `91` responses as applicable;
- round-trip times;
- device/streamd log covering the request;
- the postflight task `97` result proving whether port `6000` remained
  reachable after the request.

P1 should start with app-side CPU-only Vision on the exact device and input
that reproduced `420f`.
