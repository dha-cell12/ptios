# S005 Benchmark Plan — OCR / Template / Color

## Tesseract cache cardinality
Run same language/OEM with 1/10/100 distinct whitelists and several PSM values. Capture cache entries, RSS, Tesseract/Leptonica allocations, retained image bytes and engine-init time. Compare current key `lang|oem|psm|whitelist` with bounded `lang|oem` engine reuse plus per-request settings.

## Tesseract scale-up memory
Test ROIs 320x100, 640x360, and full-screen classes at scale 1/2/4 with none/Otsu/adaptive threshold. Record preprocess/recognition/total ms, allocated bytes and peak RSS. Validate a post-scale pixel/byte budget and no unnecessary scale=1 clone.

## OCR queue latency
Burst 1/4/10/25 requests. Record enqueue, worker-start, preprocess, recognition and total response time. Separate the engine's 3-second recognition limit from queue wait.

## Vision region overhead
Compare current full capture -> CI crop -> Vision against task-66 frame snapshot -> ROI -> Vision for small/medium/full regions. Measure native captures, allocations, capture ms, Vision ms and total latency.

## Template deadline correctness
Use deterministic no-match workloads while varying screen/template dimensions, maxTryTimes and scale ratio. Record preparation time, each SAD duration, candidate positions and total comparisons. A profiling 1-second deadline should abort from inside SAD close to deadline rather than only between templates.

## Template preparation bounds
Exercise extreme maxTryTimes/scale ratios and large templates in a controlled build. Validate max scaled pixels/bytes, bounded cache retention and preparation included in deadline.

## Color multi-point complexity
Regions 100x100 / 640x360 / full screen; point counts 1/5/20/100; skip 0/1/3/7. Compare legacy NSArray/NSValue loop with C++ vector and task-69 frame implementation.

## Invalid color request leak
Loop malformed requests 10k times and graph live CGImage/IOSurface-related allocations and RSS before/after cleanup refactor.

## Capture-once/use-many workflow
Equivalent automation: 20 color ops + 5 template searches + 2 OCR regions. Compare legacy recapture-per-call versus one task-66 capture + frame-backed consumers.

### Suggested counters
- tess_cache_entries / estimated_bytes
- tess_queue_wait_total_us / max_us
- tess_preprocess_total_us / max_us
- tess_recognition_total_us / max_us
- template_prepare_total_us / max_us
- template_sad_total_us / max_us
- template_deadline_abort_count
- color_candidates_tested
- color_point_comparisons
- color_deadline_abort_count

Avoid per-pixel/per-candidate logging.
