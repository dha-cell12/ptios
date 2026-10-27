# C02b30 — direct appState query and shared app ingress

Date: 2026-10-27 (Asia/Bangkok). Baseline: `dfde59c`; the user reported C02b29 built successfully.
Status: **build reported passed by the user before C02b31 (`aca0719`); independent device/performance qualification pending**.
Finding: **P0-13, task-32 application-state adapter**. Other adapters and performance qualification remain open.

## Result and compatibility

The rootfull/roothide appState bridge calls TLinkExecuteNativeAppState after the existing bundle-ID validation. Process exposes appStateForBundleIdentifier; the RAW parser delegates to it. Keep application lookup and selector precedence: processState wins whenever available, otherwise isRunning maps to 1/0, missing app returns 0 and an app with neither selector returns -1. The signed NSInteger formatting is unchanged.

appState and appPid now share one typed ingress/authority entry, restricted to task IDs 32 and 50. Preserve C02b29's prefix-inclusive UTF-16/UTF-8 limits, encoding/NUL/protocol rejection, immutable input snapshot, ASCII direct input and non-ASCII %s compatibility conversion. The ordinary gate receives the selected task ID exactly once. Other app methods retain their RAW adapter.

The typed appState path removes full RAW request formatting/encoding, processTaskWithContext dispatch, compatibility CF stream and response-vector accumulation/copy. Successful replies use the existing scalar formatter, with an opt-in running field built in the same result dictionary. Its default remains off for PID/frontmost/path callers. state remains the old Foundation intValue conversion of the response field, and running means that converted int is positive; it is not computed from the original NSInteger or a separate isRunning lookup. This preserves wide-state and overflow behavior.

Keep ok/raw/parts/state/running, ignored extra JS arguments, validation errors, missing-identifier errors and RAW task-32 behavior. The RAW handler is unchanged and checked against frozen source. appInfo's existing RAW state call still uses the same parser/core behavior. Production TrollStore and TouchPOC execution sources are unchanged; both build workflows run the shared safety suites.

## Authority and lifetime

Both query wrappers use the shared ordinary child context with response capture disabled and inherited owner fields, caller deadline and output settings. Invalid task IDs/ingress do not reach authority or application lookup. Check stop before one selected license gate, after it, after the complete Process operation and after formatting/output admission. Owner automation authorization does not bypass the gate. No C01-local timeout or compute admission is added.

Application discovery and selector execution remain synchronous, cooperative and opaque. Cancellation/expiry can be observed after lookup/selector completion; this checkpoint adds no preemption or intermediate backend cancellation. NS/C++ exceptions normalize to native_exception. Per-query autorelease pools retain the final result outside the pool; input snapshots and error writeback retain the existing lifetime contract. No measured CPU, allocation, latency or RSS improvement is claimed.

## Verification

All 62 workflow runners (36 source-contract, 26 native), 521 direct workflow source-grep assertions, expanded standards-conforming assert preprocessing and git diff --check pass on Windows on the final source. The assert checker retains its rejecting negative control. Sixteen artifact-only checks require CI outputs. No warning or sanitizer checks were disabled. New Foundation/ARC/ASan/UBSan branches cannot execute on this Windows host.

New macOS coverage compiles the actual Process parser/core and performs its objc_msgSend calls against controlled Foundation application objects. It checks real selector dispatch/precedence, both selectors, processState-only, isRunning-only, neither selector and missing app. Frozen task/core fragments plus the existing frozen app bridge provide the old adapter oracle. Coverage compares complete replies, normalized identifiers, gate/read/method counts and selector-query order.

Cases include 160 ordinary states, NSInteger/int boundaries and both isRunning values, exact/short output caps, exact/over-limit Unicode ingress, NUL/encoding/argument rejection, authority, caller/gate/lookup/selector cancellation/deadline, NS/C++ lookup/selector faults, RAW errors, input snapshots and NSError/reply pool lifetime. Existing appPid, frontmost and path fixtures cover the shared-entry/formatter changes. Fixture extraction also checks dependency order on every host. SpringBoard discovery, actual selector capabilities and device/performance acceptance remain pending.

## Acceptance and remaining work

The user reported this checkpoint built successfully before C02b31. That report does not establish device or measured performance acceptance. The next checkpoint is documented in IMPLEMENTATION-C02B31.md.

Build rootfull/roothide variants and compare typed/helper appState with RAW task 32 for running/stopped/missing applications and supported selector combinations. Verify exact state/running fields, license denial/revocation, caller stop/deadline and input/output limits. Recheck appPid and frontmost/path replies after the shared refactor. Measure bridge overhead separately from application/selector work. Continue other P0-13 adapters, P1-40 invalidation and P0-12 qualification/unknown-start cases; C02 remains partial.
