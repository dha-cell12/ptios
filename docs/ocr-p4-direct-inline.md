# Vision OCR P4: direct inline transport

P4 optimizes the device-qualified P3 background route without changing the
legacy task `27` request or response shape.

For `app_cpu` and `xxt_compat`, the long-lived streamd process now captures and
crops the screen and calls `TLinkUIService.app` directly. Vision itself remains
isolated in the UI service. The former per-request streamd child, worker output
file, and cross-uid PNG temporary file are no longer used on this route.

Port `6018` protocol v3 sends one bounded metadata line followed by the exact
PNG byte count. Both peers reject zero-length or greater-than-32-MiB payloads,
the receiver reads exactly the declared length, and the existing 15-second
Vision watchdog remains active. UI service protocol v2 file requests remain
accepted temporarily for rollback compatibility.

`worker_cpu` intentionally retains process isolation and the old worker path.
Language enumeration also remains isolated. Toast stays on port `6017`; P4
does not create or attach a scene or make a window key.

## Qualification

Keep StreamControl backgrounded and the target app foreground, then run
`Collect-TLinkVisionOCRQualification.ps1` as documented for P3. The artifact
must report:

- `background_direct_inline_fast20_accurate1_largefast1_v4`
- task `275`: `protocol=3`, `transport=inline_png`, `app_state=2`
- task `97`: `visionOCRTransport=inline_png_bounded_32mib_v1`
- task `97`: `visionOCRDispatch=direct_streamd_to_uiservice_no_worker_v1`
- 22 pixel-buffer probes, perform completions, and responses with no failure

Compare the v4 round-trip p50/p95 with the P3 artifact. The Vision-internal
warm Fast time should remain in the same range; improvement is expected in the
outer round trip because worker spawn and disk handoff were removed.
