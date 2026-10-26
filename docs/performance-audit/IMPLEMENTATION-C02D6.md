# C02d6 — helper lifecycle ownership and dispatch snapshots

Date: 2026-10-26 (Asia/Bangkok). Baseline: `29858f0`; the user reported C02d5 built successfully before this slice.
Status: **user reported build `014db57` passed before C02d7; independent device/performance qualification remains pending**.
Finding: **P0-12 prerequisite: coherent lifecycle/native-slot reads and worker retirement before runtime wait adoption**.

## Result

Helper lifecycle fields, session/run identity, error/duration/path metadata, cancellation transitions and the native RPC slot now share the existing rpcCondition owner. Status builds and copies lifecycle/native dispatch fields under that same owner. A stop/terminal snapshot cannot expose a native request as dispatchable: the pending slot is advertised only while state is running. Internal pending ownership remains until worker cleanup/terminal commit so late responses still meet the existing rejection rules.

Status and handshake advertise `sessionSnapshotContract: "lifecycle_rpc_owner_v1"`. This identifies the stronger snapshot separately from C02d5's change-wait capability, for future runtime negotiation with mixed installed versions. The change sequence remains a wake hint sampled before the snapshot, not an exact snapshot version or a durable event cursor. No runtime wait adoption or reconnect/caller-disconnect change is included here; the existing 200-ms polling/fresh-socket loop remains.

## Worker ownership and transitions

A start reserves sessionWorkerActive and resets session/run/lifecycle/native-slot state in one condition-protected transaction. Socket start checks busy before license work and reserves again after authorization. The direct execution entry uses the same reservation. License work and JavaScript/file I/O do not run under the lifecycle condition.

Starting, running and stopping sessions, plus terminal sessions still finishing logging or cleanup, retain the worker reservation. New starts fail helper_busy until the owned execution wrapper retires the matching session in its final cleanup. Terminal status includes `sessionWorkerActive` to distinguish published results from a reusable worker. Retaining busy through post-result logging prevents a replacement from resetting state still being read or written by the old worker.

The worker checks ownership, cancellation and starting state before entering running/JavaScriptCore. A stop that arrives while work is queued or while script preparation is in progress therefore cannot be overwritten by a later unconditional running assignment. A stop after the running transition still uses the existing cooperative cancellation/watchdog; this slice does not preempt opaque work instantly.

Completion clears the native slot and publishes terminal metadata together. The first completion transaction wins; later records/completions from that terminal session cannot overwrite the captured result. Cancellation produces cancelled state/reason unless a prior license-revocation reason must be preserved. The logging summary is a retained immutable dictionary built from that transaction; subsequent logging reads the captured values rather than current mutable session fields. Worker reservation persists until the wrapper finishes logging, autorelease-pool return and final cleanup.

Error/duration records, running transitions, completion, retirement and file-close callbacks validate session ownership before changing state. Old-session stop/revocation requests fail the identity check. Stale finish/wrapper calls return before closing current handles. File-close callbacks validate the session while holding rpcCondition and then mutate the file table under its existing monitor, preventing an ownership-check/removal gap across replacement.

## Locks, diagnostics and exceptions

The lock order for nested access is rpcCondition then the file-table monitor; status samples file/heartbeat diagnostics under that monitor and releases it before acquiring rpcCondition. Heartbeat validates its timer token under the monitor, releases it, then performs a session-checked stop transaction. Lifecycle/file-table owners are released before timer authorization, script/storage I/O, session log appends, JavaScript evaluation, sleep broadcasts and change waits. Existing per-RPC NSLog diagnostics remain inside the native worker owner. Native waitUntilDate continues releasing its condition while sleeping.

Native response/timeout accounting completes under the RPC owner. Storage and scalar diagnostic counters use atomic property access; their updates have the existing single execution worker, with reset excluded until retirement. Socket/waiter/file/heartbeat diagnostics are separately sampled and may lag the lifecycle view; this contract does not claim one globally atomic measurement of every counter or deep copies of arbitrary native argument objects.

The owned execution wrapper handles NS/C++ failures and reaches final heartbeat/file cleanup and retirement. Native RPC execution now releases rpcCondition in finally, including an exception while consuming a malformed response, so the outer cleanup cannot deadlock trying to reacquire that owner. A worker that reaches retirement without a terminal commit is published as failed with helper_cleanup_incomplete and its pending slot is cleared. The change does not add a timeout to blocking file/log I/O: blocked cleanup intentionally remains busy and can require the existing helper restart/recovery path.

License authority/enforcement and feature policy remain intact. Revocation uses the same owner as stop and preserves its reason/error through completion. First-response-wins admission, request/helper/session fences, bounded replay, client/socket deadlines and four bounded change waiters remain. TouchPOC and production TrollStore execution source are unchanged.

## Verification

The existing helper-identity runner now extracts the actual session transactions, status snapshot, start, finish, owned execution wrapper, native worker and response admission into a second macOS Foundation/GCD/ARC/ASan/UBSan fixture. Controlled license, JavaScript/file/log operations keep those dependencies explicit; the full real JavaScriptCore/license/device stack still needs qualification.

New cases include one winner among eight start contenders; stopped-before-worker evaluation; 100 running/stop races; stale error/stop/completion/retirement/finish calls; first terminal result and retained snapshot lifetime; license-revocation metadata; four simultaneous readers during 1000 session replacements; busy while post-terminal logging is deliberately held; ordinary and NS/C++ failure cleanup; and an exception while the actual native worker consumes malformed response data. Existing change-wait/socket fixtures include the condition needed for session validation and retain their deadline/admission regressions.

All 62 workflow runners (36 source-contract, 26 native), 521 direct workflow source-grep assertions, standards-conforming assert preprocessing and git diff --check pass on Windows; 16 artifact-only checks need CI package outputs. Focused helper checks and assert preprocessing were repeated after the final native-worker finally and race-fixture changes. Windows cannot compile or execute these Foundation/GCD branches; macOS CI, actual iOS/helper execution, Thread Sanitizer/device race probes and CPU/RSS/latency acceptance remain pending. No measured performance improvement is claimed.

## Next slice

After build qualification, integrate the runtime with capability-gated bounded waits only when both snapshot and wait contracts are present. Use the cursor from the status actually processed, validate a fresh status before native effects, preserve replay after lost acknowledgements, and retain a bounded legacy path. Caller cancellation/deadline allocation, mixed-version behavior, helper/session replacement and reconnect ordering still require implementation/qualification. Remaining P0-13 adapters, P1-40 invalidation and C01/C02 device/performance acceptance remain open.
