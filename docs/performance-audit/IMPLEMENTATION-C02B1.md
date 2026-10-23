# C02b1 — structured tap/swipe/longPress request entry

Date: 2026-10-24 (Asia/Bangkok). Baseline: `72fef91`; the user reported the C02a build passed before this slice.
Status: **source implemented; macOS/iOS CI and device qualification pending**.
Finding: **P0-13, tap/swipe/longPress portion**. C02 remains open for other typed methods and helper transport/config/dedupe.

## Result and scope

The root in-process JS bridge now submits numeric `TLinkNativeTouchRequest` values for `tap`, `swipe` and `longPress` to `TLinkExecuteNativeTouch`. It avoids the full legacy request NSString/UTF-8 payload, compatibility CFWriteStream, task-ID/string parser, response sink/vector and success-response split for those three methods. The returned dictionary keeps `ok`, `raw` and `parts`; success remains `{ok:true, raw:"0\r\n", parts:["0"]}`.

Legacy task 62/63 adapters and the typed entry share the same tap/swipe executors, including C02a's integer-pixel injection, absolute timeline and finally-owned UP. External/RAW/batch input and reply formats remain available. JS gesture/zoom/batch and other methods still use their existing raw dispatch. Production TrollStore and excluded TouchPOC are unchanged.

## Authorization, context and completion

The new entry only maps Tap to task 62 and Swipe to task 63. Unknown kinds fail before dispatch. It creates a bounded call context with the existing helper, preserving the owner tuple and cancellation token and capping the deadline/output size just as the former nested raw dispatch did. The call is synchronous on the existing caller thread; no new queue, reconnect, retry or detached side effect is introduced.

The entry checks cancellation/deadline, calls the existing `TLinkRootfullLicenseTaskAllowed` for the mapped task, then checks cancellation/deadline again before execution. It grants no RAW-session automation exemption for these tasks. Cancellation during a blocking license refresh cannot lead to DOWN after that refresh returns. An opaque license operation itself is still cooperative, not preempted.

Executor argument validation, geometry, frame ordering and finally-owned UP are shared with the wire path. The boundary converts Objective-C/C++ exceptions to `native_exception` after unwinding the executor. The context scope restores the previous native budget on all exits. Existing injector-failure reporting and HID thread ownership are not redesigned.

The reply checks UTF-8 byte length against the call output budget and rechecks the stop reason. It does not capture response bytes in a vector. Denial/argument-error strings retain the legacy raw/parts shape; only those error strings need splitting. As before, output-cap failure can be discovered after a gesture's side effects; a tiny cap is not a promise to reject the gesture before DOWN. Bounded stop/exception error dictionaries remain control results outside the old wire-sink cap.

## Numeric compatibility

The old JS bridge formatted coordinates with `%.2f` and task 62/63 parsed them with `floatValue`; durations were clamped to `0..60000`, formatted with `%.0f`, then parsed as integers. Removing those conversions without characterization would shift some coordinates and half-integer durations.

This slice retains scalar decimal compatibility using fixed stack buffers (384 bytes for any finite double coordinate, 16 for a clamped duration), libc formatting and float conversion. Darwin/Windows use one immutable C numeric locale cached for process lifetime, without changing thread/process locale. There is no per-request locale creation or NSString scalar allocation. This deliberately retains scalar formatting/parsing work; the improvement is removal of the aggregate legacy request/response transport machinery, not a claim that every numeric conversion/allocation is gone.

The numeric request has default duration 50 ms, finger 0 and default swipe steps derived from duration with the existing 2..120 clamp. Direct internal callers receive numeric executor validation. The JS compatibility helpers preserve finite-input checks, signed zero, float overflow behavior, duration clamping and decimal rounding. Nonfinite converted coordinates are rejected by the shared executor before injection.

## Validation

- Windows: all **36 source-contract runners, 20 native runners and 528 TrollStore workflow source grep assertions pass**. The first full run and a Frame Vision rerun hit Windows EPERM only while removing an already-passed executable; that runner now uses bounded cleanup retry and passes. Production Frame Vision behavior is unchanged.
- Portable tests cover task 62/63 mapping/unknown-kind rejection, defaults, 100k old decimal-to-float comparisons, signed zero/extreme finite coordinates, nonfinite input, truncated scalar formatting and clamped half-integer duration rounding. Existing gesture timing, cancellation, touch ownership and raw/HID parity tests remain.
- Both workflows' existing native-budget runner extracts the actual new bridge branches and task entry. Cross-platform assertions prohibit raw dispatch/CF stream creation in the typed branch and check license/pre/post-stop wiring. The new shared header is compiled by the portable test on every host.
- The macOS fixture compares 160 actual typed-bridge cases against the old NSString encoder plus actual RAW adapters/executors, checking reply, HID points and controlled timestamps. It also checks task 62/63 license gates, denial, cancellation inside authorization, pre-expiry, native wait expiry, cancellation after DOWN, argument/kind rejection, 3/2-byte output boundaries, Objective-C/C++ exception cleanup, restored scopes and no raw-dispatch calls or response-buffer allocation.
- Strict warnings and existing ASan/UBSan flags are retained. **The new Foundation/macOS branch and iOS builds were not run on this Windows host.** Exact Darwin NSString/libc parity, helper-driven call behavior, actual license/HID integration and device latency/allocations remain qualification work.

## Acceptance and next slice

Build rootfull/roothide and exercise JS tap/swipe/longPress with observe/enforced licensing, revoked/expired/offline snapshots, stop during authorization/wait/DOWN, native exceptions and limited output caps. Compare coordinates around decimal/fixed-point boundaries, signed zero, extreme finite values and duration half-ties. Record allocations, native-call latency, endpoint timing and stop-to-UP against C02a. A successful build does not establish a measured performance win.

After this checkpoint, continue structured gesture/zoom/batch or other measured hot methods while preserving their preflight, diagnostics, ordering and rollback contracts. P0-12 event-driven helper RPC, P1-40 configuration snapshot and P1-41 byte-bounded replay/dedupe remain separate work. C01 device acceptance also remains open.
