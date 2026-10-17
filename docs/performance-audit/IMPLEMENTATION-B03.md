# B03 — root IPC hot path and bounded socket service

Date: 2026-10-17. Findings: **P0-05, P1-14 (daemon/socket portion), P1-16, P1-17 (IPC response portion)**.

Scope: pccontrol SpringBoard IPC and the shared tlinkautod/tlinkautob socket implementation for rootfull/roothide. Production TrollStore's separate transport is unchanged; prototype TouchPOC remains excluded. User reported the corrected B02 build passed at `e304763` before this group. Device acceptance remains separate.

The previous B02 next-group note incorrectly called B03 an OCR group. The authoritative plan assigns OCR cache/pixel work to **C01**. B03 implements the IPC/socket group in that plan; next is **B04 (H264)**.

## IPC behavior and compatibility

Daemon fire-and-forget sends now use message ID 2, distinguishing them from reply-bearing ID 1. Both package components ship together; old SpringBoard callbacks ignore the message ID and still accept the command. New callbacks continue accepting ID 1, preserving legacy reply behavior.

For ID-2 TASK::10, a length-checked byte prefix enters processTaskWithContext directly with the actual payload length and NULL stream. It creates no NSString command, response stream or CF reply and emits no per-touch IPC logs. Task/license/touch validation still runs in Task.xm; this is not a bypass of the license gate. Task 61 retains its sequence/dispatch ACK and becomes quiet in IPC logging. The daemon keeps aggregate task-10 denial counters without logging each dropped touch.

Other no-reply tasks also avoid a response stream. Reply-bearing tasks use the existing cross-TU native sink with a **1 MiB** ceiling, a one-byte placeholder CF stream and synchronous scoped ownership. The stream is closed/released in finally. Overflow discards partial output and returns `1;;ipc_response_too_large`; sink setup failure returns an error before running the action. No automatic retry is introduced. Full response NSString/log copies are removed; UI-tree logs remain redacted metadata summaries.

Existing legacy `0;;queued` responses and JSON fire-and-forget suppression remain. Queued still describes the old transport behavior, not a durable action-completion guarantee. A disconnect/output failure after an action starts does not prove that action was canceled; callers must not blindly repeat side effects.

The 1 MiB sink bounds appended response bytes while they are generated through notifyClient. Individual handlers may still materialize large intermediate NSString/JSON/vendor results before calling the sink; C01/C03 own those producer limits. The receiver's synchronous CFMessagePort callback and remote send timeout hierarchy remain unchanged, pending C04. A long SpringBoard task can still delay subsequent SpringBoard tasks/pings.

## Socket ownership, work and liveness

Each IPC callback and poll worker has an autorelease pool; socket/task queues drain autoreleased objects per work item so continuous traffic does not defer their release until thread idle.

The socket queue owns client membership, parser state, output queues, byte accounting and cleanup. Ordinary task execution, licensing and IPC waits run on one separate serial task queue. Only **one ordinary task per client** is admitted at a time; its buffered successors resume after its completion. This preserves FIFO for those requests without increasing compute parallelism. Across clients, ordinary work is serialized in admission order. Already-admitted work can finish after disconnect; queued work checks a closed atomic before entering its handler, and late completions cannot write to a reused connection.

Task 95 keeps its existing separate deferred poll path, one pending poll per client, and authorization moves off the socket queue. Its existing multiplex/ordering and disconnect-to-capacity behavior are not redesigned here; those belong to B06. In particular, a legacy poll response can still interleave with later ordinary responses as before. Use a dedicated legacy subscription connection; JSON IDs correlate deferred responses.

Liveness is explicit: legacy `CMD_PING\n` and JSON `{"id": 1, "command": "ping"}` return daemon transport status without waiting for ordinary work or license refresh. The legacy response is `0;;daemon\r\n`; JSON uses the existing id/ok/data/error envelope with data `["daemon"]`. This proves the daemon's socket service is progressing, **not SpringBoard health or feature authorization**. A ping on a connection with an outstanding ordinary request follows that connection's FIFO; use a separate connection to inspect liveness during its work. Existing requests without command=ping keep their prior task semantics.

Parser turns admit at most 32 iterations before yielding to the owner queue. Raw receive callbacks retain their CF object until queued delivery completes, look up membership before reading, and check bytes-available before a read. Stale queued read events cannot read a released/reused CF object. Input overflow and embedded-NUL legacy frames close the connection instead of executing a truncated prefix. Legacy task 19 without CRLF retains its existing compatibility path.

## Output and admission policy

| Resource | Limit / behavior |
| --- | --- |
| Connected clients | 64 |
| Outstanding ordinary tasks, running plus queued/completion | 16 globally; one per client |
| Received buffered input | Legacy 64 KiB; JSON 1 MiB plus 10-byte header (unknown protocol initially uses that upper bound) |
| Owned unsent output allocation | 2 MiB per client, 16 MiB globally |
| Output chunks | 128 per client |
| Per-client service turn | Up to four nonblocking send calls / 64 KiB |
| No send progress | Close at 5000 ms when serviced |
| Oldest response residence | Close at 30000 ms even with trickle progress |
| Backpressure service | Shared 20 ms timer while output is pending; disabled when empty |

