# C01c2 — bounded legacy color operations

Baseline: `528655c`; the user reported the C01c1 build passed before this slice.
Status: **build accepted by the user at `5ae231b` before C01c3a; device qualification pending**. This does not replace independent inspection of CI logs or device measurements.

## Scope and resulting behavior

Rootfull/roothide legacy tasks **23** (pick RGB) and **28** (range, absolute multi-point check, multi-point search) now share checked preparation, owned graphics resources and portable scan kernels. This addresses P1-33, P1-34 and P1-35, plus the validation/ROI-buffer part of P1-32. The native JS point-table encoder is corrected to the actual root protocol. Production TrollStore color implementations and prototype TouchPOC are unchanged.

The old range path could capture a screenshot and return from coordinate/RGB/skip validation without releasing it. Pixel and range helpers also used unchecked crop/context allocation, signed buffer/offset arithmetic and `skip+1`; multi-point scanning decoded NSValue in its innermost loop. New scope-owned image/context/color-space/buffer objects release on success, early return and exception. Buffer bytes are released before their private reservation. Borrowed images passed to class selectors remain borrowed.

Valid results preserve their shapes and row-major first-match ordering: task 23 RGB fields; task-28 range `x;;y;;r;;g;;b` or five `-1` fields; absolute check `1`/`0`; multi-point search `x;;y` or `-1;;-1`. The outer task envelope is unchanged. Deviation mode 1 retains integer truncation of finite tolerance; similarity mode 0 retains the old sum-of-channel-differences formula. Sample stride remains `skip+1`, now evaluated in 64 bits. New validation, resource and timeout errors are deliberate behavior changes; no partial match is returned after a budget failure.

## Policy limits and semantics

| Resource or parameter | Policy |
| --- | --- |
| Raw color payload | At most 256 KiB, valid UTF-8 C-string payload |
| Point table | At most 128 KiB / 512 pipe-separated entries; at least one nonempty valid entry |
| Wire integers | Complete signed 32-bit decimal token, optional surrounding whitespace; malformed/overflowing/fractional tokens rejected |
| Target RGB | 0–255; range minimum must not exceed maximum |
| Match mode/value | Mode 0 similarity in [0,1]; mode 1 deviation in [0,255]; finite values |
| Skip | Nonnegative signed 32-bit; INT_MAX is safe and samples the initial position only on admitted geometry |
| Source image | At most 8,388,608 pixels and 8192 per axis |
| Rendered ROI | At most 4,194,304 pixels / 16 MiB RGBA per request |
| Private RGBA ledger | At most 32 MiB per process across pending/live buffers |
| Concurrent calls | At most 2 per process, including capture/preparation |
| Local cooperative time | 3 seconds from raw handler / direct selector entry |
| Scan work | At most 16,777,216 sampled RGB-point comparisons per request |

Validation that does not need actual image geometry runs before capture, including channel/mode/table/skip errors and known-invalid coordinates. Actual source geometry, ROI clipping and points against the real image are checked after capture; all such failures now release the image. Integer parsing rejects formerly accepted junk/default-zero or wrapped inputs. Mode values other than 0/1 and negative multi-point skips are rejected explicitly.

For raw range requests, nonpositive width/height still extend to the remaining source edge, and positive oversized extents are clipped without overflowing addition. Single-range/pick origins must be in bounds. Multi-point search retains its old origin-clamping behavior; point offsets can be negative. Anchor/crop bounds use 64-bit arithmetic, including INT_MIN negation and extreme offset spans. Impossible anchor geometry returns the normal no-match shape. Absolute point checks reject out-of-bounds coordinates. Zero-width/height class-selector range requests use the same extension convention; fractional or invalid direct-selector rectangles fail safely instead of ambiguous crop geometry.

The old class selectors have no NSError parameter. They retain RGB -1 / range no-match fallbacks for failure; use the task entry points when explicit `-1;;color_*` errors are required. Raw handlers report capture, geometry, allocation/crop/context, busy, memory, parameter/table, work and cancellation/deadline errors. An Objective-C or C++ exception is converted to `color_operation_failed` after scope cleanup.

