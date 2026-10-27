# C02b26 — direct keepAwake enqueue adapter

Date: 2026-10-27 (Asia/Bangkok). Baseline: `b60a754`; the user reported C02b25 built successfully.
Status: **source implemented; new macOS/Foundation/ARC/sanitizer CI and device qualification pending**.
Finding: **P0-13, task-40 keep-awake adapter**. Other adapters and performance qualification remain open.

## Result and compatibility

The rootfull/roothide keepAwake bridge calls TLinkExecuteNativeKeepAwake directly. The shared TLinkSetKeepAwakeEnabled core accepts the normalized boolean and enqueues the existing UIApplication idleTimerDisabled assignment on the main queue. This removes the typed call's RAW request formatting/encoding, string parser, processTaskWithContext dispatch, compatibility CF stream and response-vector accumulation/copy. Successful replies build ok/raw/parts through the existing direct reply formatter; denial replies retain compatibility parsing.

Keep JS boolValue normalization and default false for missing arguments. The RAW task-40 body remains unchanged and is checked against frozen source. The RAW backend retains its %s string conversion, intValue != 0 interpretation, empty-string return and NSError behavior, then delegates to the shared enqueue core. JS and RAW conversions intentionally remain distinct; for example a JS boolean-like string is normalized before the old wire adapter would have seen it.

ACK still means that the property update has been enqueued, not that it has executed. The assignment remains asynchronous on the main queue, with the enabled value captured by the block. This checkpoint introduces no synchronous main-queue wait, coalescing, retry, expiry inside the accepted block or new state owner. Production TrollStore and TouchPOC execution sources are unchanged; both build workflows run the shared safety suites.

## Authority, effects and lifetime

Both enable and disable remain ordinary licensed task-40 operations. Disabling is not cleanup and does not bypass license, cancellation or deadline checks. The entry creates the existing child context with response capture disabled, inheriting caller deadline/output settings and owner fields. Check stop before one task-40 gate and again before enqueue; owner automation authorization does not bypass the gate. No C01-local timeout or compute admission is added.

Preserve post-enqueue stop/output admission. An accepted update can remain queued when the response reports cancellation, timeout or response_too_large; caller teardown does not retract it. The UI block captures only the boolean, not the task context/budget. Calls remain synchronous only through enqueue and reply formatting. Main-thread property execution is opaque to the caller and is not preempted by this change.

Each direct call drains temporary objects in an autorelease pool while retaining the result outside that pool. NS/C++ exceptions during synchronous gate/enqueue/reply work normalize to native_exception; asynchronous UIKit exceptions retain the existing behavior. No measured CPU, allocation, latency, RSS or idle-timer behavior improvement is claimed.

## Verification

All 62 workflow runners (36 source-contract, 26 native), 521 direct workflow source-grep assertions, expanded standards-conforming assert preprocessing and git diff --check pass on Windows. The assert checker retains its rejecting negative control. Sixteen artifact-only checks require CI outputs. No warning or sanitizer checks were disabled. New Foundation/ARC/ASan/UBSan fixture branches cannot execute on this Windows host.

New macOS coverage compiles the actual bridge, task entry and Scheduler parser/core against controlled main-queue and UIApplication boundaries. Independent frozen bridge/task/backend fragments provide the old adapter oracle. It compares replies and deferred boolean effects for missing, numeric, string and extra arguments at ordinary/exact/short output caps, and independently compares the RAW parser's integer interpretation.

Coverage checks one ordinary gate for both states, denied owner exemption, pre/gate cancellation and expiry, cancellation/expiry immediately after enqueue, enqueue faults before/after acceptance, caller/pool teardown, ordered alternating queued values and zero typed RAW dispatch/response-vector capacity. Pending blocks are explicitly drained at fixture boundaries. Controlled host calls do not change the host idle timer; the new Foundation fixtures await macOS CI and actual GCD/UIKit behavior requires device qualification.

## Acceptance and remaining work

Build rootfull/roothide variants and compare typed/helper keepAwake with RAW task 40 for both states and normalized arguments. Verify on device that ACK remains enqueue-only, the property changes on main, and licensing, stop/deadline/output failures preserve the documented accepted-work behavior. Measure bridge cost separately from UI scheduling. Continue other P0-13 adapters, P1-40 invalidation and P0-12 qualification/unknown-start cases; C02 remains partial.
