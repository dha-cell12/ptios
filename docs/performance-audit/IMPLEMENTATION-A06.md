# A06 — P0-14 / P1-45 / P1-46

Date: 2026-10-17. Base: `4cc10e5` (A05 build reported passed by the user).
Status: source implemented; Windows portable tests and source contracts passed. User reported the build passed after both CI corrections, before B01 (`93d2b8b`). New macOS logs were not independently inspected; device qualification remains pending.

## Input and response bounds

Rootfull/roothide in-process bridge rejects a payload above **8192 UTF-16 units** before encoding/dispatch; it never executes a truncated prefix. It also checks **32 KiB UTF-8** and rejects embedded NUL. The exact byte length, excluding the appended sentinel, reaches `processTaskWithContext` along with a child context retaining cancellation, owner metadata and the successful-touch observer. Task's length-aware validation and license policy remain in use. P1-46 is the input truncation finding; P1-45 is the late response limit finding.

`shared/TLinkNativeBudget.h` owns a scoped response sink. `notifyClient` admits each complete NUL-terminated chunk before copying it. Aggregate wire bytes and vector capacity stay within **1 MiB**, or a caller's smaller positive limit; the buffer grows on demand instead of allocating 1 MiB for every RPC. A chunk that does not fit sets a sticky output error, with no truncated success. Scanning stops after remaining capacity + 1 bytes. The bridge uses a one-byte compatibility CFWriteStream for existing non-NULL-stream branches; it no longer creates an allocated-buffer CFWriteStream or copies its unlimited CFData property. All root task stream writes currently route through `notifyClient`.

The cap applies to **accumulated raw wire bytes**, not total process RSS, the later NSDictionary/raw/parts/JS representations, or every upstream task's temporary object. AX rows get conservative escaped-JSON/base64 accounting before retention; OCR results are checked before accumulating additional rows or encoding Tesseract text. Vendor OCR/AX may already have materialized an individual result. Other producers, including shell/history/event serializers, retain their existing upstream allocation behavior; their final sink is bounded, but A06 does not claim a universal producer-memory ceiling. Further representation/storage work remains C02/C03/C05.

Socket callers without a captured native scope keep their existing write/ACK behavior. The production TrollStore bridge is unchanged; the shared AX queue wrapper is inert with no budget. TouchPOC / `poc-trollstore` is untouched.

## Cancellation and deadline contract

A typed bridge operation selects a monotonic deadline: **30 seconds by default**, an earlier positive caller default when present, or explicit shell timeout capped at **300 seconds** and bounded by a positive caller default. Nested wire calls preserve that selected deadline and cannot extend it. Cancellation shares the session's token; it does not mutate the parent context's owner/settings. A thread-local RAII scope restores the previous caller on exit, including exceptions. Queue wrappers explicitly transfer that same budget to image, Tesseract and AX owner queues.

RAW keeps its existing no-cumulative-deadline policy when its context defaults are zero. A cancellation-only budget is created once for each RAW session, avoiding a new budget allocation for every dense touch record. Direct legacy calls with nil context/scope remain compatible.

Checks occur at task entry and again after license refresh, before action dispatch; within gesture waits/steps, native batches, color rows, image/template scales and SAD candidate/template rows; and between AX elements/attributes. Native waits use a condition variable notified by cancellation, with the call deadline as the wait ceiling. Shell's existing termination/drain path now also observes the native budget during its polling loop.

Tesseract receives the remaining recognition timeout, capped at its existing 3 seconds, and a strongly held cancellation delegate; delegate and cached UIImage are cleared in finally after text has been read. Vision gets a 10 ms cancellation monitor only while recognition runs, canceled in finally; result iteration observes the budget, handles empty candidates, and resets inProgress on all exits. Screenshot ownership is released in finally, with a NULL capture guard. AX uses remaining per-query timeouts where the private backend supports them.

**This is cooperative cancellation, not preemption or a hard RPC completion SLA.** A caller still waits behind an earlier non-cooperative operation on a serial queue. On entry, expired queued work is skipped. An OpenCV call, capture/engine initialization, Foundation I/O, private AX call or other opaque native handler may finish after the deadline before a checkpoint can run. Vision/Tesseract cancellation responsiveness depends on those engines. Shell cleanup retains its existing grace/drain/reap behavior, including a potentially blocking reap; VPN/UI/dialog handlers are not redesigned here. TemplateMatch's older local 8-second check remains at scale boundaries; the new native budget reaches the inner SAD loop. No fixed maximum stop latency is claimed. B02/C01/C02/C04/C05 own the remaining scheduling/vendor/IPC work.

## Cleanup and committed effects

Tap/swipe/gesture/zoom use UP cleanup on interrupted waits and exception exits. A batch tracks successful direct raw touch frames and releases remaining fingers on failure/cancel, including cancellation just after its final command. A successful batch preserves intentional held touches, matching the low-level API. PressHardwareKey's finally includes the DOWN call itself: if DOWN committed but its child returns AbortError, UP still runs.

