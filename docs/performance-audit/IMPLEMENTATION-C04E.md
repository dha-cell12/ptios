# C04e — pending VPN manager operation admission

Date: 2026-10-30 (Asia/Bangkok). Baseline: `2c5eaf6c`, C04d build passed according to the user. Complete normalized broker source SHA-256 before this change: `5ce3789f5c46e1d941b4874269254b382103030bc1dca07b7c89388ed5b75f33`.
Status: **source/core implemented; new Foundation/GCD/ARC/ASan/UBSan runtime pending macOS CI; independent device qualification pending**.
Finding: **P1-63 pending manager submissions**, distinct from C04b's eight client leases. P0-19 IPC isolation and operation cancellation/coalescing remain open.

## Change

A timed-out client can release its client lease while its asynchronous VPN manager operation remains pending. Repeated timeouts could therefore submit more manager work despite the client cap. Add one process-local owner with eight tickets shared by query, connect, disconnect and diagnostics manager-status submissions. There is no admission wait queue. Ordinary authority still runs before admission; diagnostics remains exempt.

When all eight tickets are pending, do not call the manager. Query/control return `-1;;vpn_broker_busy\r\n` through their existing error formatting. Diagnostics still returns its static fields through the existing failed-status path, with `manager_status.available=0` and `manager_status.last_error=vpn_broker_busy`. This differs from the client cap: a ninth client is closed without a reply; an admitted client encountering operation saturation can receive the busy response.

A ticket retires only after the starter has exited and the first terminal callback has arrived. Inline callbacks cannot release capacity while their starter is still executing. Timeout, client closure and result abandonment do not prove manager completion and do not retire started tickets. A late terminal callback releases capacity while C04d's closed completion object ignores its result. Duplicate callbacks and old tickets cannot release a replacement slot: each admission uses a non-wrapping uint64 identity. Identity exhaustion fails closed.

Allocate the ticket before publishing its slot/counters. Before start, RAII cancellation releases an unused admission on expiry, allocation failure or unwind. After start, the scope guard marks starter exit on normal return or NS/C++ unwind, but still requires callback evidence. A throwing starter that has not reported completion, or a backend that drops/never invokes its callback, conservatively keeps its slot occupied. At eight such operations the broker stays busy until terminal callbacks arrive or the broker process restarts. There is no automatic time-based release/reset. This avoids admitting replacement work on an uncertain completion; it can require a process restart to restore availability when callbacks are permanently lost.

Preserve request parsing, profile scope, manager arguments, license policy, deadline and result/output handling, encoding, listener and client leases. This change neither cancels nor rolls back VPN effects. Rootfull/roothide port 6014 is covered. Production TrollStore foreground/agent listeners are separate and unchanged; TouchPOC is excluded.

## Verification

The existing admission runner reverses only this stage's include, owner and wait additions to compare the complete broker against the frozen C04d source/hash. Earlier C04b/c/d guard layers remain. Runtime extraction uses the actual current handler/wait code, not reconstructed historical code. The runner now compiles three portable suites: ingress, budget and operation admission. Both CI workflows continue to use the existing runner.

The operation core passes capacity/ninth rejection across timeout, inline completion held until starter exit, late recovery, stale/duplicate events after reuse, 100,000 sequential lifecycles, dropped-callback and throwing-starter pinning, identity exhaustion, owner/ticket lifetime, 80,000 concurrent admissions and 1,000 callback/return races. Final active counts are zero in completed-work cases; deliberately uncertain cases retain their expected charges.

The actual wait/response Foundation fixture adds eight pending calls across client timeouts, immediate ninth rejection without manager invocation, license-denial precedence, exempt diagnostics busy status, late callback recovery, stale callback fencing, pre-start expiry release, inline starter ownership and permanently dropped callback saturation. Existing first/nil/late/async/race/pool/healthy frozen response tests remain. Manager, authority and time are controlled; no real VPN/profile/license state is changed. These new Foundation/GCD/ARC/sanitizer cases require macOS CI and were not run on Windows.

Windows verification passed: all 67 workflow runners (36 source checks, 31 safety runners), 521 existing workflow source checks, final focused broker/three-core/source guards, expanded assert preprocessing and `git diff --check`. Sixteen artifact-only checks are skipped. No device latency, throughput, memory or power result is claimed.

## Remaining work

The cap counts logical pending submissions through this broker. Backend-internal subtasks, other processes and direct UI manager calls are outside it. References retained by a backend after a terminal callback are not bounded by ticket retirement. Restart resets the process-local accounting without proving old system work ended. Synchronous APIs can still overrun cooperative deadlines; no preemption, manager cancellation, coalescing, disconnect propagation or outer SpringBoard/daemon IPC isolation is added. The existing IPC/socket timeout mismatch, production TrollStore listeners and real device/sleep/backend qualification remain open. C04/P1-63/P0-19 are not fully closed.
