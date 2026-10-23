# C02a — typed internal touch frames and absolute gesture timing

Date: 2026-10-23 (Asia/Bangkok). Baseline: `f8155bc`; the user reported the C01d3 build passed before this slice.
Status: **source implemented; new macOS/iOS CI and device qualification pending**.
Findings: **P1-04 and P1-05**, with a numeric injection foundation for the later P0-13 typed bridge.

## Result and scope

Rootfull/roothide native tap, swipe, point gesture and zoom helpers now submit integer-pixel `TLinkTouchPoint` frames directly to the existing HID injector. They no longer build NSString touch frames, convert UTF-8 and parse the same numeric fields for every injected frame. The external task-10/61 and RAW text protocol still parses through its compatibility adapter into that same injector. Task-62..65 input/reply formats remain unchanged.

Tap/swipe/gesture/zoom use one monotonic timeline anchored immediately before DOWN. Each wait consumes time already spent preparing/injecting earlier frames and any earlier scheduler oversleep. It uses the existing cancellation-aware native-budget wait, with no busy loop, timer or detached gesture work. License checks, context propagation, owner queues and cleanup UP remain at their existing boundaries.

This slice changes only the root pccontrol gesture/injection implementation. Production TrollStore and excluded TouchPOC behavior are unchanged. Adding a validator to the shared touch header does not select a new TrollStore injection path.

## Typed boundary and compatibility

`performTouchFrame(const TLinkTouchPoint *, int)` validates the whole frame before any HID object allocation or active-finger state change:

- Count `1..9`, matching the existing one-digit wire count.
- Types UP/DOWN/MOVE (`0..2`), fingers `0..19` and integer coordinates `0..9999`.
- Duplicate finger entries keep the legacy sequential semantics.
- Parent/child ownership, unchanged active-finger appends, all-or-nothing allocation/state commit and normalized HID coordinates remain in one implementation shared by typed and wire entry points.

Internal CGFloat inputs retain the old fixed-point conversion: clamp/round to a five-digit tenth-pixel field, then truncate to integer pixels. The typed path does not introduce subpixel HID coordinates. Zoom still preflights every radial point before DOWN and submits all participating fingers in one parent frame.

This API is an internal injector, not a replacement licensed task entry. Native JS calls still pass through the current bridge/raw task dispatch and enforcement before reaching these helpers. P0-13's first request formatting/response sink/text parsing, as well as helper RPC transport/config/dedupe, remain subsequent C02 work. Existing task helpers' injection-failure reporting and the HID dispatch thread-safety model are not redesigned here.

## Timing semantics

For a duration `D`, interval count `N` and step `i`, the target is `start + floor(D * i / N)`. The implementation divides before multiplying and saturates absolute addition, avoiding overflow and cumulative integer-division truncation. The endpoint is exactly `start + D` when representable.

| Operation | Targets |
|---|---|
| Tap | UP after one duration; DOWN work consumes that duration |
| Swipe | MOVE at `i / steps`, `i=1..steps-1`; UP at duration at the exact final coordinate |
| Point gesture | MOVE at `i / (point_count-1)`; final point at duration, followed by UP |
| Zoom | MOVE at `i / (steps-1)`; final radius at duration, followed by UP |

Point gestures previously emitted their first MOVE immediately and slept after each MOVE. They now wait before that MOVE, consistently distributing the declared points from DOWN to the final point. This is an intentional timing correction with unchanged wire format and point/frame order. Swipe/zoom retain their established endpoint geometry and frame counts.

Late targets do not trigger additional sleeping. Frames remain ordered and no point is skipped; if frame work exceeds the interval, overdue frames may be delivered back-to-back. Final-frame cancellation in point gestures/zoom returns failure and releases owned fingers in finally cleanup. An already-expired request is rejected even if its target time is in the past.

This is cooperative scheduling, not a hard completion deadline or a real-time HID guarantee. Opaque injection time, OS scheduling and UP cleanup may extend the measured end of a gesture. Device measurements must determine actual jitter, input delivery/visual behavior and whether a separate stale-frame policy is needed.

## Validation

- Windows: all **36 source-contract and 20 native runners pass**, plus **528 TrollStore workflow source grep assertions**. Strict warnings remain enabled; the existing macOS sanitizer flags are retained.
- The actual root HID injector and actual Task numeric helpers are compiled into the portable touch harness. It checks whole-frame rejection without allocations/state mutation, 3,000 typed/wire parity frames including duplicate fingers, allocation rollback, concrete rounding/clamping boundaries, synchronized three-finger frames and 100k typed frames with balanced live HID references. The existing malformed/guarded-truncation and 100k wire lifecycle tests continue for both production injectors.
- Portable timeline tests cover `1..512` intervals, fractional remainders, exact final targets, zero duration, saturating arithmetic, consumed work/oversleep and cancellation/deadline rejection of overdue waits.
- The existing macOS actual-gesture fixture now compiles the production timeline/gesture bodies with a controlled clock/wait and HID boundary. It asserts timestamp sequences for tap/swipe/point gesture/three-finger zoom with 7 ms frame work and 2 ms oversleep, ordered overdue frames with 40 ms work, exact swipe final coordinates, and cancellation on the final MOVE with owned-UP cleanup. Its existing real native-budget cancellation/queue/context tests remain.
- Both production workflows already run these runners and match all modified test files/shared headers. **The new Foundation/macOS branch and iOS builds were not run on this Windows host.** Private HID delivery and real gesture timing require device qualification.

## Acceptance and remaining C02

Build rootfull and roothide, then compare task-62/63/64/65, in-process JS and helper-driven calls at 100/500/1000/5000 ms with 30/60/120 steps. Record actual frame timestamps and p50/p95/p99 endpoint error, CPU/allocations and stop-to-UP latency. Test cancellation during DOWN, waits, final MOVE and overloaded injection, including two/three fingers and fingers 0/19. Verify RAW/task-10/61 payload/reply and active-finger behavior remain compatible.

After the C02a build checkpoint, continue the structured in-process request/task entry for P0-13 without bypassing context/license/output/cleanup gates. P0-12 event-driven helper transport, P1-40 immutable policy snapshots and P1-41 byte-bounded replay/dedupe remain open, including reconnect ordering and no repeated side effects. C02 is not marked complete by this internal-frame slice; C01 device acceptance also remains open.

## Following checkpoint

The user reported the C02a build at `72fef91` passed before C02b1. Real HID/timing/performance qualification remains open. The next implemented slice is `IMPLEMENTATION-C02B1.md`, covering structured tap/swipe/longPress requests.
