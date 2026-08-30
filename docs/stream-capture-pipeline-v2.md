# Stream Capture Pipeline v2

Status: fresh-surface CGImage snapshot-safe path implemented. The original performance
path produced 287/287 API-successful accelerated frames, but a later visual
qualification found horizontal tearing in both Fast and RTC while forced
legacy capture remained clean. A run-loop/coherence-only revision was also
visually rejected, as was an explicit staging/stride-copy revision. Direct raw
vImage reads then removed the scanline tearing but exposed incomplete layer
tiles. Private IOSurface accelerator and raw-surface vImage scaling are
therefore rejected for production; the accelerator remains
available only through explicit diagnostic mode.

Production `auto` now uses the exact `CGImage -> CGContextDrawImage` path that
device testing proved visually clean. Correctness takes priority over the
rejected acceleration gain.

```text
CARenderServerRenderDisplay
  -> fresh full-resolution BGRA IOSurface
  -> UICreateCGImageFromIOSurface snapshot materialization
  -> CGContextDrawImage into the encoder buffer
  -> VideoToolbox pixel buffer
  -> VTCompressionSession
```

The existing ports `7001-7006`, H.264 profile sizes, TS/ZXH2 framing and
license checks are unchanged. This phase does not add an application window,
FrontBoard scene, direct WebRTC stack or SpringBoard injection.

## Runtime fallback and recovery

When snapshot creation or drawing fails, the frame fails closed. A failed
private accelerated transfer is replaced with a fresh CoreGraphics snapshot
before VideoToolbox.
The private accelerator and alignment entry points are resolved with `dlsym`,
so an SDK stub that does not export them cannot turn the optimization into a
link-time build failure.

The private accelerator staging implementation remains behind task 93 mode
`accelerated` only for diagnosis and comparison with the reference XXTouch
runtime. Mode `auto` never creates or calls the accelerator. It materializes a
CGImage snapshot from a fresh source surface and draws it
into the encoder buffer, which preserves the compositor synchronization behavior
that remained visually clean in legacy device testing.

If both paths fail, H.264 resets the cached IOSurface/accelerator state and
retries once. The existing three-attempt encoder recovery budget is reset only
after 300 consecutive successful frames, preventing three unrelated historical
encoder faults from permanently exhausting a long session.

Task `97` exposes:

```text
streamCapturePipeline=iosurface_pool_gpu_scale_v2
streamCapturePreferredBackend=coregraphics_fresh_surface_safe
streamCaptureAcceleratorPolicy=unsafe_opt_in_only
streamCaptureFallback=coregraphics_v1
streamCaptureSourcePool=2
streamCaptureStagingCache=4
streamCaptureTarget=encoder_iosurface_pixel_buffer
streamCaptureAcceleratorTarget=explicit_bgra_staging_surface
streamCaptureDiagnostics=task60_adaptive_streaming_capture_pipeline
streamCaptureBenchmark=task93_legacy_vs_accelerated_v2
streamCaptureSynchronization=fresh_iosurface_cgimage_draw_v5
streamCaptureRecovery=capture_reset_once_encoder_budget_reset_300_frames
streamCaptureIntegrityDeviceValidated=0
streamCaptureDeviceValidated=1
```

Task `60` returns live diagnostics under
`adaptive_streaming.capture_pipeline`, including the active backend, capture,
accelerated, fallback and failure counters, source dimensions, transfer result,
coherence-barrier counts/results, seed changes, integrity fallback count,
staged-copy/allocation/failure counts, source/target bytes per row, run-loop
attachment, safe-copy count/failures, the most recent
capture/scale/total processing times, and bounded
average/p50/p95/max windows in microseconds.

Task `93` provides licensed runtime control for device qualification. Its
`set_capture_mode` action selects `legacy`, `accelerated`, or `auto` and can
reset the bounded metrics window. `auto` is the production fresh-surface snapshot backend;
`accelerated` is the visually unsafe private diagnostic backend. `legacy`
deliberately reproduces the old per-frame IOSurface allocation plus CoreGraphics
scale path.

## Device qualification

After installing the new build, use **Settings > Restart streamd** once. Stop
any existing viewer that already owns the selected stream port, then run:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass `
  -File .\scripts\Test-TLinkStreamCapturePipelineV2.ps1 `
  -HostIP "192.168.1.244" `
  -StreamPort 7003 `
  -DrainSeconds 10
```

`pass_fresh_surface_safe` is the intended result.
`pass_safe_coregraphics_fallback` keeps functional compatibility but means the
private diagnostic path needed the fresh historical retry. For safe-path promotion,
verify a sustained 10-minute run with:

The qualification script explicitly selects `auto` and resets capture metrics,
so it is safe to run after a manual `legacy` tearing-isolation test.

- `safe_copy_count == capture_count`, zero safe-copy failures and zero
  fallback/failure frames;
- `active_backend=coregraphics_fresh_surface_safe`;
- `accelerated_count=0` and `accelerator_run_loop_attached=false` in auto mode;
- `last_total_us` normally below 70% of the selected profile frame budget;
- no horizontal tearing or black frames in both Fast and RTC across orientation
  changes, app backgrounding and target-app transitions;
- no unbounded memory growth or serious/critical thermal state.

If the result is fallback, collect task `60` and the streamd log. A non-zero
`safe_copy_failure_count` identifies fresh snapshot creation/draw failure.
Accelerator transfer counters are irrelevant unless task 93 was
explicitly switched to `accelerated`.

## Legacy versus v2 measurement

Run the controlled sequential A/B test after installing the new build:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass `
  -File .\scripts\Compare-TLinkStreamCapturePipeline.ps1 `
  -HostIP "192.168.1.244" `
  -StreamPort 7003 `
  -SampleSeconds 10
```

The script measures legacy first, production-safe fresh snapshot second, restores `auto` even after an
error, and writes `stream-capture-comparison-*/stream-capture-comparison.json`.
The report calculates improvement for capture/scale/total average, total p50,
total p95, and observed frame-rate gain. A positive processing-time percentage
means v2 is faster; for example, `40` means v2 used 40% less time than legacy.
Only `pass_comparable` is suitable for quoting an optimization percentage:
legacy frames must use the historical backend, auto frames must use the fresh
snapshot backend, and both runs must have zero capture failures. Because both
now use the same proven rendering primitive, this comparison is a regression
check rather than evidence of an acceleration gain.
