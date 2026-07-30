# OCR P1 Device Findings And Deferral

## Status

**Deferred on 2026-07-31.**

The TrollStore Vision OCR P1 implementation is complete as an experimental
CPU-only canary, but it is not suitable for production on the device tested so
far. Task `91` Tesseract remains the stable and default OCR path.

Vision OCR should be revisited when a newer/faster test device is available.
Do not promote either P1 profile based only on static CI success.

## Scope Of P1

P1 added two explicit task `27` profiles without changing the legacy response
format:

- `app_cpu` — default profile. An isolated `streamd` worker captures and crops
  the image, writes a PNG, and sends it to the foreground StreamControl app on
  localhost port `6011`. Vision runs inside the app with CPU-only execution.
- `worker_cpu` — opt-in profile. Vision runs directly inside the isolated
  `streamd` worker with CPU-only execution.

On iOS 14-16, CPU-only execution uses `VNRequest.usesCPUOnly = YES`. On iOS 17
and newer, the runtime selects an `MLCPUComputeDevice` for every supported
Vision compute stage and fails closed if a CPU device cannot be assigned.

Task `27` responses remain byte-compatible:

```text
0;;text,,x,,y,,width,,height[;;...]\r\n
```

No automatic fallback to task `91` was added. Task `97` therefore continues to
report:

```text
visionOCRState=experimental
visionOCRProfiles=app_cpu_default,worker_cpu_opt_in
visionOCRFallback=none
visionOCRCPUOnly=1
visionOCRDefaultProfile=app_cpu
ocrDefaultEngine=tesseract
```

## Device Under Test

| Field | Value |
|---|---|
| Hardware identifier | `iPhone8,2` |
| Device generation | iPhone 6s Plus |
| SoC | Apple A9 |
| iOS | `15.8.8` |
| Runtime | TrollStore |
| Service version | `23` |
| License mode | Enforced, valid during all probes |
| OCR region | `0,0,640,320` |
| Context | Foreground |

The JSON artifacts contain additional device and license diagnostics. They
must be redacted before being shared publicly and should not be committed as
release evidence in their raw form.

## Test Results

### 1. `app_cpu`, Accurate

Command:

```powershell
./scripts/Collect-TLinkOCRBaseline.ps1 `
  -HostIP "192.168.1.244" `
  -Context foreground `
  -RunVision `
  -VisionProfile app_cpu
```

Artifact directory:

```text
ocr-baseline-20260731-011413
```

Result:

```text
-1;;app_ocr_bridge_empty_response
roundtrip_ms=8226.443
```

The bridge has an eight-second receive timeout, and the observed duration
closely matched that timeout. Task `97_postflight` succeeded, proving that
port `6000` and the main `streamd` process survived.

The same run established the working control path:

```text
task91=success
tesseract_confidence=68.00
tesseract_ocr_ms=123.084
```

### 2. `app_cpu`, Fast After The Initial Attempt

Command:

```powershell
./scripts/Collect-TLinkOCRBaseline.ps1 `
  -HostIP "192.168.1.244" `
  -Context foreground `
  -RunVision `
  -VisionProfile app_cpu `
  -RecognitionLevel 1
```

Artifact directory:

```text
ocr-baseline-20260731-011855
```

Result:

```text
-1;;app_ocr_bridge_empty_response
roundtrip_ms=8247.738
```

This result alone was not considered an independent Fast-profile test. The app
OCR server handles its client synchronously, and the previous Accurate request
may have left its Vision call blocked. A client-side timeout does not cancel
the app's in-process `performRequests` call.

Task `97_postflight` still succeeded.

### 3. `worker_cpu`, Fast

Command:

```powershell
./scripts/Collect-TLinkOCRBaseline.ps1 `
  -HostIP "192.168.1.244" `
  -Context foreground `
  -RunVision `
  -VisionProfile worker_cpu `
  -RecognitionLevel 1
```

Artifact directory:

```text
ocr-baseline-20260731-011912
```

Result:

```text
-1;;ocr_worker_crashed signal=11 phase=vision_perform_requests port_6000_preserved
roundtrip_ms=310.994
```

This is a definitive direct-worker failure. CPU-only execution did not prevent
Vision from raising `SIGSEGV` during `performRequests`. Worker isolation
worked correctly and task `97_postflight` succeeded.

### 4. `app_cpu`, Fast After Fresh StreamControl Launch

StreamControl was force-closed, opened again, kept in the foreground, and the
Fast profile was run as the first Vision request. Tesseract was skipped to
remove unrelated work.

Command:

```powershell
./scripts/Collect-TLinkOCRBaseline.ps1 `
  -HostIP "192.168.1.244" `
  -Context foreground `
  -RunVision `
  -VisionProfile app_cpu `
  -RecognitionLevel 1 `
  -SkipTesseract `
  -Notes "fresh StreamControl launch, first Vision request"