The private ledger covers source-visible RGBA allocations reserved before calloc, including pending work. It does **not** count the full screenshot, crop backing, CoreGraphics scratch/caches, Foundation parsing temporaries, allocator overhead, other subsystems or total RSS. Geometry/input/cardinality limits additionally bound source-visible work; they do not establish a process memory guarantee or measured saving.

## Scan and native client integration

Point tables are parsed once into a vector. Absolute checks and candidate loops read those numeric values directly. Portable production range/multi-point kernels perform no Objective-C messaging. The work counter charges sampled points; local/parent cancellation is checked at row/block boundaries and before successful completion. Existing native cancellation/deadline remains effective. Expired work returns an error even if an opaque capture/render finished successfully after the deadline.

Capture, crop/render and system allocation are cooperative boundaries, not preemptible operations. Admission stays held until an opaque call returns. The three seconds exclude upstream command/license queues, and do not promise a hard TCP response/completion time. No new heavy-work queue or recognition/capture parallelism is introduced.

The native bridge helper and its inline legacy-color caller previously emitted semicolons inside each point and `,,` between points, conflicting with both root table parsers and the normal legacy JS encoder. They now use one helper emitting `x,,y,,r,,g,,b|...`, including r/g/b aliases and the existing 512-entry/finite-coordinate validation. This also corrects table encoding for native frame multi-point calls that already used that helper. Numeric coercion of typed JS options is not redesigned in this slice; strict validation described above applies to the resulting wire fields.

## Validation and pending acceptance

Windows validation passes **36 source-contract runners, 16 native runners A01–C01c2 and 528 TrollStore source grep assertions**. The portable color suite compares the production predicate against the frozen `528655c` primitive over 100,000 cases and compares production range/multi-point scans against an independent legacy-order oracle over 5,000 randomized cases, including coordinates and first match. It exercises integer/nonfinite boundaries, clipping, INT_MIN/INT_MAX offsets, INT_MAX stride, three-second/parent/work stop conditions, admission and 80,000 concurrent reservation lifecycles with zero final charges.

Both workflows run `check-color-safety.mjs`. On macOS its ASan/UBSan branch compiles the actual ColorPicker parser, rendering adapter, kernels, public selectors and extracted native table encoder. Foundation/CoreGraphics and RGBA images are real; capture/allocation/crop/space/context/draw failures and a monotonic offset are controlled. It checks wire shapes, channel values, encoder-to-parser integration, 1,000 invalid pre/post-capture lifecycles, explicit failures, error retention across a caller pool, source/ROI bounds, live-byte rejection, busy/cancellation and zero final buffers/providers. The actual display capture stack, physical coordinate orientation and full native JS context are not executed by this fixture.

**The new macOS fixture and iOS builds have not run on this Windows host.** Required acceptance:

1. Run both workflows and build rootfull/roothide with sanitizers enabled. Exercise native JS `isColors`, `findMultiColor` and frame multi-point helpers to confirm the corrected table grammar reaches their existing parsers.
2. Compare task 23/28 results on fixed screen patterns and orientations, single/range/absolute/offset modes, stride values, deviation/similarity edges, zero-size/clipped regions and genuine no-match. Confirm RGB channel order and coordinate mapping remain correct.
3. Exercise invalid pre/post-capture coordinates, oversized ROI/source, malformed/huge tables, count 512/513, invalid numbers/modes and INT_MIN/INT_MAX inputs. Check explicit errors, no partial success and recovery.
4. Stress concurrent calls, low memory and native cancellation during capture/render/scan. Verify scope cleanup and no retained screenshot after failed validation. Use Allocations/VM Tracker and Instruments to measure RSS, latency, CPU and opaque-operation overrun; do not infer savings from source limits.

C01c3a now implements explicit root Vision frame selection; see [IMPLEMENTATION-C01C3A.md](IMPLEMENTATION-C01C3A.md). Remaining C01c3b covers frame-color validation/scan budgets and modern image matcher work. Legacy commands still capture a fresh full display per request; this slice does not complete P1-28/P1-32/P1-39 capture reuse or upstream queue isolation. The whole C01 group remains open.
