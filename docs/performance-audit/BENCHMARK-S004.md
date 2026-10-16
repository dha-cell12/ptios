# S004 Benchmark Plan — Capture / Frame Store / Image Lifetime

Goal: quantify capture bandwidth, frame-store copy/retention and image-store contention before implementation changes.

## Probe A — Capture pipeline cost by physical resolution

Target:
`pccontrol/Screen.xm::zx_captureScreenCGImageRef`

Test on representative iPhone + iPad devices/orientations.

Collect per capture:
- physical pixel width/height,
- IOSurface creation time,
- render-server time,
- iPad rotation time where applicable,
- total capture time,
- allocations/bytes,
- peak RSS,
- CPU and Energy Log.

Rates:
- 1 FPS
- 12 FPS
- 15 FPS
- 20 FPS
- 30 FPS

Do not log every frame in production. Use aggregate counters/sampled signposts in a profiling build.

### A/B variants

A. Current full native capture.
B. A + cached device classification (remove per-frame uname/regex).
C. B + reusable IOSurface/pixel resources.
D. target-resolution capture prototype for H264 where supported.
E. GPU/IOSurface scaling prototype if direct target-size render is not correct.

Verify orientation and pixel correctness, especially iPad8+.

---

## Probe B — Frame-store insertion copy volume

Target:
`Image.xm::handleFrameCaptureTaskFromRawData`
and
`zx_storeFrameLocked`.

Use both BGRA+gray default frames.

Capture:
- allocator bytes,
- malloc/free count,
- memcpy/memmove sample cost,
- peak RSS,
- capture total p50/p95/p99,
- queue hold time.

Compare:

1. current const-reference + local copy + map copy,
2. move directly into map,
3. optional pooled/reused BGRA storage if later justified.

Resolutions:
- 1170×2532-class
- 1290×2796-class
- 2048×2732-class iPad

Store sequences:
- one frame,
- rolling 3 frames,
- 10k captures with immediate auto-release/replacement.

Acceptance target: persistent frame owns one BGRA buffer; no extra full-size vector deep copies during insertion.

---

## Probe C — Frame TTL idle retention

Procedure:

1. Capture three default frames with 1-second TTL.
2. Record RSS/store bytes immediately.
3. Perform **no further frame operation**.
4. Measure at +2 s, +5 s, +30 s, +5 min.
5. Then issue one harmless frame operation and observe cleanup.

Current expected source behavior: payload remains allocated until a later cleanup-triggering operation.

Repeat after coalesced expiry cleanup.

Acceptance target: expired frame payload is actually released within a bounded tolerance without polling.

---

## Probe D — Image-store byte growth

Create/open image objects until:
- 1,
- 16,
- 32,
- 64 objects.

Use:
- screen-sized grayscale objects,
- large disk-loaded images,
- mixed sizes.

Collect:
- current/peak decoded bytes,
- RSS,
- creation latency,
- release latency.

After redesign, validate:
- per-object decoded pixel cap,
- global byte budget,
- deterministic rejection/eviction,
- owner-scoped release,
- no use-after-free for operations holding snapshots.

---

## Probe E — Global image-queue head-of-line blocking

Thread/client A:
- run a worst-case `find_image_in_frame` or `find_multi_point`.

While A is executing, clients B/C issue:
- frame release,
- single color pick,
- new frame capture/store,
- OCR region acquisition.

Record:
- time waiting to enter `zx_imageQueue`,
- actual operation compute time,
- end-to-end latency.

Current source should show B/C latency dominated by A's compute time.

After immutable snapshot redesign, store-queue hold time should be limited to lookup/retain/insert/erase.

---

## Probe F — Gray-only capture path

Task 66 with:
- gray=1, BGRA=0,
- gray=0, BGRA=1,
- gray=1, BGRA=1.

Measure:
- temporary allocated bytes,
- memory writes,
- conversion time,
- total capture time.

Compare current gray-only BGRA-intermediate path against direct grayscale render/conversion prototype.

Verify grayscale values against current implementation within an explicit tolerance.

---

## Probe G — H264 native-vs-output-resolution capture

Profiles:
- 7001 fast 640×360 @ 15 FPS
- 7002 eco 426×240 @ 12 FPS
- 7003/7005/7006 640×360 @ 30 FPS
- 7004 worker 480×270 @ 20 FPS

For each:
- SpringBoard CPU,
- capture ms/frame,
- encoder ms/frame,
- memory bandwidth if available,
- thermal state over 10/30 minutes,
- dropped/late frames,
- power/energy,
- end-to-end latency.

A/B current native capture vs target-sized/reusable capture.

This is the benchmark that determines whether P0-08 is the dominant active-stream win.

---

## Probe H — iPad capture ownership/failure stress

On iPad8+ path:

1. Capture 10k frames while running Allocations/Zombies/Guard Malloc where practical.
2. Exercise orientation changes.
3. Simulate/force allocation pressure.
4. Verify every Create/Copy is balanced and every Get-rule object is not released.

Specifically validate removal of the `CGColorSpaceRelease(CGImageGetColorSpace(...))` over-release.

Also verify graceful handling of:
- IOSurfaceCreate failure,
- CGImage creation failure,
- bitmap-context creation failure.

---

## Probe I — Template cache memory

Use distinct templates and cache keys:
- 1,
- 16,
- 33,
- 65+ entries.

Vary:
- template dimensions,
- maxTryTimes,
- scale ratio.

Collect:
- retained cv::Mat bytes,
- peak RSS,
- preparation time before matching timeout begins,
- cache hit rate.

Test an intentionally large maxTryTimes input in a controlled profiling build.

After redesign:
- preparation has its own bounded budget,
- cache reports bytes,
- LRU/global cap holds,
- memory-pressure eviction works.

---

## Probe J — Legacy query vs frame-reuse workflow

Equivalent automation workload:
- 100 color/image queries.

A. legacy path: each query captures current screen.
B. task 66 capture once + tasks 68/69/70 against same frame where semantics permit.

Compare:
- number of native captures,
- CPU,
- memory bandwidth,
- total latency,
- result equivalence.

This quantifies the value of migrating clients without removing legacy protocol compatibility.

---

## Suggested S004 diagnostics

Expose aggregate values through existing status diagnostics:

- screen_capture_count
- screen_capture_total_us / max_us
- screen_capture_native_pixels
- screen_capture_rotation_count
- frame_store_current_count
- frame_store_current_bytes
- frame_store_peak_bytes
- frame_store_expired_bytes
- frame_store_insert_copy_bytes (profiling only)
- image_store_current_count
- image_store_current_bytes
- image_store_peak_bytes
- image_queue_wait_total_us / max_us
- template_cache_current_bytes
- scaled_template_cache_current_bytes

Avoid per-frame NSLog.

## Acceptance criteria

- Frame insertion performs no redundant full-frame BGRA deep copy.
- Expired frame payload does not remain indefinitely while idle.
- Image/template stores have byte budgets, not count-only limits.
- Expensive matching/scanning does not hold the store ownership queue.
- iPad capture has correct CF ownership and failure handling.
- Gray-only capture does not require a retained 4-byte/pixel intermediate unless measurement proves it is necessary.
- Streaming capture cost scales materially closer to output resolution rather than physical display resolution where the platform path allows it.
