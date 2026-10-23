# C02b2 — structured point gesture and zoom requests

Date: 2026-10-24 (Asia/Bangkok). Baseline: `c4b8611`; the user reported the corrected C02b1 build passed before this slice.
Status: **source implemented; new macOS/iOS CI and device qualification pending**.
Finding: **P0-13, point gesture/zoom portion**. Batch and other typed methods/helper transport remain open.

## Result and scope

Root JS `gesture` and `zoom` now use the licensed numeric entry introduced by C02b1. All five touch methods (tap, swipe, longPress, point gesture, zoom) avoid aggregate legacy request strings, compatibility CFWriteStreams, raw task dispatch, captured response vectors and successful reply splitting. The public `{ok, raw, parts}` result shape and synchronous call ordering remain.

Task 64's RAW adapters and typed requests share point/zoom executors. Point paths are decoded once into a bounded vector and no longer reparsed during each MOVE. Zoom shares its finite/geometry preflight, radial interpolation, synchronized multi-finger frames, absolute timeline, cleanup and diagnostics. Legacy batch still invokes its adapters sequentially. Production TrollStore/TouchPOC are unchanged.

## Compatibility and bounds

- Point gestures still accept 2..512 array/object points with the old missing-coordinate/default/finite rules. JS options keep duration/durationMs precedence, integer conversion, `0..60000` clamp and finger default 0. Coordinates keep the old `%.2f` then floatValue conversion.
- The old JS raw dispatch rejects aggregate requests longer than 8,192 UTF-16 units. Numeric gestures preserve that boundary by counting each scalar's legacy ASCII length plus commas, separators, signed finger, duration and task prefix, without constructing the request string. All source points are validated before the size decision, preserving early JS argument-error precedence. Rejection still returns `input_too_large` before license/injection. ASCII-only numeric payloads satisfying that limit also satisfy the old 32 KiB byte limit.
- Zoom keeps double precision after `%.2f`, matching its NSScanner double parser rather than narrowing through float. Defaults, rejection strings and preflight order remain. The angle's nonfinite error still comes from task 64 after authorization/diagnostic reset; the four required center/radius arguments retain the bridge's early finite check.
- Zoom attempts/reset occur once per authorized call before parsing/preflight; success/rejection/cancellation/exception/frame counters and last fields remain shared with RAW. The base-finger range comparison now subtracts the already-validated 2/3 finger count from 20, avoiding signed overflow for extreme int input while rejecting the same unsupported range.
- The point vector holds at most 512 double-coordinate pairs (8 KiB payload, plus container/allocator overhead). It remains owned by the synchronous caller and is not copied into detached work. RAW parsing retains its original shape/numeric error order before calling the common executor; an additional bounded executor validation pass preserves safety for direct callers.

Scalar C-locale formatting/parsing remains deliberately bounded on the stack to retain old decimal behavior. This change does not claim to remove every scalar conversion, dictionary allocation or opaque library allocation.

## Execution and authority

Both kinds map only to task 64 and use the existing license policy. The entry preserves owner/token/output defaults and parent deadlines, checks stop before and after authorization, then invokes the selected executor. There is no per-point authorization bypass, retry or asynchronous completion. Denial/pre-expiry produces no DOWN.

C02a timing is retained: wait before each point/zoom MOVE using the original monotonic start, retain ordered overdue frames and finish at the exact endpoint before UP. Point cleanup uses finally; zoom retains its existing all-finger cleanup/exception handling and diagnostics. Typed output-cap/stop mapping is unchanged from C02b1, including detection after a side effect and small control-error replies outside the old sink. No hard timing or opaque HID-failure recovery guarantee is introduced.

## Validation

- Windows: all 36 source-contract runners, 20 native runners and 528 TrollStore workflow source grep assertions pass, including native-budget/request, Zoom contract and production touch checks. The existing 100k scalar suite now checks both float and double legacy conversions and encoded lengths, signed zero/extreme values, integer digit lengths including INT_MIN/MAX and exact gesture-cap boundaries.
- Source/fixture checks require all five bridge branches to call the typed entry, forbid aggregate raw dispatch/format/CF stream use there, retain the post-license stop checks, and compile the typed entry without YES/NO macros in the existing Foundation fixture. Production option/point helpers are extracted rather than replaced by test implementations.
- New macOS actual-bridge/executor tests compare 80 point paths, 40 zoom plans and boundary/error cases to the old NSString encoder plus actual RAW adapters. Comparisons include raw/parts, HID frames, controlled timestamps and zoom counter deltas/last fields (excluding wall-clock timestamp). Exact 8,192/8,193-character point paths verify the retained ingress boundary. Cases include 512 points, float overflow, missing object fields, duration/finger limits, spread/pinch, 2/3 fingers, steps/radius/angle/base-finger/bounds errors and extreme signed base finger.
- Task-64 cases also check denial, cancellation during authorization/after DOWN, malformed input before the gate, Objective-C/C++ exceptions during MOVE with owned UP, and absence of raw-dispatch calls/response-vector allocation. Existing tap/swipe/longPress/native budget/cancellation tests remain.
- Strict warnings and existing ASan/UBSan flags remain. Existing workflow paths/runners cover all modified files. **The new Foundation/macOS cases and iOS builds were not run on this Windows host.** Actual Darwin numeric parity, diagnostics, HID delivery and device allocations/timing require CI/device qualification.

## Acceptance and next slice

Build rootfull/roothide in observe/enforced modes and exercise JS and RAW task 64 with the same paths/radial plans. Compare frame coordinates/order/count, returned error/parts, diagnostic counters and final-UP state. Cover exact input-size boundaries, 512 points, authorization expiry/cancellation, exception paths, two/three fingers and a following gesture after each failure. Record allocation counts, call latency, endpoint error and stop-to-UP versus C02b1; no measured performance gain is claimed from source/tests alone.

After C02b2's checkpoint, continue structured batch while preserving whole-input validation, sequential order, first failure and owned cleanup. P0-12 event-driven helper RPC, P1-40 policy snapshots and P1-41 byte-bounded replay remain open, as do other measured P0-13 methods and C01 device acceptance.

## Following checkpoint

The user reported C02b2 build `4d1ce08` passed before C02b3. Structured object batches are tracked in `IMPLEMENTATION-C02B3.md`; C02b2 device qualification remains pending.
