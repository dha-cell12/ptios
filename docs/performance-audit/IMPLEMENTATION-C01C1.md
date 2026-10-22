# C01c1 — root Vision lifecycle and cooperative request limits

Date: 2026-10-18 (Asia/Bangkok). Baseline: `4e6ef06`; user reported the corrected C01b build passed before this slice.
Status: **build accepted by the user at `528655c` before C01c2; device qualification pending**. This report does not replace independent inspection of macOS sanitizer logs or device measurements.

## Scope

This slice changes rootfull/roothide legacy task 27 and its `VKOcrManager` adapter: the deadline/lifecycle part of P1-29 and remaining candidate/debug cleanup in P1-30/P1-31. A06 had already guarded empty candidates in normal recognition and reset `inProgress` in a recognition finally block. C01c1 extends that foundation instead of claiming those original defects were still wholly unfixed.

Production TrollStore Vision has different UI-service/worker paths and remains unchanged. Both workflows run the new shared regression. TouchPOC is excluded. P1-28/P1-39 capture/frame reuse, ColorPicker, modern Image.xm matching and queue isolation remain separate work; task 27 still captures a fresh full display before cropping. A smaller ROI does not eliminate full-display capture cost.

## Request policy and compatibility

The root task creates a shared monotonic **8-second cooperative context at handler entry**, before parsing and screenshot capture. Manager initialization, CI orientation/crop, Vision execution, result formatting and optional debug work share it. Existing native cancellation/deadline remains effective. The adapter starts its own context if constructed directly; a directly supplied path/CGImage may already have been decoded/converted by its convenience initializer before that context begins.

At most **two admitted contexts per process** may exist. Excess requests return `vision_busy` before capture. A context is retained through manager lifetime, including the optional debug phase; retaining a manager after use retains its admission until deallocation. This is a request-scoped adapter, not an idle engine cache. No extra recognition worker queue or recognition parallelism is introduced. Existing upstream queues are outside the local timer, so this does not complete the ingress isolation part of P1-29.

Source image dimensions must be finite, positive and at most 8192 per axis, with at most **8,388,608 source pixels**. ROI origins must be finite, nonnegative and inside the oriented source; dimensions must be finite and nonnegative. Zero width/height retains the legacy meaning of extending to the remaining edge, and positive oversized dimensions are clipped to that edge. The conservative ceil-based ROI is capped at **4,194,304 pixels**. Invalid numeric parameters are rejected before capture when possible; actual oriented geometry is checked before constructing the cropped Vision handler. The CI extent origin is included in crop mapping.

Results retain five fields per observation (`text,,x,,y,,width,,height`), `;;` separators, order and existing task envelope. Completed empty observations still return an empty result. Empty candidates/text, missing boxes and nonfinite/unrepresentable boxes are skipped instead of dereferencing/indexing invalid data. Rectangle height explicitly uses floating-point absolute value. Valid coordinate behavior and request revisions 1/2 by OS version remain; compare rounding and real Vision output on devices.

The adapter admits at most **4096 observations** and **1 MiB of formatted UTF-8 output**, also respecting a smaller inherited native output cap. Excess output is an explicit error, not a truncated success. New limits introduce deliberate resource/geometry rejection cases. `vision_*` errors distinguish busy, parameters/ROI, perform failure, observation/output bounds, timeout/cancellation and operation failure. A failed `performRequests` return is handled even when its error pointer is nil. Existing language-list request format is retained; that subtask also shares admission/deadline checks at the root handler boundary.

These are geometry/concurrency/output limits, **not a byte ledger or RSS guarantee**. CoreImage, Vision models, graphics contexts, framework caches and opaque scratch allocations remain outside measured accounting. A full debug image can still allocate at source size. No RAM/CPU/energy saving is claimed without device measurement.

## Ownership, cancellation and debug cleanup

The old completion block captured manager ivars strongly: manager -> request -> completion -> manager. The adapter now reads synchronous `request.results` directly and no longer creates that cycle. Normal caller cleanup can release source CIImage, request/handler and admission. Configuration setters now exist in daemon builds too; only UIKit debug drawing remains excluded there.

`inProgress` admission/reset is synchronized. Recognition errors, exceptions and cancellation reset it in `@finally`. A request-active 10 ms dispatch timer checks the local/parent context and invokes `VNRequest.cancel`. It holds a weak context and the active request, without retaining the manager. Finally cancels the source and drains its private serial queue before clearing `inProgress`, preventing an already-running cancel callback from reaching a later invocation.

