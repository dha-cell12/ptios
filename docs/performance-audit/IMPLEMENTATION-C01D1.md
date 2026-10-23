# C01d1 — root image request deadlines across queue and IPC boundaries

Date: 2026-10-23 (Asia/Bangkok). Baseline: `74e656f`; the user reported the C01c3b build and storage-fixture correction passed before this slice.
Status: **source implemented; new macOS/iOS CI and device qualification pending**.

## Finding and scope

C01a–C01c3b bounded the image engines and their immediate owner queues, but external root requests could wait on the daemon task FIFO and IPC queue before those local clocks started. SpringBoard's CF callback also constructed a response budget with no deadline. Thus an old socket request could still authorize/capture/start compute with a fresh local budget.

C01d1 carries an earlier monotonic deadline through those boundaries. It applies to rootfull/roothide tasks 21/23/27.1/27.6/28/49/68/69/70/91. Production TrollStore implementations and TouchPOC are unchanged. The new shared parent-scope mechanism is inert for other tasks; frame/image/hardware cleanup contracts are retained.

This slice keeps the existing daemon FIFO and synchronous CFMessagePort architecture. It does not close C01 queue-isolation work; C01d2 remains next, including non-preemptible IPC/capture/engine/file boundaries. No full-C01 or device-performance acceptance is claimed.

## Admission and task scopes

At `zx_deferTask`, a parsed, accepted task receives an absolute monotonic deadline **before entering the global ordinary-task FIFO**:

| Tasks | Request ceiling |
|---|---|
| 23, 28, 69, 91 | 3 seconds |
| 21, 27 subtask 1 or 6, 49, 68, 70 | 8 seconds |

The existing 16-pending-task limit, one pending request per client, global FIFO, response grammar and daemon-only ping stay in place. Work expired while queued returns `1;;c01_request_expired` when its queue turn arrives; it does not enter the request handler/license/capture path. Queue entries are not eagerly removed and pending admission is not released before their completion. TCP partial-frame time and bytes buffered behind a preceding request on the same client are outside this admission clock.

Each selected request also owns a local cancellation token; socket cleanup cancels it. Queued disconnected work is skipped, and cooperative in-process waits/compute can observe disconnect. Completion resets only that client's finished token before admitting its next request. No token or deadline carries over to another client's task.

`zx_handleLegacyRequestBytes` caps direct daemon calls before authorization. `processTaskWithContext` caps direct SpringBoard/native/legacy calls before the root license gate, and its existing post-license checkpoint now observes that cap. Re-entering these layers takes the earlier existing deadline; it cannot restart the allowance. Local engine budgets and work/memory limits still apply and may reject earlier.

A new task-local native budget borrows its parent's response sink, capacity limit and cancellation token. Its deadline is the minimum of its own cap and the parent deadline. It leaves the parent deadline/owner settings unchanged, and scope exit restores the previous TLS budget. All output and sticky output-limit errors reach the original caller; there is no disconnected second response buffer. C01 work does not acquire a cleanup exemption from a cleanup-marked parent. Legitimate task 67/image release/hardware-UP requests retain their existing cleanup path.

## IPC envelope

Deadline-bearing synchronous calls use private CFMessagePort **message ID 3**, with:

```text
TC01 | uint64 absolute deadline, big endian | original UTF-8 TASK:: payload
```

The fixed header is 12 bytes; the original payload remains at most 4095 bytes. Both processes use the same local-host, same-boot `TLinkNativeNowNs`/steady-clock domain. Deadlines are ephemeral transport metadata, not persisted wall timestamps or client-provided network options.

The receiver validates magic, bounds, nonzero deadline, allowed task family, absent embedded NUL and at most eight seconds of future time before creating NSStrings or dispatching a task. Expired envelopes return `c01_request_expired`; malformed ones return `c01_ipc_envelope_invalid`. The validated absolute deadline is attached to the existing 1 MiB response budget and remains effective in task-entry/license checks and transferred engine/owner scopes. A known expired final response is returned as an error.