```

Artifact directory:

```text
ocr-baseline-20260731-012117
```

Result:

```text
no task 27 protocol response
collector_timeout_ms=20000
roundtrip_ms=20013.789
task97_preflight=success
task97_postflight=success
task97_postflight_roundtrip_ms=2719.21
```

This fresh-launch result removes the earlier contaminated-server explanation.
The `app_cpu` Fast pipeline remained blocked for at least twenty seconds.

The collector timeout and the OCR worker watchdog are both twenty seconds. The
client therefore timed out just before it could reliably receive the worker's
structured `ocr_worker_timeout timeout_ms=20000` response. The delayed
postflight response is consistent with the original task handler finishing its
timeout cleanup while port `6000` remained alive.

## Conclusions

The P1 device promotion gate failed on the A9/iOS 15.8.8 device:

1. `worker_cpu` crashes deterministically with `SIGSEGV` during
   `vision_perform_requests`.
2. `app_cpu` can block beyond the eight-second bridge timeout and the
   twenty-second worker watchdog, including Fast recognition after a fresh app
   launch.
3. CPU-only configuration does not by itself resolve the original TrollStore
   Vision instability on this hardware/runtime combination.
4. Worker isolation successfully protects the main task server. Every
   postflight task `97` probe succeeded.
5. Tesseract remains functional and is the only production-approved OCR engine
   for this runtime.

This evidence does not prove that CPU-only Vision is broken on every TrollStore
device. It proves that P1 cannot be promoted from the current A9 test result.

## Current Decision

- Keep `visionOCRState=experimental`.
- Keep `ocrDefaultEngine=tesseract`.
- Do not enable `worker_cpu` automatically.
- Do not add transparent task `27` to task `91` fallback because it would hide
  crashes/timeouts and alter expected task semantics.
- Do not increase timeouts as a production fix. Longer timeouts would only
  conceal a hang and hold a task-server request open longer.
- Preserve the P1 implementation and fixtures for future device testing.
- Pause additional Vision work until newer hardware is available.

## Improvements To Consider Before Retesting

These are diagnostic/hardening tasks, not evidence that Vision will become
functional:

1. Give the collector timeout a margin above the worker watchdog, for example
   30 seconds versus the current 20-second worker timeout, so structured worker
   timeout responses are not lost in a race.
2. Persist worker phase breadcrumbs to a parent-readable file during normal
   progress, not only from fatal signal handlers. This would identify whether
   an app-profile timeout occurred during capture, PNG encoding, bridge I/O, or
   Vision execution.
3. Add app-side request IDs and timestamps for decode start, CPU configuration,
   `performRequests` start/end, result collection, and socket write.
4. Prevent one hung app-side Vision request from permanently blocking the
   accept loop. Any concurrency design must remain bounded so repeated requests
   cannot accumulate hung Vision threads.
5. Add a runtime/device denylist only if Vision is ever exposed outside an
   explicit experimental canary.

## Future Device Matrix

When stronger hardware is available, start with one fresh-launch Fast request
per device:

| Dimension | Minimum coverage |
|---|---|
| SoC generation | A12 or newer preferred; include at least two generations |
| iOS API path | iOS 15/16 `usesCPUOnly`; iOS 17+ compute-stage device API |
| Profiles | `app_cpu`, then `worker_cpu` only if the app profile is bounded |
| Recognition level | Fast first, Accurate only after Fast succeeds |
| Context | Foreground first; background/locked only after foreground passes |
| Region | Small known fixture, then `640x320`, then representative production regions |
| Repetition | At least 20 consecutive calls plus a longer soak |

Restart StreamControl before the first `app_cpu` request on each test case.
Run only one Vision request until it is known that the app-side server returned
cleanly.

Recommended first command:

```powershell
./scripts/Collect-TLinkOCRBaseline.ps1 `
  -HostIP "<device-ip>" `
  -TimeoutMs 30000 `
  -Context foreground `
  -RunVision `
  -VisionProfile app_cpu `
  -RecognitionLevel 1 `
  -SkipTesseract `
  -DeviceModel "<hardware-identifier>" `
  -SoC "<soc>" `
  -IOSVersion "<ios-version>" `
  -BuildIdentifier "<build-id>" `
  -Notes "fresh launch; first Vision request"
```

Only after `app_cpu` returns a bounded success or diagnostic error should
`worker_cpu` be tested:

```powershell
./scripts/Collect-TLinkOCRBaseline.ps1 `
  -HostIP "<device-ip>" `
  -TimeoutMs 30000 `
  -Context foreground `
  -RunVision `
  -VisionProfile worker_cpu `
  -RecognitionLevel 1 `
  -SkipTesseract `
  -DeviceModel "<hardware-identifier>" `
  -SoC "<soc>" `
  -IOSVersion "<ios-version>" `
  -BuildIdentifier "<build-id>"
```

## Promotion Criteria For A Future Revisit

Vision OCR remains experimental until all of the following are demonstrated:

- no worker/app crash and no unbounded `performRequests` call;
- task `27` returns before both bridge and worker watchdog deadlines;
- task `97_postflight` remains responsive after every request;
- output retains the frozen five-field task `27` observation contract;
- coordinates and text are correct for known fixtures;
- repeated requests do not grow memory or leave the app OCR server blocked;
- unsupported contexts fail with bounded, structured errors;
- the result is reproduced on more than one supported device generation.

Until those criteria pass, all production automation should use task `91`.
