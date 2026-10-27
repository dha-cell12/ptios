# C02b27 — direct touchIndicator action adapter

Date: 2026-10-27 (Asia/Bangkok). Baseline: `acc8648`; the user reported the corrected C02b26 built successfully.
Status: **source implemented; new macOS/Foundation/ARC/sanitizer CI and device qualification pending**.
Finding: **P0-13, task-26 indicator adapter**. Other adapters and performance qualification remain open.

## Result and compatibility

The rootfull/roothide touchIndicator bridge calls TLinkExecuteNativeIndicator with the normalized numeric action. The shared handleTouchIndicatorAction core selects stop, start or reload without a request string. This removes the typed call's RAW request formatting/encoding, parser, processTaskWithContext dispatch, compatibility CF stream and response-vector accumulation/copy. Successful replies use the existing direct reply formatter; backend errors and denials retain compatibility parsing.

Keep JS intValue normalization, negative/missing-argument validation, ignored extra arguments, unknown positive-action errors and ok/raw/parts. JS values such as a leading-zero string are normalized before numeric dispatch, just as the previous bridge normalized them before formatting its RAW request. The direct entry rejects negative actions before authority/backend work.

The RAW task-26 body remains unchanged and is checked against frozen source. The RAW parser still trims whitespace/newlines and accepts only exact 0, 1 or 2 strings. Empty/nil, 01, +1, 1.0, extra fields and other strings remain invalid rather than being accepted through intValue. It maps an invalid string to an internal sentinel for the existing unknown-action error.

Start/stop public wrappers, synchronous main ownership, reload's running-state check, color loading, HID lifecycle/generation fencing and window updates retain their existing implementation. Only the action selection is shared. No new queue, cache, asynchronous ACK, lifetime state or synchronization policy is added. Production TrollStore and TouchPOC execution sources are unchanged; both build workflows run the shared safety suites.

## Authority, effects and lifetime

All valid normalized actions, including stop and unknown positive actions, pass one ordinary task-26 license gate. Stop is not an exempt cleanup operation. Owner automation authorization does not bypass the gate. The entry inherits the existing child context, owner fields, caller deadline and output settings with response capture disabled. Check stop before and after the gate, then after backend work through reply admission. No C01-local timeout or compute admission is added.

The backend still waits synchronously for its main owner. It does not gain timeout-aware queue acquisition or preemption: cancellation/expiry after admission can coexist with an already committed state/color change, and a short output cap can reject the reply after that effect. The shared core preserves those legacy semantics. No automatic retry or compensating start/stop is introduced.

Each typed call drains temporary objects in an autorelease pool while a strong result outside the pool retains reply fields. NS/C++ synchronous exceptions normalize to native_exception. The public lifecycle wrappers continue transferring an owned NSError result through the synchronous main boundary before writing the caller's out-parameter. No measured CPU, allocation, latency, RSS or device behavior improvement is claimed.

## Verification

All 62 workflow runners (36 source-contract, 26 native), 521 direct workflow source-grep assertions, expanded standards-conforming assert preprocessing and git diff --check pass on Windows. The assert checker retains its rejecting negative control. Sixteen artifact-only checks require CI outputs. No warning or sanitizer checks were disabled. New Foundation/ARC/ASan/UBSan fixture branches cannot execute on this Windows host.

New macOS coverage compiles the actual bridge, task entry, strict RAW parser, public start/stop wrappers and reload branch against controlled synchronous-main, UI, configuration and lifecycle boundaries. Frozen bridge/task/parser fragments provide the old adapter oracle. It compares replies, state, color values and boundary-call counts across missing/negative/numeric/string/extra arguments, running/stopped state and ordinary/exact/short output caps, including duplicate start and configuration/start errors.

Additional coverage checks strict RAW strings/nil input, one ordinary gate for stop/start/reload, denied owner exemption, pre/gate cancellation/expiry, effects after main admission, NS/C++ faults before/after the operation, pool/error lifetime, invalid direct input and zero typed RAW dispatch/response-vector capacity. Existing portable HID ownership tests remain in the shared workflow. The new fixture controls its main/UI/HID boundaries; real main contention, private HID, window rendering and device behavior require qualification.

## Acceptance and remaining work

Build rootfull/roothide variants and compare typed/helper touchIndicator with RAW task 26 for stop/start/reload, duplicate start, invalid actions, missing/bad color configuration and exact error replies. On device verify the main-owned lifecycle and callbacks under repeated calls, license denial/revocation, caller stop/deadline and output rejection. Measure bridge cost separately from main-queue/config/HID work. Continue other P0-13 adapters, P1-40 invalidation and P0-12 qualification/unknown-start cases; C02 remains partial.
