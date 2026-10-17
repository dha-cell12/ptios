# C01b — bounded legacy template matching

Date: 2026-10-17. Baseline: user accepted the C01a build at `1b4b382`.
Status: **source implemented; new macOS/iOS build and device qualification pending.**

## Scope and behavior

This slice covers `pccontrol/TemplateMatch.xm`, used by the rootfull/roothide daemon task 21 and the SpringBoard legacy adapter. It addresses the legacy template portion of P1-25, P1-36, P1-37, P1-38 and P2-08. Production TrollStore task 21 uses a separate vImage matcher; its algorithm is unchanged. Both production workflows run the shared regression suite. Prototype TouchPOC remains excluded. Modern `Image.xm` matching and remaining Vision/color/frame reuse belong to C01c.

Successful matches retain the existing coordinate/rectangle fields and first acceptable scale behavior. A completed search without a match still returns the legacy zero rectangle. Coarse step 4, local refinement within ±8, SAD scoring, first-minimum selection, automatic 0.5 downscale above 600,000 screenshot pixels, INTER_AREA preparation and INTER_LINEAR scale interpolation are retained. Unusable scales are skipped before resize and duplicate exact scale factors are omitted; no partial success is returned when the full pyramid cannot be admitted. New resource/parameter/timeout errors are intentional compatibility changes. Each scale now has its own output Mat: the old reused resize destination could overwrite an earlier scale when rounded output dimensions coincided. This removes that alias contamination, so complete matcher output is not claimed byte-identical for every prior configuration; real OpenCV scale behavior needs device comparison.

## Admission policy

| Resource | Limit per process/request |
| --- | --- |
| Template source | 4,194,304 pixels; each dimension at most 8192 |
| Screenshot source | 8,388,608 pixels; each dimension at most 8192 |
| Encoded image file | 16 MiB each; regular, nonempty file |
| Cached/pending/active template payloads | 32 MiB per process, including base dependencies |
| Source-visible work reservations | 64 MiB per process |
| Combined private ledger | 96 MiB per process |
| Prepared scale pyramid | 16 MiB per request |
| Base/pyramid cache cardinality | 16 base entries / 32 pyramid keys |
| Concurrent admitted matching calls | 2 per process |
| `maxTryTimes` | 0–8 |
| `scaleRation` | finite, 0.1–1.9 |
| `acceptableValue` | finite, 0–1 |
| Cooperative request time | 8 seconds from TemplateMatch API entry |
| SAD work | 256,000,000 pixel comparisons per request |

Daemon and SpringBoard adapters reject invalid parameter ranges before screenshot IPC/capture. Existing numeric text conversion remains; this slice does not introduce a new wire parser. Parameters and geometry are rechecked by the matching API. The complete usable pyramid is planned and reserved before any template resize. Conservative ceil-based reservations cover rounding. There is no silent scale clamping or smaller-result fallback on resource failure.

The byte ledger follows immutable shared payloads, including pending builds and readers after eviction/purge. Scaled payloads retain their base dependency. Eviction tries pyramids before bases; when active/pending owners retain the space, a new reservation fails with `template_memory_budget`. Work charges survive Mat destruction and encoded-data autorelease-pool drainage. Cache metadata locks do not cover decoding, resizing or SAD. Two simultaneous misses may do duplicate preparation within the same admission and byte limits.

This is **private source-visible accounting, not an RSS limit**. It excludes caller-owned images/input Mats, the legacy public `templateImage` property, codec/OpenCV scratch, framework metadata, allocator overhead and other subsystems. Aliased buffers/dependencies may be conservatively charged twice. The legacy unused conversion helpers are not redesigned here. A source CGImage is borrowed; newly created contexts/color spaces are balanced and failed context creation is guarded.

## File identity, pressure and cache keys

File loading opens a descriptor, checks size/type, reads at most size+1 in bounded chunks, and verifies the descriptor metadata again before decoding. ImageIO metadata bounds pixel geometry before `imdecode`; decoded grayscale geometry is checked afterwards. Screenshot files are decoded fresh rather than cached.

Base identity includes length-prefixed path, device, inode, size and nanosecond mtime/ctime. Atomic replacement at the same path and restored mtime therefore gets a new base. This is metadata-based cache coherence, not a content hash or a guarantee against hostile in-place modification with forged metadata. An already opened descriptor remains the selected file version.

Pyramid keys include exact float bits, tries and working screen/template dimensions. Neighboring float settings cannot collide through decimal formatting. One memory-pressure source and UIKit warning observer increment an epoch and clear both LRUs. Active snapshots remain valid and charged. Epoch checks on both base and pyramid publication prevent in-flight work from repopulating a cache after that purge. Process-lifetime pressure observers remain installed while idle.

## Deadlines and process configuration