Only frame release, image release and hardware UP receive a cleanup context allowed past cancellation/deadline and license rejection. Output bounds and owner checks still apply. No new DOWN/MOVE action receives this exception. This does not create a general ownership namespace for external/raw finger IDs; deliberate holds across separate successful low-level calls retain their existing caller/session responsibilities.

If a frame/image create returns a successful ID but the budget expired during that operation, the bridge releases that ID with the original owner tuple before returning the stop error. A create with output budget below 1024 bytes is rejected before dispatch so its normal small ID response can be retained for rollback. This covers normal successful allocation responses; it is not an atomic rollback guarantee for a vendor exception before an allocated ID is returned. Other committed native side effects are not undone by a later cancellation.

Errors use the existing result envelope with AbortError, TimeoutError, response_too_large, input_too_large or invalid_payload. A task Objective-C exception returns native_exception, and closes/releases the compatibility stream in finally.

## Verification

`node scripts/check-native-budget-safety.mjs` compiles the actual shared budget and both actual production SAD function bodies using C++14 and MSVC `/W4 /WX` on Windows:

- empty/exact/overflow and multi-chunk writes; reject an entire overflowing chunk; sticky errors; bounded scan and 1 MiB growth/capacity;
- **200 cancellation races** before/during a 60-second wait; deadline wake; cleanup after stop with output limits still enforced;
- nested scopes, worker transfer/restoration and a separate translation unit reading the same TLS slot;
- deadline and cancellation inside both production SAD loops, plus normal matching behavior.

All **36 existing source-contract checks** pass. Native regressions A01–A05 pass: both production injectors at 100k frames each, 10k indicator lifecycles, 22 capture success/fault paths + 20k frames, 8 x 10k scheduler cycles, and 100k RAW records + 8 x 10k playback cycles. git diff --check passes.

Both production workflows now run the new suite. On macOS it additionally compiles actual raw bridge, request-budget prelude, press body, context classes, response writer, queue wrapper and gesture helpers with Foundation/dispatch and ASan/UBSan. Controlled task/hardware/UI doubles exercise Unicode/8192 boundaries, NUL rejection without dispatch, exact/multi-chunk limits, exception/scope cleanup, inherited shell deadlines, expired queue admission, frame/image rollback, gesture/batch UP and hardware UP when DOWN reports cancellation. This integration suite was **not run on Windows**; real UIKit/OpenCV/OCR/private AX/HID code still requires the iOS build/device checks below.

## Build/device qualification

1. Run the macOS CI harness and build rootfull/roothide plus the production StreamControl consumer of shared AX. The latest reported build is A05, before these changes.
2. Submit >8192-unit shell/batch/raw input with an observable suffix; verify no prefix executes. Verify boundary Unicode inputs, embedded NUL and oversized/multi-write responses return explicit failures.
3. Cancel or expire during Task-18, tap/swipe/zoom/gesture/batch, shell, SAD/color, Tesseract, Vision and AX. Confirm no further cooperative steps occur after the next checkpoint, UP/release happens before playback admits another run, and license/owner checks are preserved.
4. Cancel just after frame/image creation and hardware DOWN; check store counts/held keys recover. Repeat under capture/allocation failure, engine exceptions and competing queue work. Record slow vendor/IPC/queue completion paths rather than interpreting the default deadline as a hard SLA.
5. Measure stop latency, allocations/RSS, queue residence and active OCR monitor wakeups on devices. Compare dense RAW playback to A05; no quantitative CPU/RAM/latency gain is claimed by host correctness tests.

Next: B01 (P0-01/P1-01/P2-04), recorder ownership/timing/bounded buffering and batched writes.

## CI harness correction — 2026-10-17

User-provided rootfull and TrollStore logs both stop in the shared macOS A06 harness: the extracted PressHardwareKey body references `TLinkautoJSResultByAdding`, but the generated helper include omitted its definition. The logs show earlier portable/dispatch/playback checks passing; they do not establish that the new artifacts built successfully.

The harness now extracts that production helper as well. Fixture extraction and dependency checks run on every host, so Windows detects this missing-helper case before a macOS run. A normal successful press assertion exercises the result-merging path alongside the existing canceled/deadline press tests. Production runtime behavior is unchanged by this correction.

Windows verification: `check-native-budget-safety.mjs` passes its native suite and fixture dependency checks; `git diff --check` passes. macOS compilation/runtime and both artifact builds still require a CI rerun.

## OpenCV macro correction — 2026-10-17

Rootfull/roothide CI exposed an undeclared `NO` in Image.xm's new scale-loop cancellation branch. Image.h intentionally undefines NO/YES before including OpenCV. Use C++ `false` there and in the new Tesseract recognition-state initializer, which also follows Image.h. Keep the existing OpenCV header policy.

The portable native harness now compiles the complete production `zx_findTemplateSAD` body with NO/YES undefined, alongside its SAD helper. Small unit-scale fixtures check cancellation/default outputs, successful matching, non-matching and empty input; the resize double rejects unexpected use and does not substitute for real OpenCV qualification. Windows native A06, OCR P0/P1 checks, capture/image contract and diff validation pass. New iOS artifact builds remain unverified on this Windows host.
