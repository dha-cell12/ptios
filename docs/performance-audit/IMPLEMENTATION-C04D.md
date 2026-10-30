# C04d — synchronized VPN completions and shared broker budget

Date: 2026-10-30 (Asia/Bangkok). Baseline: `dd0dae9d`, C04c build passed according to the user. Complete normalized broker source SHA-256 before this change: `dcbe39ad964877613536d525a21ea04bb704d95903a7be9487b31a00192c30f0`.
Status: **user reported build passed at `2c5eaf6c` before C04e; independent device qualification pending**.
Finding: **P0-19/P1-63 broker wait/output portion**, cooperative budget and completion ownership. Synchronous IPC and underlying operation cancellation/admission remain open.

## Change

The broker previously shared an unsynchronized __block result between callback and worker. Multiple callbacks could overwrite it, and a callback arriving after timeout could race with the waiter. The 8/24-second wait also started only after the operation starter returned, and each blocking send had a separate timeout.

Replace that result with a shared completion object containing a mutex, first-result state and one semaphore. The callback owns only this object, never the client FD, slot or stack budget. The first callback wins, including nil; duplicates and callbacks after closure are ignored. Consumption and abandonment clear the retained result under the same mutex. Sample deadline validity inside that lock when consuming, so waiting for the result lock cannot make a late result eligible. A scope guard abandons on every return or NS/C++ starter exception; a retained late callback cannot publish a result or hold a completed result indefinitely. The backend can still retain the small closed completion object until it releases its callback.

Keep the 30-second accepted-time window from C04c and extend its use through response dispatch and output. Check it before and after ordinary authority work, so a slow successful authority check cannot start manager work after the budget expires. A manager phase starts before invoking the operation starter and ends at the earlier of its existing 8/24-second limit or the outer deadline. Starter time consumes that phase. Semaphore waits use slices of at most 250 ms to recheck the continuous clock after sleep; there is no new polling thread or idle timer. A result is eligible only while that budget remains live at consumption. Preserve the existing vpn_broker_operation_timeout code and first-nil behavior.

After response dispatch, check the outer window before encoding and before writing. Use MSG_DONTWAIT sends and the existing exact-write/EINTR/EAGAIN/poll helper with that same absolute deadline. Byte progress does not renew it. Partial output can already have reached the peer at expiry; close through the existing lease without replay, a replacement timeout response or rollback of committed VPN effects. Per-call flags leave the descriptor's global blocking mode unchanged.

Keep command parsing, ordinary task authority and diagnostics exemption, response fields/encoding, manager API arguments (including its existing 20-second transition argument), profile scope, license implementation, listener and eight-slot ownership. Rootfull/roothide port 6014 is covered. Production TrollStore foreground/agent listeners are separate and unchanged; TouchPOC is excluded.

## Verification

The existing broker runner reverses only this stage's wait, expiry gates, function arguments and output driver, comparing the complete source with a frozen C04c SHA-256 baseline. Both earlier full-source guard layers remain. It compiles both portable ingress and budget suites on every host.

The new budget core covers 100,000 outer/8-second/24-second plans, starter-time consumption, invalid/edge clocks and limits, exact partial output, send/poll EINTR/EAGAIN, fatal/zero writes, empty output, backpressure and progress that expires without renewal. These checks pass on Windows.

The actual handler fixture retains frozen parser/admission/exception/FD-reuse/ingress tests. It adds a response that overruns the budget and produces zero sends, and a real small-buffer socket with a non-reading peer: actual nonblocking send reaches backpressure, the controlled wait expires the outer clock, and the lease drains without waiting for the peer. Admission stress clocks remain fixed against CI scheduling load.

A separate Foundation fixture compiles actual wait/response code and the frozen healthy response path with controlled manager, authority and clock. It covers inline and other-thread callbacks, first/nil/duplicate/late results, phase/outer/startup expiry, NS/C++ abandonment, result ownership across pools, 1,000 callback/abandon races, eight competing publishers with one signal, consumption-time rejection, frozen healthy/error/diagnostics replies, ordinary authority and slow-authority no-manager behavior. No real manager, profile, VPN or license state is changed. New Foundation/ARC/sanitizer cases require macOS CI and were not run on Windows.

Windows verification passed: all 67 workflow runners (36 source checks, 31 safety runners), 521 existing workflow source checks, final focused broker/core/source guards, expanded assert preprocessing and `git diff --check`. Sixteen artifact-only checks are skipped. No device latency, throughput, memory or power result is claimed.

## Remaining work

This is a cooperative deadline, not preemption of arbitrary synchronous APIs. License checks, operation starters, diagnostics or encoding can overrun while holding control; the next check rejects late work/results. Once manager work has begun, timeout does not cancel it or roll back effects, and its completion may arrive after the client closes. Pending manager callbacks/operations are not bounded by the eight client slots over time. The outer SpringBoard/daemon IPC timeout and blocking behavior are unchanged. Operation admission/coalescing/cancellation, disconnect propagation, IPC isolation, actual device/sleep qualification and TrollStore listeners remain open. P0-19/C04 are not fully closed.
