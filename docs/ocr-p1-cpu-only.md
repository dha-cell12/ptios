# OCR P1 CPU-Only Canary

P1 enables an explicit CPU-only Vision OCR canary in the TrollStore runtime.
Task `91` Tesseract remains the default and stable OCR engine. P1 does not add
automatic fallback and does not change task `27` response bytes.

Device testing on an A9/iOS 15.8.8 device failed the promotion gate:
`worker_cpu` crashed during `vision_perform_requests`, while a fresh-launch
`app_cpu` Fast request remained blocked through the twenty-second worker
watchdog. Further Vision work is deferred until newer hardware is available.
See `docs/ocr-p1-device-findings.md` for the complete evidence and retest plan.

P2 now adds a separate opt-in `xxt_compat` profile without changing these P1
profiles. See `docs/ocr-p2-xxt-compat.md`; task `91` remains the default.

## Profiles

Task `27` subtask `1` accepts one optional ninth body field:

```text
1;;x,,y,,w,,h;;custom_words;;minimum_height;;level;;languages;;correct;;debug_path;;profile
```

- `app_cpu` is the default when the field is missing or empty. The isolated
  worker captures and crops the image, then sends it to the foreground app on
  port `6011`. The app configures every Vision request for CPU execution.
- `worker_cpu` is opt-in. Vision runs directly inside the isolated worker with
  CPU execution forced. A worker crash remains isolated from port `6000`.
- Any other profile is rejected before capture.

On iOS 14-16 the runtime sets `usesCPUOnly=YES`. On iOS 17 and newer it queries
the supported devices for every Vision compute stage and assigns an
`MLCPUComputeDevice`. If the query fails or any stage has no CPU device, the
request fails closed with `ocr_cpu_profile_failed` or an app-bridge error; it
does not silently use GPU/ANE.

Legacy requests with eight fields select `app_cpu`, and successful responses
remain:

```text
0;;text,,x,,y,,width,,height[;;...]\r\n
```

No engine/profile metadata is appended because existing clients parse every
payload item as a five-field observation.

## Capability Report

Task `97` reports:

```text
visionOCRState=experimental
visionOCRProfiles=app_cpu_default,worker_cpu_opt_in
visionOCRRoute=profile_selected_worker_or_app_6011
visionOCRFallback=none
visionOCRCPUOnly=1
visionOCRDefaultProfile=app_cpu
ocrDefaultEngine=tesseract
ocrEngineSelector=none
ocrProtocolVersion=legacy_v1
ocrLegacyTasks=27,91
```

`experimental` is intentional until both profiles pass the device matrix.
`ocrDefaultEngine=tesseract` remains authoritative for normal automation.

## Device Canary

Keep StreamControl in the foreground for the app profile:

```powershell
./scripts/Collect-TLinkOCRBaseline.ps1 `
  -HostIP "192.168.1.244" `
  -Context foreground `
  -RunVision `
  -VisionProfile app_cpu `
  -RegionX 0 -RegionY 0 -RegionWidth 640 -RegionHeight 320
```

Test the isolated direct worker separately:

```powershell
./scripts/Collect-TLinkOCRBaseline.ps1 `
  -HostIP "192.168.1.244" `
  -Context foreground `
  -RunVision `
  -VisionProfile worker_cpu `
  -RegionX 0 -RegionY 0 -RegionWidth 640 -RegionHeight 320
```

For each profile, retain the JSON artifact, task `97` pre/postflight results,
device model/SoC/iOS/build identifier, and the device log. Repeat foreground,
background, locked, after-respring, and after-reboot contexts only after the
foreground canary passes. The `app_cpu` route is expected to fail cleanly when
the foreground app bridge is unavailable.

## Promotion Gate

P1 is ready for promotion only when:

- neither profile terminates the worker or disrupts port `6000`;
- the former `420f` input reproducer succeeds on the target device;
- output coordinates and text match the P0 fixture contract;
- repeated runs show acceptable latency and memory growth;
- unsupported/background states return bounded, diagnostic errors.

Until then, production callers should continue using task `91`.
