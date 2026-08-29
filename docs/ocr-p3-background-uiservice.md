# Vision OCR P3: background UI-service host

> Historical P3 contract. P4 replaces the temporary-file/worker handoff with
> direct inline protocol v3; see `docs/ocr-p4-direct-inline.md`.

P3 removes the foreground `StreamControl.app` dependency from the opt-in
Vision route. `streamd` still captures and crops the target screen, writes a
bounded temporary PNG under `/var/mobile/Library/TLinkauto/tmp`, and sends the
existing protocol-v2 request to `TLinkUIService.app` on localhost port `6018`.
The UI service decodes compact BGRA and runs Vision before returning the legacy
task `27` response shape.

This is intentionally not a synthetic FrontBoard scene. The OCR endpoint does
not create a window, call `makeKeyAndVisible`, or attach a `UIWindowScene`.
Toast remains isolated on port `6017`, and the black-screen scene path remains
disabled. `privhelper` requires UI service version `23` and checks that its OCR
worker has started before accepting the process as current.

## Runtime contract

- task `27`, profiles `app_cpu` and `xxt_compat`: UI service port `6018`
- task `27`, profile `worker_cpu`: isolated streamd worker, still experimental
- task `275`: live `uiservice_ocr_ready` probe; it must report port `6018` and
  `scene_required=0`
- task `273/274`: read/clear the shared bounded Vision debug log
- task `91`: stable headless Tesseract fallback

The localhost service accepts only protocol-v2 image paths with the prefix
`/var/mobile/Library/TLinkauto/tmp/appocr-`, caps the PNG at 32 MiB, serializes
Vision work, and applies a 15-second watchdog.

## Device qualification

Keep StreamControl in the background and the target application in the
foreground, then run:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass `
  -File .\scripts\Collect-TLinkVisionOCRQualification.ps1 `
  -HostIP "192.168.1.244" `
  -TimeoutMs 30000 `
  -FastRepeatCount 20 `
  -VisionLanguages "en-US" `
  -Notes "background UI-service qualification"
```

The artifact must report qualification version
`background_fast20_accurate1_largefast1_v3`. A stopped preflight normally
means the installed UI service is stale or port `6018` is unavailable. Inspect
task `275`, task `97`, and `debug_after.decoded_log`; successful requests contain
`uiservice_pixelbuffer_probe`, `uiservice_perform_end`, and
`uiservice_response_ready`.

P3 remains a device-qualified canary until text and coordinates are reviewed.
Automation may continue to use task `91` when the UI service fails closed.
