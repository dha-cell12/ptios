# C01d2b — bounded daemon image lane

Date: 2026-10-23 (Asia/Bangkok). Baseline: `c224451`; the user reported the C01d2a build passed before this slice.
Status: **source implemented; expanded macOS/iOS CI and device qualification pending**.

## Problem and scope

The root daemon's single ordinary-task FIFO contained both image work and unrelated tasks. In particular, task 21 performs its template search inside the daemon after screenshot IPC has returned. Its opaque decode/OpenCV/owner operations could therefore occupy the ordinary executor even when a subsequent local request needed none of those dependencies. C01d1 stopped expired work from starting later, but retained that shared executor.

C01d2b adds one serial image executor to `tlinkauto-binary/SocketServer.mm`, shared by rootfull/roothide tlinkautod and tlinkautob builds. Classification uses the existing C01 deadline function: tasks 21/23/27.1/27.6/28/49/68/69/70/91. Other ordinary tasks use the existing serial executor. Task 95 and transport ping retain their separate paths. Production TrollStore execution and TouchPOC are unchanged.

Each lane has at most one executing handler. The change permits an ordinary handler and an image handler to overlap; it does not introduce concurrent C01 image handlers in this daemon, per-request queues, detached workers or an expanded OCR worker pool. Existing cache, memory, engine admission and owner locks remain authoritative.

## Admission and lifecycle

| Resource | New policy |
|---|---|
| Image lane | At most 2 admitted requests, including the running request |
| Ordinary lane | At most 14 admitted requests, including the running request |
| Combined work | At most 16 admitted requests |
| Per client | One ordinary-or-C01 request admitted at a time |
| Release point | Completion committed on the socket owner queue |
| Overload | Close the rejected connection without enqueueing/executing that request |

Capacity is reserved in both directions. The ordinary ceiling falls from 16 to 14 even when the image lane is idle, and the image ceiling is 2 even when ordinary capacity is idle. Idle reservations are not borrowed: image saturation cannot consume all ordinary slots, and an unrelated blocked ordinary executor cannot consume both image slots. Bursts that previously joined the longer shared FIFO may now be rejected earlier. Reply grammar and the existing overload-close policy are retained.

The socket queue alone owns both counters. Running work, queued work and work awaiting its completion callback all remain charged. A disconnect cancels a C01 token but does not free admission before the actual worker completion. An expired queued request is skipped when its lane reaches it and then releases its slot. Repeated timeout/reconnect therefore cannot build an unbounded backlog behind a non-cooperative image operation. If an owner never returns, its charge remains held; this slice does not force unsafe worker termination or declare the slot idle.

C01 deadlines still begin before queue submission, are carried in the worker's native budget scope and include lane residence. The existing before/after-handler checkpoints reject expired results. Both Objective-C and C++ handler exceptions are converted to the existing `request_failed` response inside the dispatch block so the controlled handler failure reaches normal completion bookkeeping.

## Ordering change

The parser continues to pause on `ctx.requestPending` and resumes only from that request's completion on the socket queue. A single connection therefore retains FIFO and response order while moving ordinary -> image -> ordinary, including fire-and-forget suppression and bounded JSON replies. Disconnect checks and strong request context ownership prevent late work from replying to a replaced connection.

Within either lane, different clients retain serial admission order. **Across the two lanes, different clients no longer share a global FIFO or completion order.** For example, client B's local ordinary request can complete while client A's task-21 template compute is still running. This intentionally supersedes B03/C01d1's shared-FIFO behavior. Workflows with dependencies on another connection's screen changes, frame/image creation, removal or configuration must wait for that operation's acknowledgment before submitting dependent work, or keep those requests on one connection. Merely sending them earlier from another connection is no longer an ordering barrier.

Existing task-95 deferred subscription multiplexing is unchanged and is outside the ordinary/C01 per-client FIFO guarantee. A daemon transport ping on a separate connection still bypasses both work lanes; on the same connection it follows that connection's preceding request.

## Boundaries still open

Both executors still share the serial IPC sender owner and SpringBoard's synchronous CFMessagePort callback. An image request needing those dependencies can still wait behind an unrelated IPC operation; conversely a long SpringBoard image handler can still delay a later ordinary SpringBoard action. A local diagnostic can also wait on one of its own locks/services. The new lanes isolate daemon executor ownership, not every downstream dependency.

Capture, encoder, filesystem, model load, OpenCV and Vision operations remain cooperative/opaque. No hard response SLA, forced remote cancellation or measured CPU/latency/RSS reduction is claimed. Source-visible admission limits do not cap opaque process memory. Existing C01d2a temporary ownership remains in place; process-crash retention is still unresolved.

Next C01 boundary: IPC completion/owner isolation and safe late-result ownership, preserving the single-client ordering and bounded admission established here. Any asynchronous completion design must retain charges until opaque work actually exits. C01 remains open pending that work and device qualification.

## Validation

- Windows: all 36 source-contract runners and 20 native runners pass; expanded C01 policy tests check reserved capacity in both directions, 441 counter states and invalid/overflow admission. Existing deadline, cancellation, envelope and 100k malformed-input checks remain enabled.
- Expanded macOS socket fixture extracts the actual production queues, parser, work/completion adapter and CF callback. Real dispatch/socketpairs with controlled handlers check ordinary work during blocked image work, image work during blocked ordinary work, same-client ordinary/image/ordinary reply order, expired queued image work, active and queued disconnects, both lane caps, the combined 16-slot boundary, Objective-C/C++ exception recovery and final zero pending/output/client accounting.
- Existing no-reply, JSON ID/error, oversized output, event cancellation, backpressure and stale stream tests remain in that fixture. The root workflow already runs it with strict warnings, ASan and UBSan; no warning or sanitizer is disabled. Both workflows run the expanded portable C01 admission test.
- **The expanded macOS fixture and final iOS builds were not run on this Windows host.** It uses controlled task handlers and does not establish real-device capture, OpenCV, license-service or SpringBoard scheduling latency.

Device acceptance: build both root runtimes and daemon binaries; pipeline image and ordinary commands on one client; run independent clients in both lane directions; saturate two image slots and 14 ordinary slots; disconnect queued/active work and check subsequent recovery. Separately block downstream IPC and record its remaining head-of-line delay. Verify frame/image reader lifetimes, capture after acknowledged touch, normal error/reply fields, screenshot lease cleanup and idle wakeups. Record queue residence, latency and RSS against C01d2a without treating a build pass as performance acceptance.