A monotonic request context covers bounded file reads, metadata/decode, CG rendering, downscale/pyramid preparation and search. It also inherits the native cancellation/deadline. SAD checks within rows and charges actual comparison chunks; exhaustion returns `template_work_limit`. Expired/cancelled work returns `template_cancelled_or_timed_out`, including after opaque preparation returns. Exceptions at the public file/CG APIs become `template_operation_failed`.

The eight seconds start at the matching API, **after upstream daemon queues and screenshot IPC/capture**. Opaque filesystem, ImageIO, CoreGraphics and OpenCV operations cannot be preempted. They can overrun; admission remains held until they return. This is not a hard TCP response/completion deadline. Geometry/format/decode/busy failures use explicit `-1;;template_*` responses through existing error plumbing.

`cv::setNumThreads(1)` is configured once on first eligible match instead of every match. It is still a process-global OpenCV setting; interactions with other concurrent consumers and device performance require qualification. This change does not establish a measured CPU/latency saving.

Root daemon task 75/76 diagnostics add `template_match` with cache entries/hits/misses/purges, current/peak reserved bytes and policy limits. These are per-process, best-effort snapshots rather than an atomic account of all process allocations. The daemon snapshot does not include SpringBoard's separate cache.

## CI error-lifetime correction

The user reported both production workflows crashing in the macOS Foundation fixture at `objc_retain` after entering the image tests. Source review found a production lifetime defect: the loader wrote an autoreleased NSError through an `NSError **` out parameter, then drained its internal autorelease pool before the caller's ARC writeback could retain that error. Malformed image/metadata and other in-pool failures could therefore return a dangling NSError.

The pooled wrapper now owns a strong local error. The inner helper returns into that strong local while the pool is still live; only after pool drainage does the wrapper forward the error to its caller. The encoded-data reservation also belongs to the wrapper, so it continues covering bytes through autorelease-pool drainage. File/cache/pixel/timeout policies are unchanged.

The macOS regression adds 1,000 malformed-image failures and a missing-file case, retains the error across both loader and caller pools, reads its description and verifies weak-reference cleanup after the final strong reference is released. Existing public API failure tests remain enabled. The macOS binary now includes debug symbols; ASan/UBSan remain enabled. Windows template-core and native-budget suites were rerun successfully; corrected Foundation execution still requires macOS CI and is not claimed to have passed locally.

## Validation and acceptance

Windows validation passes **36 source-contract runners, 14 native runners A01–C01b and 528 static grep assertions** from the TrollStore workflow. The portable C01b harness compares actual extracted SAD values and coordinates with the frozen pre-change implementation over 3,000 randomized cases. It also exercises planning/overflow/pyramid limits, exact float keys, local/inherited cancellation, work exhaustion, retained owners after eviction, 80,000 concurrent reservations and 100,000 LRU cycles. Existing A06 tests continue exercising the extracted legacy SAD loop.

Both workflows run `check-template-safety.mjs`. On macOS its ASan/UBSan branch compiles the actual TemplateMatch loader, cache, orchestration and SAD code with Foundation/CoreGraphics/ImageIO and real PNG files. OpenCV Mat/resize/decode operations and UIKit's facade are controlled doubles: it checks preflight before decode, immutable replacement snapshots, cache hits, context failure, pressure during decode/resize, preparation expiry, C++ exceptions, live-byte rejection, two-call admission and parent cancellation. It does **not** establish real OpenCV interpolation or bundled-framework ABI correctness.

**The new macOS branch and iOS builds have not run on this Windows host.** Required acceptance:

1. Build rootfull/roothide and run both workflow suites. Confirm the new Foundation fixture succeeds with the supported Xcode toolchains; inspect sanitizer output.
2. On the same device/images compare task `21<template_path>;;2;;0.8;;0.8` before/after for rectangle/field shape, genuine no-match, scale order, resize rounding and large-screen auto-downscale. Include PNG/JPEG, orientation, threshold edges and representative template sizes. Compare real OpenCV accuracy and cold/warm latency.
3. Test tries 0/8 and rejection at 9, finite range boundaries, oversized/sparse/malformed files, pixel/axis limits and pyramids exceeding 16 MiB. Confirm invalid numeric ranges avoid screenshot capture. Verify explicit errors, no partial success and subsequent recovery.
4. Rewrite/atomically replace templates at the same path within one second, restore mtime, vary neighboring float values, change screenshot geometry and apply pressure during active matches. Verify immutable readers, no stale cache publication, bounded counters and cleanup after active readers finish.
5. Stress concurrent calls and parent cancellation during decode/resize/search. Measure actual opaque-operation overrun and busy recovery. Use task 75 diagnostics plus Instruments Allocations/VM Tracker to inspect cache retention, RSS/CPU/energy and UI impact. No device performance or memory saving is claimed from the harness alone.

Next: C01c remaining Vision/color/frame reuse and modern image matcher work; do not mark the whole C01 group complete.
