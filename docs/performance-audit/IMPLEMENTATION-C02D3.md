# C02d3 — bounded concurrent helper clients and serialized command ownership

Date: 2026-10-26 (Asia/Bangkok). Baseline: `d89c4d3`; the user reported C02d2 built successfully before this slice.
Status: **source implemented; new macOS/Foundation/GCD/iOS CI and device qualification pending**.
Finding: **P0-12 prerequisite: bounded client ownership and I/O isolation before event waits**.

## Result and scope

The helper listener now admits at most eight live client work items and dispatches them to a concurrent GCD queue. Admission happens before dispatch or body allocation; queued callbacks count against the same eight-slot budget. A ninth accepted descriptor closes immediately without queueing or parsing. The kernel listen backlog is separate from this application budget, and there is no reserved control-client slot or fairness guarantee under saturation.

Each work item carries its original monotonic acceptance time. Both queue entry and the complete client handler use the same 1000-ms C02d2 window, so delayed GCD scheduling does not restart the deadline. Parsed clients acquire one timed command owner before handleEnvelope, rechecking expiry and admission state after acquiring it. Read/parse and response serialization/write can proceed across independent clients, while command handling remains serialized. A slow reader/writer does not retain the command owner; an expired command waiter returns without running its handler.

This does not enable event waiting or remove 200-ms status polling/fresh sockets. A long license/native/opaque command still holds the serialized owner; other ready commands can time out waiting, and this slice cannot preempt that handler. It isolates socket I/O and bounds retained client work, not all head-of-line blocking or total process RSS. Production TrollStore and TouchPOC source are unchanged; both workflows run the portable admission runner and the expanded existing macOS transport runner. No device latency/CPU/RSS improvement is claimed.

## Descriptor and callback ownership

An accepted descriptor initially belongs to a Socket RAII owner. A successful admission lease adopts it before dispatch; rejected admission leaves it with the caller for immediate close. The queued block captures a shared lease, so copying a block does not copy ownership of a raw descriptor. The worker atomically transfers the descriptor once into the existing finally/RAII handler. Expired/stopped/discarded callbacks close their descriptor through the lease without entering the handler.

The lease releases capacity after handler/I/O work and its autorelease pool complete. Explicit finish and destructor cleanup are idempotent. Shared accounting state outlives the admission wrapper if necessary, preventing a callback's final lease destruction from accessing a destroyed pool. No pool lock is held across dispatch, parsing, handler work, logging or socket operations. Objective-C and C++ exceptions in a client callback are caught after the handler's socket/command cleanup and return its lease.

When the listener exits, admission closes. Queued callbacks and parsed clients recheck that state and cannot begin a new command; new accepted work is rejected. Already running I/O has the existing deadline and an already entered opaque handler remains non-preemptive. This is not a graceful daemon shutdown/drain or a promise that an in-flight handler is canceled before process exit.

## Ordering and compatibility

Start/status/stop/native-response handlers still share one command owner, preserving their serialization across clients. The existing one-pending-native-request condition, first-response-wins slot and root replay fence remain. Sequential root helper requests retain their order because the caller awaits each response. Across independent connections, a ready request can now overtake an earlier incomplete/slow frame; accept order is intentionally not a global command order. Concurrent callers must use session/request identity rather than assume FIFO across sockets.

Wire protocol version, command/result schema, identity validation, 1-MiB envelope bounds, EOF compatibility and fail-closed deadline checks remain. Status adds socketClientsActive, socketClientsLimit and socketClientsRejected counters; active includes the status connection itself. An admission rejection closes before the envelope is known, so no correlated busy response is fabricated and no automatic command retry is added.

The deadline starts after accept, not at sender issue time. Backlog delay and sender expiry/cancellation are still not propagated on the wire; a complete request that reached accept after its sender timed out may execute. Request expiry/cancellation propagation and reconnection/event sequencing remain P0-12 work. Event waits must eventually release the command owner before waiting, rather than blocking lifecycle/native-response commands behind a long poll.

## Validation

- New portable admission tests cover exact eight-slot rejection, 100k shared-reference and explicit descriptor-transfer lifecycles, lease survival after wrapper lifetime, idempotent finish, stopped/zero-capacity rejection and eight threads issuing 80k admissions. Tracked fake descriptors close exactly once and all admitted work finishes; peak admission stays within its configured cap.
- The existing macOS transport fixture now compiles the actual enqueue/worker, accepted-time handler, command-owner and cleanup code. It verifies stalled-reader isolation, eight queued callbacks/ninth-fd rejection, expiry without deadline renewal, command-owner timeout without later effects, closed admission and NS/C++ callback exceptions. The previous real client/server identity, framing, EOF and descriptor tests remain.
- Source guards require admission before concurrent dispatch, lease transfer/finish, captured accepted time, timed command ownership, listener integration/shutdown and both workflow runner entries. The full JavaScriptCore/license server lifecycle and device performance are not executed by the controlled fixture.
- All 61 workflow runners (36 source-contract, 25 native), 521 source-grep assertions, standards-conforming assert preprocessing and git diff --check pass on Windows; 16 artifact-only checks require CI outputs. Windows does not compile or execute the Foundation/GCD branches. Actual Foundation/GCD/ARC/ASan/UBSan and iOS/device execution remain pending on macOS/device.

## Acceptance and next slice

Build rootfull/roothide and run helper mode while holding one or more sockets before completing their frames or reading responses. Confirm another ready client can proceed when capacity is available, the ninth admitted client fails quickly without FD growth, accepted deadlines survive scheduling/command waits, and expired requests never run after acquiring the owner. Exercise concurrent start/stop/status/native replies against the real execution queue and verify identity/replay/cleanup behavior. Measure actual callback memory, FD counts, latency and saturation recovery.

Continue P0-12 request expiry/cancellation propagation, event wait generation/cursors and reconnect ordering, keeping bounded client ownership and releasing command ownership before event waits. P1-40 invalidation, remaining P0-13 adapters and C01/C02 device/performance acceptance remain open.
