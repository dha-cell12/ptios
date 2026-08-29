# Stream Capture Pipeline v2

Status: implemented for the TrollStore `streamd` H.264 runtime; device
promotion is pending.

Pipeline v2 removes `CGImage -> CGContextDrawImage` from the normal H.264
frame path. It retains that path only as a bounded compatibility fallback.

```text
CARenderServerRenderDisplay
  -> reusable two-entry full-resolution BGRA IOSurface pool
  -> IOSurfaceAcceleratorTransferSurface
  -> IOSurface-backed CVPixelBuffer from the VideoToolbox pool
  -> VTCompressionSession
```

The existing ports `7001-7006`, H.264 profile sizes, TS/ZXH2 framing and
license checks are unchanged. This phase does not add an application window,
FrontBoard scene, direct WebRTC stack or SpringBoard injection.

## Runtime fallback and recovery

When `CVPixelBufferGetIOSurface`, `IOSurfaceAcceleratorCreate`, or the surface
transfer is unavailable, the already-captured source IOSurface is drawn into
the target buffer with CoreGraphics. A failed accelerated transfer therefore
does not terminate an otherwise compatible device stream.
The two private accelerator entry points are resolved with `dlsym`, so an SDK
stub that does not export them cannot turn the optimization into a link-time
build failure.

If both paths fail, H.264 resets the cached IOSurface/accelerator state and
retries once. The existing three-attempt encoder recovery budget is reset only
after 300 consecutive successful frames, preventing three unrelated historical
encoder faults from permanently exhausting a long session.

Task `97` exposes:

```text
streamCapturePipeline=iosurface_pool_gpu_scale_v2
streamCapturePreferredBackend=iosurface_accelerator
streamCaptureFallback=coregraphics_v1
streamCaptureSourcePool=2
streamCaptureTarget=encoder_iosurface_pixel_buffer
streamCaptureDiagnostics=task60_adaptive_streaming_capture_pipeline
streamCaptureRecovery=capture_reset_once_encoder_budget_reset_300_frames
streamCaptureDeviceValidated=0
```

Task `60` returns live diagnostics under
`adaptive_streaming.capture_pipeline`, including the active backend, capture,
accelerated, fallback and failure counters, source dimensions, transfer result,
and the most recent capture/scale/total processing times in microseconds.

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

`pass_accelerated` is the intended result. `pass_coregraphics_fallback` keeps
functional compatibility but means the device did not use the optimized GPU
path. For accelerated promotion, verify a sustained 10-minute run with:

- `accelerated_count` increasing and `fallback_count/failure_count` remaining
  zero;
- `last_total_us` normally below 70% of the selected profile frame budget;
- no black frames across orientation changes, app backgrounding and target-app
  transitions;
- no unbounded memory growth or serious/critical thermal state.

If the result is fallback, collect task `60` and the streamd log. A non-zero
`last_transfer_result` identifies accelerator creation/transfer failure; a
zero result with fallback usually means the encoder pixel buffer was not
IOSurface-backed.