Native send uses MSG_DONTWAIT and SO_NOSIGPIPE. Short writes advance an owned offset; EAGAIN/EWOULDBLOCK/EINTR preserve the complete suffix. Fatal/zero-progress socket failures close the client and release its remaining output charge. Consumed prefixes stay charged until their entire chunk allocation is freed, preventing retained allocations from bypassing the cap. The service timer is armed only when its active state changes, so frequent fast-client responses cannot postpone a stalled client's service/deadline indefinitely. It is not reset on every response.

Response-size/JSON encoding failures produce explicit bounded error envelopes with the request ID. Admission/output overflow closes the affected connection; it never silently truncates a success and continues. An input/work admission failure runs no new rejected action. Output failure can occur after an admitted action, so its outcome can be ambiguous to the caller. Task-95 polling retains its separate admission policy.

These are application-buffer and admission ceilings, not an RSS limit or a hard scheduling SLA. NSData/JSON strings, the producer result, a copied output chunk during admission, socket/kernel buffers, disconnected in-flight contexts, thread stacks and allocator metadata are additional. A full peer no longer blocks CFWriteStreamWrite on the shared queue. Kernel/scheduler pauses and a bounded parser/output turn can delay deadline observation. The 50 Hz backpressure timer adds active-only wakeups; compare latency/energy before replacing it with write-ready sources. No idle periodic timer is added.

## Verification

`node scripts/check-socket-transport-safety.mjs` passes on Windows with MSVC /W4 /WX. The shared C++ core is also built as C++11 on macOS, matching both daemon targets.

All **36 existing source-contract checks** and **8 prior native regression suites A01–B02** passed on Windows, along with the new B03 runner. git diff --check passed.

Portable coverage:

- strict length/message-ID handling for the no-reply touch prefix;
- exact byte order across tiny partial sends and repeated EAGAIN, four-call/64 KiB fairness;
- exact no-progress and absolute residence boundaries, including a trickling peer;
- retained-prefix byte charging, per-client/global byte limits, chunk limit, fatal/invalid writes;
- **100,000** flush/close lifecycles with no live charged output.

The root workflow includes a macOS ASan/UBSan harness that compiles the actual client type, output/timer adapter, work queue, deferred poll wrappers, parser, JSON encoder, read/cleanup/accept callbacks and SpringBoard CF IPC handler. Handler dependencies are doubled; real Foundation/CF streams, dispatch and Unix socketpairs exercise no-reply/ACK/output-limit behavior, FIFO under a blocked handler, independent transport ping, JSON fire-and-forget suppression, oversized-result errors, partial/nonblocking sends, timeout under other-client traffic, global work admission, queued disconnect and stale read cleanup. The socket clock boundary is controlled for deterministic deadline checks while dispatch and send are real. This branch cannot run on Windows and is not a substitute for iOS artifact/device qualification.

## Build/device acceptance

1. Run rootfull/roothide CI for both tlinkautod and tlinkautob and build the tweak. The existing source-contract and prior native suites must remain green.
2. Compare legacy/v1 golden responses for task 10, task 61 sequence ACK, queued tasks, image/OCR/AX/status/error cases and mixed ordinary requests. Verify no per-touch IPC logs or allocated response streams on the new no-reply route. Exercise compatibility with an old sender using ID 1.
3. Hold a receiver full, fragment writes, disconnect at arbitrary offsets and exceed output/work/client limits. Other clients and transport ping must progress; no success suffix may disappear while the connection stays open. Measure observed timeout/cleanup latency and verify output charges drain.
4. Hold an ordinary handler/CF IPC request, pipeline a later action on the same client, ping on a different connection and disconnect queued clients. Preserve ordinary FIFO, do not execute queued closed-client requests, and do not replay an uncertain action. Exercise repeated reconnect and FD reuse.
5. Measure task-10 CPU/allocations, socket queue residence, output syscall counts, response p50/p95/p99, RSS, backpressure wakeups and energy against B02. SpringBoard callback HOL, licensing internals and event-poll cancellation still require C04/B05/B06 qualification.

Next implementation group: **B04 — H264 backpressure/batching/pacing**. OCR cache/pixel work remains C01.

## macOS harness build correction - 2026-10-17

User CI at aec55dd passed the prior native/macOS suites and the portable socket-output test, then stopped compiling the B03 Foundation harness under -Werror. The extracted accept callback initialized only four of CFStreamClientContext's five fields. Production now value-initializes the entire context with {}. The test's NSLog macro discarded its arguments, making the real callback's timing variable appear unused; its replacement forwards all arguments to a format-checked capture function. The harness additionally checks the UI-tree timing summary and selector redaction, while retaining the no-log assertions for touch/ACK. No warning category is disabled and production IPC timing behavior is unchanged.

Windows cannot execute the Foundation harness; the corrected macOS compile/runtime and final root artifacts still need CI confirmation.

User reported the corrected B03 build passed at `a54251b` before B04. Device qualification remains pending.
