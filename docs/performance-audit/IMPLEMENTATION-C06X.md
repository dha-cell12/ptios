# C06x — supervisor watcher interruption and continuous throttle

Date: 2026-11-04 (Asia/Bangkok). Baseline: `9b75426d`; user reported the build passed after C06w and the IKEv2 fixture macro correction, then requested continued implementation. Production StreamControl only; TouchPOC excluded.

## Child exit observation

The long-lived direct `streamd` watcher already waits on a concurrent queue and returns its result to the supervisor owner queue. It previously called `waitpid` once. An EINTR return could be reported as a child exit/failure while the child was still alive.

Retry the same exact PID with flags zero only when the call returns a negative result and errno is EINTR. A reaped child or other terminal error is delivered once through the original owner-queue completion. Keep this blocking wait on the background queue for the actual service lifetime; it is separate from the short-lived helper's bounded owner/reaper. No new timer, polling loop, thread or process signal is added.

## Respawn throttle

Record continuous milliseconds at the same pre-spawn point that previously allocated an NSDate. Calculate the remaining portion of the existing three-second throttle with checked unsigned elapsed time. Clamp the result to zero through three seconds. An invalid or regressed clock retains one full three-second delay instead of bypassing protection or producing an arbitrarily large wall-clock delay.

Keep the throttle constant, PID stale-exit guard, running/PID state updates, exit/signal/failure logs, disabled-respawn behavior, scheduled queue and final autoRespawn/running checks. The formatted delay log and dispatch API retain seconds/nanoseconds at their boundaries; all duration decisions use continuous time. Ordinary clock behavior preserves preceding output within millisecond sampling precision. Changing wall time intentionally stops affecting the delay.

This does not add lifecycle-generation fencing, cancel an already scheduled respawn, change PID identity semantics, bound the full ensure/restart operation or add active helper cancellation/coalescing. Existing delayed callbacks still check autoRespawn/running. Long-lived watcher admission, non-EINTR errors and device/process-boundary qualification remain under the preceding policy. C06/P0-23 stay partial.

## Verification

Freeze the complete previous supervisor. A restoration removes the include/scalar timestamp change and restores the watcher wait/exit blocks, verifies the exact preceding file/hash and feeds C06u/C06t/C06e/C06c guards. An exact exit-method comparison isolates only the duration calculation. The existing full supervisor helper fixture imports the new policy header.

The portable runner compiles the actual production wait block with a controlled waitpid provider. It executes 100k interrupted/reaped lifecycles and terminal ECHILD/EIO, requiring exact-PID/flags-zero calls and no retries for terminal errors. The actual throttle policy executes 600k age/boundary cases plus invalid, regressed and near-overflow clocks.

The native ARC/ASan/UBSan fixture compiles complete current/frozen exit methods with controlled clocks, timer delivery and spawn effects. It compares status/log/event/respawn gates for ordinary elapsed time, checks forward/backward wall jumps and invalid-clock delay bounds, and preserves disabled/running suppression at delivery. Thirty-two real disposable children exit with code seven and are reaped through the extracted production wait block after injected EINTR, then must report ECHILD on a further probe. No real daemon, privileged helper or service is controlled; interruption injection does not qualify real device signal delivery.

Windows validation: all **83 workflow runners** (36 source, 47 safety), **521 existing workflow source checks**, full preceding-supervisor/earlier checkpoint hashes, exact exit-effect reversal, actual wait-block compilation, fixture extraction, JavaScript syntax, expanded assert preprocessing and `git diff --check` pass. Sixteen artifact-only checks skipped. The first focused portable compile found a missing initializer-list header in the new test; the explicit include is present and the focused/full runs pass. New Apple compilation/native execution/iOS builds require macOS CI. No device latency/performance gain is claimed.
