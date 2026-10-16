# A04 — P0-15 / P0-16 / P1-52

Date: 2026-10-16. Base: `b005a38` (A03 build reported passed by the user).
Status: source implemented; portable native tests and source-contract checks passed. User reported the A04 build passed before A05. macOS test logs were not independently inspected; device qualification remains pending.

## Timer ownership and acknowledgment (P0-15)

Rootfull/roothide `pccontrol/Scheduler.xm` uses one serial background dispatch queue for registry mutation, source creation/cancellation, callbacks and synchronous launch preparation. Calls already on that owner execute inline; other callers dispatch synchronously. Set returns success after installation and resume. Remove returns after cancellation/removal and any preceding callback has completed its launch attempt.

`shared/TLinkSchedulerState.h` holds the actual generation registry used by production. Replacement cancels the previous source before installing the new entry. A monotonically increasing token is never reused after removal; a delayed callback must match both name and current token. Generation exhaustion fails instead of wrapping. Source creation failure leaves an existing schedule intact. Each dispatch handler captures only name/token, so the registry's source/script ownership does not create a retain cycle.

One-shots remove/cancel their entry before admission, keeping a local owning handle through the callback. They remain consumed when busy, license-denied or launch-failed, matching the previous one-attempt behavior. A stale one-shot cannot remove a replacement. Remove is idempotent. Timers remain in-memory; no persistence/respring behavior is added.

Removal prevents later launch admission by that generation. It does not stop a script already admitted by an earlier callback, including its asynchronously scheduled worker.

## Interval and admission policy (P0-16)

- Repeating script timers now require **at least 1 second**. Reject smaller values with a protocol error instead of silently clamping them. This is a product policy for coarse script schedules; it is not an iOS timer-resolution claim or a measured optimal interval.
- One-shot timers retain positive subsecond delays. Both modes require finite numeric input, at least one representable nanosecond and a delay fitting the signed dispatch-time offset. Reject malformed numeric suffixes, NaN/infinity and overflow before conversion/allocation.
- Dispatch-source leeway is 10% of the interval, capped at 100 ms. One handler invocation makes at most one attempt; missed ticks are not replayed in a loop.
- A cheap player-state snapshot rejects busy/unavailable players before the scheduler license gate or `playScript` config/logging work. Recheck after the license gate because another ingress may have started a script meanwhile. Every actual scheduler launch attempt still passes the existing license gate and the player's own check.
- The running flag is atomic and the new admission snapshot reads the player state under its existing lock. Other ScriptPlayer lifecycle fields and the full cross-ingress start/stop state machine are not solved by this snapshot. In particular, A05's RAW premature-idle/worker-cleanup issue remains open.

Timer callbacks and launch preparation no longer execute on the main run loop. Synchronous set/remove callers can still wait for an in-progress owner operation (including license/config/history work). Do not introduce a synchronous main-thread dependency from that owner while main may be waiting for it. License fast-path work remains B05.

## Auto-launch transactions (P1-52)

`shared/TLinkAutoLaunchConfig.h` is the common writer for:

1. rootfull/roothide Task 36 in `pccontrol/Scheduler.xm`;
2. production TrollStore Task 36 in `stream-app/streamd/POCSocketServer.mm`;
3. the StreamControl Boot Script settings screen.

Each update opens the stable sibling `autolaunch.plist.lock` and holds an exclusive flock across read, parse, one-key mutation, serialization and atomic replacement. Independent descriptors serialize same-process threads and cooperating processes. RAII releases the lock on every result; the descriptor is close-on-exec and the lock file is never removed after use. A read-only lock descriptor allows an existing readable lock file to be shared across writer identities without modifying its contents.

Only a genuinely absent plist starts an empty map. Read errors, malformed/non-dictionary data, lock failure and save failure return failure; no successful acknowledgment is emitted. Preserve the flat name-to-entry schema and unrelated entries/fields. No cache or top-level revision key is introduced, so existing readers continue reading complete atomic snapshots. Existing readers can observe either the previous or next snapshot without participating in the writer lock.

All cooperating writers must be upgraded together. Advisory locks cannot protect against older binaries or external writers that ignore them. Boot Script's other config/marker files retain their existing separate commit behavior; this is not a multi-file durability transaction. Prototype TouchPOC remains untouched. TrollStore's separate timer implementation is outside the P0-15/P0-16 rootfull fix; only its shared auto-launch persistence changes here.

## Verification completed on Windows

`node scripts/check-scheduler-safety.mjs` compiles the actual portable production registry/policy with C++14, MSVC `/W4 /WX`:

- repeat intervals 1/10/100 ms rejected, 1 second accepted; subsecond one-shots accepted; malformed range/nonfinite/overflow cases rejected; leeway checked;
- set/replace/remove/restart, non-reused tokens, stale callbacks, idempotent cancellation and one-shot cleanup;
- busy skips the launch callback entirely; a callback replacing its own one-shot cannot have that replacement removed by old cleanup;
- 8 concurrent test clients x 10,000 cycles, serialized by a test owner mutex matching the production queue contract; zero post-remove/stale admissions and zero live test timer resources.

Source assertions check queue ownership, source target queue, synchronous ACK/error delivery, busy-before-license-before-play ordering, atomic player snapshot and adoption of the shared lock helper by all production writers. These checks do not execute Objective-C or Darwin flock.

All 36 existing source-contract checks collected from the rootfull/roothide and StreamControl workflows pass. A01 native injection tests pass again for both production implementations (100k frames each), A02 passes 10k indicator lifecycles, and A03 passes 22 success/fault paths plus 20k capture frames. `git diff --check` passes.

## Added macOS CI tests — not run on this Windows host

The same runner, included in both build workflows, also compiles/runs these with Foundation and ASan/UBSan on macOS:

- `test/scheduler-runtime-test.mm`: extracts the real production dispatch/ARC adapter, uses fake script/license hooks, stresses 8,000 concurrent set/remove cycles, real one-shot/repeating delivery, busy/denied admission and remove waiting for an already-admitted launch attempt.
- `test/autolaunch-transaction-test.mm`: uses the actual shared Foundation/flock writer from 8 processes and 8 threads, checks all 1,600 acknowledged distinct-name updates plus a legacy entry survive, and checks malformed/lock/write failures and recovery.

Their runtime results are pending; portable tests cannot establish real dispatch-source/ARC or cross-process filesystem behavior.

## Remaining build/device checks

1. User reported the A04 build passed before A05. The report does not identify every matrix artifact or include host-test logs; inspect the relevant rootfull/roothide/StreamControl CI jobs before release.
2. Run S007 Probe A from 8 device clients: set/remove, replacement, restart and removal during fire. After ACK, no new launch may be admitted by the removed generation; only one current timer per name remains.
3. Run S007 Probe B: reject repeating 1/10/100 ms; verify 1-second repeat and subsecond one-shot. With a long-running script, verify timer fires do not increment scheduler license checks or cause config reads/play calls. Measure CPU, wakeups, main-thread stalls and timer latency; no quantitative improvement is claimed before measurement.
4. Exercise RAW and JS, successful/failed/license-denied starts, stop/start overlaps and script-originated timer operations. A05 still owns complete RAW stopping/session isolation.
5. Run concurrent auto-launch updates through tweak/streamd/UI where deployment overlaps. Check acknowledged keys survive, errors reach callers, lock/plist access works for installed process identities and malformed config is preserved. Verify boot startup/list output and existing Boot Script enable/disable flows.

Next planned group: A05 (P0-03/P1-02), RAW worker lifecycle and repeat-run-loop removal.
