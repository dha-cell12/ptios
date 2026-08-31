# Vision OCR P4: direct inline transport

P4 optimizes the device-qualified P3 background route without changing the
legacy task `27` request or response shape.

For `app_cpu` and `xxt_compat`, the long-lived streamd process now captures and
crops the screen and calls `TLinkUIService.app` directly. Vision itself remains
isolated in the UI service. The former per-request streamd child, worker output
file, and cross-uid PNG temporary file are no longer used on this route.

Port `6018` protocol v4 sends one bounded metadata line followed by tightly
packed RGBA8888 pixels. This removes PNG encode/decode from the normal OCR hot
path. Both peers reject zero-length or greater-than-32-MiB payloads, the
receiver reads exactly the declared length, and the existing 15-second Vision
watchdog remains active. Protocol v3 inline PNG and protocol v2 file requests
remain accepted for rollback compatibility; streamd only uses v3 after an
explicit stale-service protocol rejection.

The expensive CoreVideo compatibility matrix is now sampled once when
TLinkUIService starts, rather than allocating five probe buffers for every OCR
request.

`worker_cpu` intentionally retains process isolation and the old worker path.
Language enumeration also remains isolated. Toast stays on port `6017`; P4
does not create or attach a scene or make a window key.

## Qualification

Keep StreamControl backgrounded and the target app foreground, then run
`Collect-TLinkVisionOCRQualification.ps1` as documented for P3. The artifact
must report:

- `background_direct_raw_fast20_accurate1_largefast1_v5`
- task `275`: `protocol=4`, `transport=inline_rgba8888`, `app_state=2`
- task `97`: `visionOCRTransport=inline_rgba8888_bounded_32mib_v2`
- task `97`: `visionOCRDispatch=direct_streamd_to_uiservice_no_worker_v1`
- one startup pixel-buffer probe plus all requested perform completions and
  responses with no failure

Compare the v4 round-trip p50/p95 with the P3 artifact. The Vision-internal
warm Fast time should remain in the same range; improvement is expected in the
outer round trip because worker spawn, disk handoff, and PNG transcoding were
removed.
