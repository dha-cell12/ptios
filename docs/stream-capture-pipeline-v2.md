# Stream Capture Pipeline v2

Status: pooled vImage safe path implemented. The original performance
path produced 287/287 API-successful accelerated frames, but a later visual
qualification found horizontal tearing in both Fast and RTC while forced
legacy capture remained clean. A run-loop/coherence-only revision was also
visually rejected, as was an explicit staging/stride-copy revision. Private
IOSurface accelerator scaling is therefore rejected for production and remains
available only through explicit diagnostic mode.

Pipeline v2 removes `CGImage -> CGContextDrawImage` from the normal H.264
frame path. It retains that path only as a bounded compatibility fallback.

```text
CARenderServerRenderDisplay
  -> reusable two-entry full-resolution BGRA IOSurface pool
  -> CPU-visible locked IOSurface bytes
  -> public Accelerate/vImage BGRA scale using independent source/target stride
  -> VideoToolbox pixel buffer
  -> VTCompressionSession
```

The existing ports `7001-7006`, H.264 profile sizes, TS/ZXH2 framing and
license checks are unchanged. This phase does not add an application window,
FrontBoard scene, direct WebRTC stack or SpringBoard injection.

## Runtime fallback and recovery

When source/target layout, pixel-buffer locking, or vImage scaling fails, the
already-captured source IOSurface is drawn
into the target buffer with CoreGraphics. A failed or integrity-unsafe
accelerated transfer therefore does not reach VideoToolbox and does not
terminate an otherwise compatible device stream.
The private accelerator and alignment entry points are resolved with `dlsym`,
so an SDK stub that does not export them cannot turn the optimization into a
link-time build failure.

The private accelerator staging implementation remains behind task 93 mode
`accelerated` only for diagnosis and comparison with the reference XXTouch
runtime. Mode `auto` never creates or calls the accelerator. vImage operates on
the locked source bytes and writes synchronously into the encoder buffer using
the actual bytes-per-row of both allocations.

If both paths fail, H.264 resets the cached IOSurface/accelerator state and
retries once. The existing three-attempt encoder recovery budget is reset only
after 300 consecutive successful frames, preventing three unrelated historical
encoder faults from permanently exhausting a long session.

Task `97` exposes:

```text
streamCapturePipeline=iosurface_pool_gpu_scale_v2
streamCapturePreferredBackend=vimage_pooled_safe
streamCaptureAcceleratorPolicy=unsafe_opt_in_only
streamCaptureFallback=coregraphics_v1
streamCaptureSourcePool=2
streamCaptureStagingCache=4
streamCaptureTarget=encoder_iosurface_pixel_buffer
streamCaptureAcceleratorTarget=explicit_bgra_staging_surface
streamCaptureDiagnostics=task60_adaptive_streaming_capture_pipeline
streamCaptureBenchmark=task93_legacy_vs_accelerated_v2
streamCaptureSynchronization=pooled_iosurface_vimage_stride_v3
streamCaptureRecovery=capture_reset_once_encoder_budget_reset_300_frames
streamCaptureIntegrityDeviceValidated=0
streamCaptureDeviceValidated=1
```

Task `60` returns live diagnostics under
`adaptive_streaming.capture_pipeline`, including the active backend, capture,
accelerated, fallback and failure counters, source dimensions, transfer result,
coherence-barrier counts/results, seed changes, integrity fallback count,
staged-copy/allocation/failure counts, source/target bytes per row, run-loop
attachment, safe-scale count/result/failures, the most recent
capture/scale/total processing times, and bounded
average/p50/p95/max windows in microseconds.

Task `93` provides licensed runtime control for device qualification. Its
`set_capture_mode` action selects `legacy`, `accelerated`, or `auto` and can
reset the bounded metrics window. `auto` is the production vImage backend;
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

`pass_vimage_safe` is the intended result.
`pass_safe_coregraphics_fallback` keeps functional compatibility but means the
device could not prove the optimized GPU frame safe. For accelerated promotion,
verify a sustained 10-minute run with:

The qualification script explicitly selects `auto` and resets capture metrics,
so it is safe to run after a manual `legacy` tearing-isolation test.

- `safe_scale_count == capture_count`, zero safe-scale failures and zero
  fallback/failure frames;
- `active_backend=vimage_pooled_safe` and `last_safe_scale_result=0`;
- `accelerated_count=0` and `accelerator_run_loop_attached=false` in auto mode;
- `last_total_us` normally below 70% of the selected profile frame budget;
- no horizontal tearing or black frames in both Fast and RTC across orientation
  changes, app backgrounding and target-app transitions;
- no unbounded memory growth or serious/critical thermal state.

If the result is fallback, collect task `60` and the streamd log. A non-zero
`last_safe_scale_result` identifies vImage layout/scale or pixel-buffer locking
failure. Accelerator transfer counters are irrelevant unless task 93 was
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

The script measures legacy first, production-safe vImage second, restores `auto` even after an
error, and writes `stream-capture-comparison-*/stream-capture-comparison.json`.
The report calculates improvement for capture/scale/total average, total p50,
total p95, and observed frame-rate gain. A positive processing-time percentage
means v2 is faster; for example, `40` means v2 used 40% less time than legacy.
Only `pass_comparable` is suitable for quoting an optimization percentage:
legacy frames must use the historical backend, v2 frames must use the pooled
vImage backend, and both runs must have zero capture failures.
