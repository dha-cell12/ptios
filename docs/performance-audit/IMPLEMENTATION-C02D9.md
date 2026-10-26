# C02d9 — bounded status reconnection for a pinned helper session

Date: 2026-10-26 (Asia/Bangkok). Baseline: `b206649`; the user reported C02d8 built successfully.
Status: **user reported build `c96f525` passed before C02d10; independent device/performance qualification remains pending**.
Finding: **P0-12 status transport recovery without repeating native effects**.

## Behavior

The rootfull/roothide helper runtime previously terminated on the first failed status read, even though wait failures and lost native-response acknowledgements already reconciled through fresh status. It now reconnects for a small, explicit set of local status transport failures: io_timeout, empty_frame, connect_failed, read_failed and write_failed.

One reconciliation episode allows at most three status attempts, including the first, in a non-renewing 1500-ms continuous-clock window. Each I/O budget is at most 500 ms and each retry delay at most 100 ms, shortened by the remaining episode, manifest and caller budgets. Fast failures therefore exhaust the attempt cap without waiting for the full window. Only a successfully validated status snapshot resets the episode. A subsequent status read after normal work/wait begins a new episode.

The existing synchronous client cancellation hook also observes the active episode deadline. It can close a silent status socket using C02d7's cancellation-aware I/O adapter, retaining the original per-request deadline. Returned status and completed ownership/cursor validation are checked again against episode expiry. A reply received after expiry cannot authorize native work. Episode expiry reports helper_status_recovery_timeout; exhausting attempts while the window remains reports the last transport error. Caller cancellation, output limits and execution deadlines retain precedence. Poll slices, kernel scheduling and opaque serialization/cleanup can overshoot requested timing; this is cooperative cancellation rather than a hard real-time latency bound.

## Authority and replay

Recovery requires the local failure shape: a boolean false ok, a whitelisted string error and no correlated response envelope. Structured helper errors and remote rejections are fatal, even if their error text resembles a transport code. Identity/session/request mismatches, malformed responses, oversized frames, cancellation, unsupported commands and setup failures do not become retry hints.

Retries use the same client, pinned helper instance and session. They fetch status on a fresh owned socket; they never restart a script, rebind to a replacement helper, advance a cursor from a hint, clear the replay ledger or run native effects from a failed/stale snapshot. Status ownership, pending native ownership and negotiated cursor checks still run before native dispatch. A regressing cursor or replacement helper/session terminates the run.

After a lost native-response ACK followed by failed status reads, a repeated pending native ID still returns its cached result. Its side effect is not executed again. Start outcome ambiguity remains fenced against automatic in-process fallback. An expired/missing session, failed helper or outage beyond the recovery limits still follows the existing failure path: clear the synchronous cancellation hook, make one pinned best-effort stop with its separate cleanup budget, release owned handles and clear local context/replay/runtime state.

The episode object stays on the owning runtime call's stack. The client's synchronous cancellation callback borrows its pointer and is cleared in finally before that object is destroyed, including NS/C++ exception unwind. It is inactive after a validated status, so it cannot impose the previous status deadline on a later native ACK or wait request. No worker, timer, persistent socket, protocol extension or new server-side admission path is added.

## Verification

The portable change-wait runner now covers 100000 independent elapsed-time/attempt/budget plans, exact three-attempt and 1500-ms boundaries, shortened caller budgets, bounded backoff, explicit reset, idle versus active expiry and UINT64 saturation. Existing notifier/cancellation tests remain.

The actual runtime-loop Foundation fixture adds recovery and exhaustion for all five transport codes, separate outages around a validated snapshot, a lost ACK plus status outage with one native effect, fatal remote/malformed/cancel/setup errors, helper/session replacement, cursor regression, cancellation/output rejection after retry, shorter caller deadlines, late successful replies and old capability peers. It checks pinned ownership, attempt counts, cursor provenance, ACK/effect counts, cleanup and cancellation-hook expiry. The helper client is controlled in that fixture; the existing separate transport suite exercises the actual client's socket/cancellation implementation. Full runtime-to-helper/device fault injection remains necessary.

All 62 workflow runners (36 source-contract, 26 native), 521 direct source-grep assertions and standards-conforming assert preprocessing pass on Windows; 16 artifact-only checks require CI outputs. Focused wait/transport/preprocessing checks were repeated after adding the episode cancellation hook. Darwin Foundation/ARC/ASan/UBSan and complete iOS/device runs cannot execute on this Windows host. No measured CPU, energy or throughput improvement is claimed; extra attempts deliberately trade bounded recovery traffic for resilience to transient transport loss.

## Remaining work

P0-12 remains partial: persistent connections, unknown-start outcome recovery, prompt disconnect while waiting for the command owner and device/performance qualification remain open. Longer outages and process replacement deliberately fail rather than attempting session migration. Qualify quiet/busy scripts, dropped status/ACK connections, helper restart, caller stop/expiry, sleep/wake and FD/memory recovery on matching rootfull/roothide builds. Remaining P0-13 adapters and P1-40 invalidation continue separately. TouchPOC and production TrollStore execution source are unchanged; both build workflows run the shared suites.
