# B06 — asynchronous event waits and transport cancellation

Date: 2026-10-17. Baseline: `b3383d9`. The user reported the B05b build passed before B06. B05b device/performance qualification remains pending.

Status: **B06 source implemented; user reported build pass before C01a; device acceptance pending.** Rootfull/roothide and production TrollStore are in scope. Prototype TouchPOC is excluded. Next group: **C01 — OCR/template/color**; C01a details are tracked in `IMPLEMENTATION-C01.md`.

## Wait and replay policy

P0-17/P1-55/P1-57: shared task-95 waits now use one serial event owner and one dispatch timer per process. TCP legacy, root JSON and the production remote WebSocket adapter register asynchronous requests; a long-poll no longer holds a global worker for its 20–25 second wait. The short license authorization stage still runs on workers, with a separate admission limit of eight until each provider returns. Cancellation releases poll capacity without allowing disconnect churn to create unbounded simultaneous authorization providers.

Every successful publisher retains the existing exclusive-flock journal rewrite and posts a Darwin notification **after commit and unlock**. Registration happens before the first read. Every authorized new request performs an initial journal read, so publication during registration cannot disappear between a read and a later wait. Notifications are coalescible wake hints; journal sequence/cursor remains authoritative.

Read-only journal snapshots use **shared flock**. The asynchronous owner uses `LOCK_NB`, so it does not park behind a publisher holding the file lock. A contended read is retried; if no usable current snapshot can be obtained by the request deadline, the request reports `event_journal_unavailable`. This does not bypass the lock to return a partial journal.

While requests are active, one **1-second metadata reconciliation** per process detects a missing/coalesced notification or a legacy publisher: device/inode/size and nanosecond modification/change times identify replacements. An unchanged file does not trigger JSON reads/parsing or batch reconstruction. A notification can force a reload. The timer and cached journal disarm/clear when the last request leaves. Fallback wake latency can reach the reconciliation interval plus queue, lock and filesystem delays; no hard latency guarantee is claimed. Publishers that bypass the locking/atomic-write contract are unsupported.

The synchronous `TLinkEventChannelPoll` / `PollBody` APIs remain compatibility wrappers over the same subsystem. They block their caller on a semaphore and must not be called from the event owner/completion queue. Production TCP/JSON/remote task-95 paths use the asynchronous API. This slice does not convert arbitrary future callers automatically.

## Cancellation and admission

P0-18: requests have an owner token with atomic, exactly-once admission release. Both TCP cleanup paths cancel the token before clearing it; no poll worker retains a CF stream. Completion uses a weak client reference, the current request identity and the cancellation flag before writing on the socket queue. A cancelled request cannot clear a newer request's pending flag or deliver its response to a replacement connection.

The remote bridge tracks event requests on its control queue, cancels them when that control WebSocket disconnects, and checks the original WebSocket identity before sending results. Cancellation here follows the **device control transport** lifecycle; a downstream browser disappearing while the relay/device connection stays alive needs relay-level cancellation signaling and is not inferred by the device.

Poll capacity remains **8 per process**. Cancellation returns that capacity immediately when cleanup calls `cancel`, independently of owner work or a running authorization provider. Already-running callbacks/providers are not forcibly interrupted; final transport delivery checks the token again. The separately bounded authorization stage can remain occupied until its existing verifier call returns. New requests return the existing `busy` schema while admission is unavailable.

A pending authorization has a **5-second owner timeout** and never reads/delivers journal data before its gate succeeds. The requested **0–25 second poll timeout starts after authorization**, preserving immediate zero-timeout reads. Timing is monotonic (P2-19); event timestamps remain wall-clock. Owner scheduling/opaque filesystem and verifier duration are not hard real-time bounds.

## Cursor and wire compatibility

P2-20: a bounded ASCII validator replaces per-request regex compilation; exact topics and `*`, case normalization, 16 topics and 64-byte token limits are retained.

P2-21: pagination advances through scanned unmatched events, including a trailing unmatched tail. It stops before the next matching event that cannot fit. `has_more`, retention `gap`, empty batches and at-least-once replay remain valid; no matching event is skipped to consume the tail. Clients still commit `next_cursor` only after handling a batch.

Task 95, schemas, Base64 legacy response, root JSON envelope, remote task result format, limits 256/32/4096 and license feature `automation` stay in place. Root output continues using its existing bounded nonblocking drain. TrollStore's general synchronous output writer, JSON/legacy envelope layering, full-journal publication cost, corruption/reset behavior and durable recovery remain C03 work; this slice does not claim to resolve them.

## Validation

Windows: **36 source-contract runners, 12 native runners A01–B06, all 528 TrollStore workflow grep assertions and PowerShell device-probe parsing pass.** B06 portable tests cover monotonic timeout boundaries, eight-slot cancellation/re-admission, 80,000 concurrent lifecycles, 200 finish/cancel races, 3,000 filtered pagination cases and ASCII edge cases.

Both workflows run `check-event-channel-safety.mjs`. Its macOS ASan/UBSan branch compiles the actual shared Foundation implementation, actual root legacy/JSON encoders and event adapters, and production TrollStore/remote event adapters. The journal root is redirected to a test directory; notification registration/post boundaries can suppress hints for the reconciliation case while the real filesystem and Foundation/dispatch/notify paths remain in use. License providers and socket write sinks are controlled in this fixture.

Cases include real cross-process publication, a deliberately missed notification, quiet/idle read counters, registration/publication races, eight cancellations while a writer holds flock, cancellation during authorization, a separately bounded eight-provider stage under disconnect churn, deadlines, filtered pagination/retention gaps, wire framing, same-context cancel/restart and denied authorization. The root socket regression additionally links the actual shared event subsystem and exercises eight real CF-stream clients through production cleanup. The remote agent's NSURLSession lifecycle cancellation is source-checked; its full UIKit/network dependency tree is not compiled in the event fixture.

**These new macOS branches have not run on this Windows host.** No new iOS build, device probe, CPU/RSS/energy or latency result is claimed. Build pass does not replace device qualification.

## Device acceptance

1. Build rootfull/roothide and production TrollStore, including the new macOS test branches. Compare default task-95 legacy/JSON responses, zero-timeout reads, rejected topics, license denial, page boundaries, cursor-ahead and retention gaps.
2. On a quiet device, run `Test-TLinkEventChannelV1.ps1 -HostIP <ip> -Runtime rootfull -RunCancellationStress` (or `trollstore`). It first confirms eight admitted idle polls, closes them, measures admission recovery and rejects recovery taking five seconds or more. Run script-event smoke separately with `-RunScriptSmoke`.
3. Repeatedly disconnect/reconnect all eight clients during initial authorization, blocked publication, event delivery and response queuing. Confirm no response reaches a replacement request, no retained stream/worker growth, and active counters return to baseline.
4. Publish across root/SpringBoard/TrollStore processes, drop wake hints, roll the journal past 256 events, and exercise filters with matched and unmatched tails. Confirm replay is complete within retained history.
5. Disconnect/reconnect the device's remote control WebSocket while polls are pending. Verify cancellation and connection identity protection. Relay/browser-only cancellation remains a distinct transport contract.
6. Measure idle and active journal-read/metadata counters, threads/wakeups, CPU, memory and latency against B05b. Expect no 10 Hz journal read/parse loop and no per-subscriber sleeping worker; active metadata reconciliation is intentionally retained at about 1 Hz per process. Do not interpret these source changes as measured battery savings.