All daemon IPC queue wrappers now preserve the caller's native budget. Internal task-21 screenshot task 29 and orientation task 35 also carry that caller's deadline; independent ordinary task-29/35 requests keep their legacy behavior. Task 21 checks inherited expiry before capture/matching and replaces its short file-readiness sleeps with cancellable waits.

Before ping/send, CFMessagePort wait limits are computed from remaining time. Budgeted calls assign up to 10% to send (within the prior per-stage maximum), then the rest to receive (also within that maximum), so configured send+receive time fits the remaining allowance at call entry. Ping consumption is included before recomputing task-send waits. Calls without a budget retain their prior timeout values and IDs 1/2. This calculation does not make CoreFoundation calls preemptible.

**No retry with an unbounded legacy message occurs** if the deadline envelope is rejected or unsupported. Daemon and SpringBoard should be deployed coherently. An old daemon can still use IDs 1/2 with a new receiver, which applies a local task cap, but cannot include its earlier queue residence. A new daemon against an old receiver fails the deadline-bearing call instead of silently launching it without the deadline.

Cancellation tokens are local-process objects. A disconnect while CFMessagePort is already waiting does not remotely cancel an executing SpringBoard handler; the transmitted deadline bounds its next cooperative checkpoints. A result/effect committed before cancellation cannot be undone by converting a late response to an error.

## Remaining boundaries

The serial daemon task queue, IPC owner queue and SpringBoard callback can still be occupied by opaque or unrelated work. Expired requests wait for their queue turn before returning failure. Synchronous capture, CoreFoundation waits, model initialization, OpenCV/Vision internals and filesystem operations can overrun their deadline until the next checkpoint. Task-21 file cleanup remains best effort; a screenshot write finishing after a transport timeout can still require later cleanup. C01d2 must address isolation/owned late-work cleanup without allowing reordered side effects or detached unbounded workers.

No hard three/eight-second socket SLA, forced remote cancellation, total process memory cap, throughput improvement or measured CPU/energy saving is claimed here.

## Validation

- Windows: all 36 source-contract runners, 19 native runners and 528 TrollStore source grep assertions pass. Existing native scope, touch, playback, engine, storage and socket regressions remain enabled.
- New portable ingress suite passes classification/exemptions, exact deadline inheritance, original sink/limit sharing, sibling/parent independence, 64 child-wait cancellation races, malformed/truncated/future/expired envelopes, 100k malformed byte sequences and IPC wait allocation.
- New macOS Foundation/CoreFoundation fixture compiles the actual root task-entry/license prelude and actual IPC sender. Controlled license/CF-send boundaries check expiry before/after license, parent deadline/sink, cleanup exemption, exact envelope metadata, remaining timeout limits and no legacy retry.
- Expanded existing actual socket/CF callback fixture checks expiry while waiting behind a blocked FIFO task, no handler call for that expired request, disconnect waking a cooperative C01 wait, validated/expired/malformed IPC envelopes, pending-count balance and unchanged FIFO/JSON/no-reply/output behavior.
- Both workflows include the new runner and its fixture paths. macOS branches retain strict warnings, ASan and UBSan. **New macOS fixtures, final iOS builds and device tests were not run on this Windows host.**

Device qualification should cover a slow preceding task, cold license/engine state, daemon/SpringBoard queue contention, script and external socket calls, disconnect during compute versus IPC, coherent/mixed service versions, and late task-21 screenshot cleanup. Record actual queue residence, stop/response latency and capture/engine work after expiry; report opaque overrun separately from cooperative checks.

## CI fixture dependency correction

- C01d1 CI correction: both root and TrollStore macOS jobs reported `TLinkIPCNoReplyMessage` undeclared in the extracted sender fixture. Added its production `shared/TLinkIPCPolicy.h` import to the runtime fixture. The ingress runner now compiles sender message IDs against that fixture's own portable imports on every host, catching missing shared dependencies on Windows as well. Ingress, socket and native-budget portable runners pass on Windows; a negative probe confirms the compiler rejects the omitted policy import. Production behavior, strict warnings and sanitizers are unchanged; corrected macOS/iOS CI remains pending.