Vision `performRequests`, CI operations, capture, JPEG encoding and filesystem writes are opaque cooperative boundaries. Cancellation cannot forcibly interrupt them; a handler/cleanup can overrun while admission stays held. Checks after they return reject expired work. There is **no hard 8-second TCP/completion guarantee**. Real Vision request reuse after cancellation must be qualified; current production task callers construct fresh managers.

Debug output guards empty candidates and failed boxes, uses a scale-1 graphics context and closes that context in `@finally`, including returns and exceptions. Output setup/write errors propagate, and its busy flag always resets. The task skips debug after recognition failure and rechecks deadline after optional work. Debug output is still an optional file side effect: a write already committed when the deadline expires is not rolled back. A graphics/context failure becomes an explicit error rather than an unchecked draw.

No new internal autorelease pool surrounds NSError out parameters. The strong error/pool correction from C01b remains intact.

## SDK warning correction — 2026-10-23

The user reported both workflows stopped compiling the macOS Vision fixture under `-Werror`: `VNImageRequestHandler` requires a nonnull options dictionary, and newer Clang additionally diagnoses the rounded conversion of `INT_MAX/2` in the float coordinate comparisons. Production now passes an empty dictionary (`@{}`) for default options. A shared finite/magnitude guard widens coordinates to double before comparing against the exactly represented conservative integer threshold; float coordinate calculation and ordinary result formatting remain unchanged.

Portable regressions cover the exact positive/negative threshold, fractional values beyond it, the float value rounded up from that threshold, the preceding float, NaN and infinity. The actual-manager macOS fixture also includes a box whose calculated float coordinate rounds past the threshold and must be skipped. `-Werror`, ASan and UBSan remain enabled. Portable Vision/native-budget/color checks pass on Windows; corrected Apple SDK compilation and Foundation execution remain pending CI.

## Validation and required acceptance

Windows validation passes **36 source-contract runners, 15 native runners A01–C01c1 and 528 TrollStore source grep assertions**.

The portable policy suite covers 100,000 ROI plans, axis/pixel/nonfinite boundaries, zero/clip behavior, exact eight-second boundaries, inherited cancellation/output exhaustion, nested TLS restoration, two-context admission and 80,000 concurrent context lifecycles.

`check-vision-safety.mjs` is added to both production workflows. Its macOS ASan/UBSan fixture compiles the actual manager initialization/crop/recognition and actual task parser/orchestration. It uses real Foundation/CoreImage/Vision request setup, with controlled request execution/observations, a controlled monotonic offset and a counted CGImage provider/capture facade. It checks manager deallocation, empty candidates, rectangle fields, 200 error/exception recoveries, output/observation caps, admission, active local/parent cancellation, invalid parameters before capture, capture failure and expiry during capture. Only the task manager allocation is substituted with an injecting subclass. The real Vision recognizer is not executed. UIKit debug drawing is source-reviewed and covered by normal iOS compilation/device acceptance, not that macOS fixture.

The new macOS fixture has **not run on this Windows host**. Required acceptance:

1. Run both workflows and build rootfull/roothide, retaining sanitizer checks. Compare normal task-27 wire fields and supported languages with the previous build.
2. Compare accurate/fast, languages, custom words, correction, orientations and ROI clipping on devices. Check source/ROI pixel boundaries, zero-size ROI, invalid geometry, empty recognition, missing candidates and output-limit errors.
3. Exercise active parent cancellation/timeout and a deliberately slow Vision/capture. Confirm no late success, timer teardown, no stuck busy state and subsequent fresh-request recovery. Measure opaque-operation overrun and SpringBoard responsiveness.
4. Request debug output on success, empty observations, failed box/context and unwritable paths. Verify balanced graphics contexts, scale-1 image dimensions, bounded rendering by source geometry, explicit errors and cleanup after exceptions.
5. Use Allocations/VM Tracker across repeated requests to confirm manager/request/source release after caller cleanup; distinguish Vision persistent caches from an adapter retain cycle. Retain a manager deliberately to verify its admission semantics.

C01c2 legacy color validation/ownership/scan budgets are now source implemented; see [IMPLEMENTATION-C01C2.md](IMPLEMENTATION-C01C2.md). Next: C01c3 remaining explicit frame-backed reuse and modern image matcher work. The whole C01 group remains open.
