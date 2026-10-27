# C02b28 — direct frontMostPid query

Date: 2026-10-27 (Asia/Bangkok). Baseline: `e5a4acb`; the user reported C02b27 built successfully.
Status: **build reported passed by the user before C02b29 (`b2ac272`); independent device/performance qualification pending**.
Finding: **P0-13, task-51 foreground PID adapter**. Other adapters and performance qualification remain open.

## Result and compatibility

The rootfull/roothide frontMostPid bridge calls TLinkExecuteNativeFrontmostPid directly. Process exposes frontMostPidValue without RAW parameters; the old wrapper delegates to it. The foreground bundle lookup, zx_pidForBundleId lookup and signed decimal formatting are unchanged. This removes the typed call's two-character RAW request formatting/encoding, processTaskWithContext dispatch, compatibility CF stream and response-vector accumulation/copy.

Keep ignored JS arguments, ok/raw/parts, numeric pid metadata and the task handler's nil-to-0 fallback. The entry reuses the existing scalar query formatter, building ordinary successful fields without splitting/reparsing the response. Its uncommon-string compatibility behavior remains shared with frontmost/path queries. No PID cache, task classification change or new process lookup policy is introduced.

The RAW task-51 body is unchanged and checked against frozen source. The old Process wrapper still ignores eventData and leaves the NSError out-parameter unchanged; it now explicitly consumes both unused parameters before delegation. The frozen backend oracle stays intact; only its generated temporary include adds (void)error so the strict fixture compiler can accept the historical unused parameter. Production TrollStore and TouchPOC execution sources are unchanged; both build workflows run the shared safety suites.

## Authority and lifetime

The entry creates the existing child context with response capture disabled, retaining owner fields, caller deadline and output settings. Check stop before one ordinary task-51 license gate, after the gate, after the complete Process query and after formatting/output admission. Owner automation authorization does not bypass that gate. No C01-local timeout or compute admission is added.

Execution remains synchronous and cooperative on the caller's existing path. Foreground main-queue access and PID lookup remain opaque; this change does not preempt them or introduce a stop check between those two backend operations. Cancellation/expiry is observed after the backend returns. NS/C++ exceptions normalize to native_exception.

A per-query autorelease pool drains temporaries while a strong result outside the pool retains returned metadata. The signed PID is rendered using the same backend string and Foundation intValue conversion as the old bridge. Compatibility raw strings and formatter temporaries remain. No measured CPU, allocation, latency or RSS improvement is claimed.

## Verification

All 62 workflow runners (36 source-contract, 26 native), 521 direct workflow source-grep assertions, expanded standards-conforming assert preprocessing and git diff --check pass on Windows. The assert checker retains its rejecting negative control. Sixteen artifact-only checks require CI outputs. No warning or sanitizer checks were disabled. New Foundation/ARC/ASan/UBSan fixture branches cannot execute on this Windows host.

New macOS coverage compiles the actual Process wrapper/core, bridge, task entry and existing scalar formatter against controlled foreground/PID lookup boundaries. Frozen bridge/task/backend fragments provide the old adapter oracle. It adds 160 ordinary PID comparisons, signed/zero/INT_MIN/INT_MAX cases at exact and short output caps, ignored JS arguments, unchanged RAW NSError sentinel/input behavior, one task-51 gate and zero typed RAW dispatch/response-vector capacity.

Coverage also checks denied owner exemption, pre/gate cancellation and expiry, cancellation/expiry at the PID read, NS/C++ faults at either foreground/PID boundary, foreground identifier pass-through and reply lifetime after caller/pool teardown. Actual main contention, SpringBoard/PID discovery and device/performance acceptance require qualification.

## Acceptance and remaining work

The user reported this checkpoint built successfully before C02b29. That report does not establish device or measured performance acceptance. The next checkpoint is documented in IMPLEMENTATION-C02B29.md.

Build rootfull/roothide variants and compare typed/helper frontMostPid with RAW task 51 across SpringBoard, foreground apps, missing processes and app transitions. Verify license denial/revocation, caller stop/deadline and exact output caps. Measure bridge cost separately from unchanged main/PID lookup work. Continue other P0-13 adapters, P1-40 invalidation and P0-12 qualification/unknown-start cases; C02 remains partial.
