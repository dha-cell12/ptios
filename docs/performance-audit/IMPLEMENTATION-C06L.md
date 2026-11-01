# C06l — continuous private VPN transition budget

Date: 2026-10-31 (Asia/Bangkok). Baseline: `6b754e83`; user reported C06k build passed and requested continued implementation. This checkpoint addresses a bounded part of **P1-67** in the production TrollStore private connect/disconnect compatibility path. TouchPOC excluded.

## Transition window

The private transition previously started a wall-clock deadline after invoking connect/disconnect, slept 100 ms between probes and accepted a target status before checking expiry. Action time was outside the budget; wall-clock changes could extend or shorten the loop, interrupted sleeps could issue probes early, and a probe could produce success after the deadline.

Use the existing shared Darwin continuous clock, including device sleep, through a small portable window policy. The five-to-thirty-second transition window starts immediately before the action. Action time, sleep, snapshot work and pool cleanup consume that same window. An invalid, regressed or overflowing clock fails closed; no new action starts when its window is invalid. Normalize nonfinite timeout values safely (NaN/negative infinity to five seconds, positive infinity to thirty); fractional durations use millisecond precision.

Keep the 100 ms poll interval. Early/EINTR sleeps wait only the rest of that interval; they neither issue an early probe nor renew the transition deadline. Cap the final sleep to the remaining time. Do not perform another private status read after expiry, and check again after each probe before accepting success. A fatal sleep error uses the existing transition-timeout result. Scope temporary probe objects with an autorelease pool while retaining the latest connection/status needed for the result.

This deliberately refuses success first observed at or after expiry. Timeout metadata uses the last observed status; it does not perform an extra unbudgeted read. The system action may already have committed or may complete later. There is no rollback or automatic retry.

## Preserved scope and limits

Preserve marker ownership, private store/configuration lookup, selection, already-target success, action availability, target mapping and all reply codes/fields. The public NEVPNManager notification/timer path is unchanged. The policy and adapter are compiled only for `TLINK_VPN_TROLLSTORE_RUNTIME` in the manager.

This is a cooperative transition budget beginning after existing preflight/selection. Opaque private action/probe calls cannot be preempted; they can return after the window, at which point success is refused. Private-queue residence, preflight work, caller cancellation and result construction are not newly bounded. The queue still waits synchronously. The separate cleanup loop, its publication delay, and the fifty-attempt configuration-verification/list-enumeration loop remain unchanged. Replacing/coarsening polling, private notifications, async ownership and end-to-end qualification remain open; P1-67/C06 are partial.

## Verification

The new runner is wired into both production build workflows. Its staged reversal restores only this transition loop, adapter and two conditional includes, then verifies the complete preceding manager SHA-256. The existing public-transition baseline guard runs after that reversal, preserving its historical complete-file comparison. No frozen fixture is edited.

Portable policy cases cover 100k windows; five/thirty-second and fractional/nonfinite bounds; invalid/regressed/overflow clocks; 1–100 ms early sleep fragments; fatal waits, action/probe work, oversleep, the final partial interval and refusal to probe after expiry.

Windows validation passes all **76 workflow runners** (36 source, 40 safety), **521 existing workflow source checks**, staged complete-file hashes, JavaScript syntax, fixture extraction, expanded assert preprocessing and `git diff --check`. Sixteen artifact-only checks are skipped. The portable count and controlled timing cases are test evidence, not device measurements.

The new macOS fixture extracts the actual current transition and adapter plus the frozen previous transition. It controls the private store, clock and sleep while invoking real Objective-C action selectors. Cases compare healthy/preflight/timeout replies in both directions, multiple target times and already-target paths; verify wall jumps, action/probe overruns, late target refusal, EINTR/fatal/oversleep/clock failures, NS/C++ unwind/recovery and cross-pool result lifetime. It also compiles/samples the real shared Darwin clock. No VPN/profile/radio or installed state is changed. Foundation/ARC/ASan/UBSan execution and the iOS build require macOS CI; there is no measured device CPU, memory, wakeup or latency improvement claim.

## Runner language-standard correction — 2026-11-02

User supplied a macOS log failing while compiling vpn-private-polling-runtime-test.mm (baseline `68921397`). The runner selected C++11, but its shared TLinkHelperSocketIO.h dependency uses C++14 aggregate initialization of Result with a default member initializer. This caused the repeated no-matching-constructor diagnostics, before any private transition assertions ran.

Use C++14 for the portable core and both Objective-C++ fixtures, matching the existing StreamControl/streamd/vpnagent/privhelper targets and helper transport/client runners. Include the same socket helper header in the portable core so the dependency is parsed on every host. Keep production headers, behavior, strict warnings and sanitizers unchanged.

Focused private-polling source/reversal guards, extraction and 100k portable window cases pass on Windows, as do public-transition guards, JavaScript syntax and git diff --check. Corrected macOS/Foundation/ARC/sanitizer compilation and execution still require CI; no device or C06m acceptance is claimed.
