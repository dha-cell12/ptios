# C01c3b — frame-color and modern image request bounds

Date: 2026-10-23 (Asia/Bangkok). Baseline: `71de52b`; the user reported the C01c3a build passed before this slice.
Status: **source implemented; new macOS/iOS CI and device qualification pending**.

## Scope

Rootfull/roothide `pccontrol/Image.xm`: task 49 (fresh screenshot matcher), task 68 (frame matcher), task 69 (frame color) and task 70 (frame batch). This closes the planned source slice for remaining frame-color validation and modern matching budgets under C01/P1-25/P1-32..39. Production TrollStore has separate implementations and is unchanged; both workflows run the shared regression runner. TouchPOC is excluded.

C01a–C01c3a build reports do not replace device qualification. Remaining C01 queue/deadline boundaries must be reviewed next (C01d); the entire C01 group is not declared complete here.

## Frame color contract

Task 69 retains its five modes (`pick`, `pick_many`, `search_single`, `is_colors`, `find_multi_point`), existing result fields, row-major first-match ordering, inclusive RGB limits and timing/age fields. No screenshot fallback is introduced. Valid small-frame pixel requests keep their wire layout.

Admission now checks complete numeric tokens rather than Foundation's prefix/zero conversions. IDs must be positive signed-32-bit values. Nonfinite, overflowing or trailing-junk numbers fail. Coordinates use checked rounding before conversion to int; point conversion uses the stored frame scale, finite and in (0,16]. Unknown coordinate modes fail; `pixel`/`point` remain case-insensitive in these existing adapters. `max_age_ms` is 0..5000, with 0 retaining the default 1000 ms. Both hard TTL and max-age are checked at admission, even when expiry cleanup has not run yet. A reader admitted before release/expiry keeps its immutable snapshot until completion.

BGRA reads validate positive dimensions, at most 8192 per axis and 8,388,608 source pixels, stride >= width*4 and sufficient vector length for every row, including padded strides. RGB table values and range endpoints must be 0..255, with min <= max. Mode 0 similarity is 0..1; mode 1 deviation is 0..255. Skip is 0..1023, producing a checked step 1..1024. Point lists/tables allow at most 512 entries and 32768 UTF-16 code units; empty separator entries retain their previous handling within that bound.

Task 69 has a three-second cooperative request budget from handler entry, a 16,777,216 point-comparison allowance, the shared two-slot color admission and the existing two-slot image compute admission. Each BGRA sample consumes work; row/periodic checks and the final response check observe local and inherited cancellation. Exhaustion returns `color_work_limit` or `color_cancelled_or_timed_out`, rather than an empty or partially successful result.

ROI origin clamping and zero/negative extent meaning 'remaining edge' remain. Extent clipping subtracts from the canvas instead of adding untrusted ints. Multi-color anchor geometry uses signed 64-bit intermediates. **Point-mode offsets are scaled once, preserving negative offsets**; the old multi-point scan used offsets without applying point scale; the shared coordinate converter also clamped negative absolute points to zero. For example, offset (-1,0) at stored scale 2 now samples two pixels left of the anchor. Out-of-canvas absolute points do not silently become (0,0).

## Modern matcher contract

Tasks 49/68/70 share an eight-second cooperative request budget from handler entry, inherited native cancellation and a total 256,000,000 grayscale-comparison allowance. A batch does not restart this budget for each operation. Each actual SAD row charges its width before comparisons, preserving the previous early-out arithmetic, first-minimum tie behavior and score formula. A stopped matcher becomes an explicit error, not an ordinary no-match record.

Scale endpoints must be finite in 0.01..16, acceptable in 0..1, scale step finite and >0, and pixel skip 0..1023. Reversed endpoints still swap. The previous nonpositive-step fallback is now rejected explicitly. A checked plan allows at most 64 scale iterations, including unusable scales, and rejects float steps that cannot advance. Normal request traversal retains the historical descending float subtraction and OpenCV rounding, interpolation selection, coarse/refinement scans and >600k-pixel half-resolution policy.

The planner validates source ROI <= 8,388,608 pixels, template <= 4,194,304 pixels and 8192 axis bounds before resizing. Scales whose rounded dimensions cannot fit the working source are skipped **before** resize. This avoids allocating a huge unusable template. No template pyramid cache or cross-call result cache is introduced.

A conservative scratch reservation covers RGBA+gray source conversion, reduced source when required and the largest simultaneously live scaled/reduced template pair. Reservations are at most 32 MiB per request and 64 MiB across active modern requests. They precede conversion for task 49 and resizing for every matcher. Each batch operation finishes/destroys its Mats before the next reservation can replace the prior one. Frame callers conservatively reserve the same conversion allowance even though they borrow gray pixels; oversized requests may therefore need a smaller ROI. Existing B02 immutable frame/image charges continue independently.

The scratch estimate excludes original capture/CG framework backing, stored template/frame payload (already B02 charged), opaque OpenCV/framework scratch, Foundation temporaries and process RSS. It is not a total-process memory bound. Fresh task 49 still captures the full display once; invalid wire parameters fail before capture, geometry and scratch are checked before ROI conversion, and owned screen/crop images have unwind-safe guards.

## Frame batches

Task 70 allows at most 64 operations and 65536 UTF-16 code units of operation text. Each `img` operation is fully typed and has a single valid scale; each `pick_many` list has at most 512 points. Point samples consume the same batch request work allowance. BGRA stride, gray canvas consistency, numeric coordinates and point scaling are checked before pixel access. Reply grammar, operation ordering and explicit `auto_release` remain. A known cancellation before completion does not execute auto-release or return partial success; a cancellation arriving after the release commits cannot undo that release.

## Validation

Windows results for this slice:

- All 36 source-contract runners, 18 native regression runners and 528 TrollStore source grep assertions passed.
- 3000 comparisons of the actual modern scale/SAD functions against a frozen pre-change implementation, using the same controlled resizer, preserved match/no-match, coordinates, dimensions and score. Added >600k-pixel/odd-size half-resolution oracle cases.
- Plan/count/non-progress/invalid-number/scratch-admission/work-exhaustion/pre-cancel cases passed, with scratch returned to zero. Signed coordinate, extreme offset and padded-stride geometry cases passed.
- Existing native budget tests compile the modified actual SAD/scale helpers and still pass cancellation/deadline/resource regressions. Existing storage fixtures still compile the actual block-to-C++ admission boundary.
- Both workflows include `check-modern-image-safety.mjs`, using strict compiler warnings, ASan and UBSan on macOS. Its new Foundation/CoreGraphics fixture compiles all four actual handlers and their parsers, with controlled capture/CV and real Foundation/CG ownership. It covers the five color modes, exact legacy fields, negative point offsets, overflow/junk/NaN, list cap, padded stride, TTL, matcher admission, batch replies and pre-cancel behavior. **That new macOS branch was not run on this Windows host.**

Controlled interpolation is a test double, not evidence of real OpenCV accuracy or memory behavior. New rootfull/roothide/TrollStore CI and device acceptance remain pending. Device checks should compare point/pixel coordinates in both orientations, real template interpolation and scores, negative-offset patterns, concurrent release/expiry, cancellation under long scans, and small-ROI versus rejected large-ROI behavior. Capture/CV calls and synchronous owner waits remain opaque/non-preemptible portions of a cooperative deadline; no hard TCP completion deadline or measured CPU/RAM/energy improvement is claimed.
