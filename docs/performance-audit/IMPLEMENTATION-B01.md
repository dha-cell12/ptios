# B01 — P0-01 / P1-01 / P2-04

Date: 2026-10-17. Base: `93d2b8b` (A06 build reported passed by the user after harness/OpenCV corrections).
Status: rootfull/roothide source implemented; Windows portable suite and source contracts passed. New macOS integration/iOS build and device qualification pending.

## Ownership and completion

`pccontrol/Record.xm` uses one named, dedicated CF run-loop thread for lifecycle and HID ownership. It registers/schedules and unregisters/unschedules the client on that same saved loop and releases the Create-rule client. Callback target is the process-lifetime recorder; refcon carries a non-reused generation. A callback from an old client cannot append to a newer session. There is no recording-specific run loop nested on a shared GCD worker.

The shared core has Idle -> Starting -> Recording -> Stopping -> Idle. Start reserves Starting before directory/file/client setup. Busy includes startup and final drain/close. Concurrent starts admit one owner. Stops capture the requested generation before queuing; a stale stop returns an error and cannot stop a newer recording. The single owner thread sleeps in its CF event wait when idle; it remains allocated for the process lifetime. Its stack/CF footprint must be measured on devices.

Metadata snapshots UIKit/private foreground state on main before entering the owner. The owner/writer never synchronously calls main, so a main-thread API caller can await completion without a main/owner wait cycle. Indicator updates are main-only and compare the requested generation to suppress stale show/hide blocks.

Direct stop and SpringBoard Task-15 task replies wait for HID teardown, accepted pending records, final raw-file fsync/close and completion metadata. File errors become task errors. The volume-button path requests asynchronous generation-bound stop; it displays saved only after successful completion, keeping that HID/main callback out of file waits. The old void stop API remains an adapter that reports errors.

**Transport distinction:** the existing daemon treats Task 14/15 as fire-and-forget and returns `0;;queued`; this remains an admission/queue response, not a durable completion ACK. B01 does not redesign that IPC policy. Synchronous in-process/direct task clients see the completion/error response.

## Callback and writer budgets

One monotonic timestamp is captured at callback entry, before parsing/enqueue or any storage work. Accepted children in the same callback share that arrival time, preserving child order and giving subsequent same-frame children a zero delay. This is callback arrival time, not a validated hardware event timestamp; owner scheduling delays remain part of the sample.

The normal digitizer callback reads fields and appends fixed C++ records. It does not build NSString/NSData, format text, log, write a file or reread the unused HID range field. A short mutex protects fixed storage; no file work or formatting occurs under that mutex. Input is checked before the complete callback batch is admitted.

- Pending capacity: **4096 records** (96 KiB of record payload on the current 64-bit layout).
- Callback batch: at most **20 children**, finger indices **0..19**, finite normalized coordinates in **0..1**, positive finite dimensions within the five-digit fixed-point wire range.
- Writer removes up to **256 records** per ring access and formats into a fixed **16 KiB** byte batch. A coalesced data source wakes it at the 256-record threshold; an active-only **100 ms timer with 10 ms leeway** flushes smaller batches. Stop cancels both sources and drains the tail explicitly.
- The in-flight 256-record chunk, byte batch, callback stack, objects and thread stacks are additional to the pending ring. This is a bounded application buffer, not an RSS ceiling.

On overflow or invalid accepted input, the callback admits no part of that new frame, marks Stopping and queues owner teardown after returning. It does not evict MOVE/DOWN/UP records or keep recording silently. A write failure stops admission immediately and posts owner teardown without a writer-to-owner synchronous wait. Failure is reported and the package is marked failed; an incomplete prefix may remain. No loss-free claim is made under storage failure or overflow.

Writer work is generation-filtered. A canceled source handler arriving after close cannot touch a newer session's descriptor. New recording admission stays blocked until the old descriptor has been closed. A stalled storage syscall can delay completion indefinitely; B01 neither interrupts a blocked write/fsync nor promises a stop-latency SLA. Busy queries/new-start rejection use the short core lock and need not wait for storage.

## RAW compatibility and files

Keep the existing one-child Task-10 wire representation, Task-18 delay lines, child order, down/move/up mask precedence, device geometry and Entry/Orientation/FrontApp metadata. Coordinate conversion keeps the old float intermediate and nearest rounding used by the old %.0f formatting, bounded to five digits; 1000 coordinate fixtures match that formatting.

The writer derives all delays from captured timestamps, never writer completion time. It rounds nanoseconds to nearest whole microseconds; a regressing sample is clamped. Gaps above signed-int microseconds are emitted as multiple valid Task-18 lines, preserving the total gap without producing an unplayable delay. No speed/playback/license policy is changed.

Packages use a timestamp plus UUID stem, exclusive mkdir and O_EXCL raw open so same-second starts cannot append to or truncate an earlier script. Existing permission defaults are retained. Start checks folder, metadata and file creation before publishing success. Direct Task 14 now returns one status/path envelope (`0;;path\r\n`) after setup, replacing the old racy bare-path plus separate ACK writes; clients depending on that old direct path format must parse the status/path field. The daemon queued route is unchanged. The legacy C API keeps its synchronous path-only notification. A borrowed task/IPC stream is never captured by the owner/writer.

`RecordingStatus` is recording, complete or failed, with RecordingError on failure. Normal stop fsyncs the raw descriptor before close and checks the metadata write result. This is not a crash-atomic journal: a crash may lose pending/batched data, completion metadata/directory persistence is not guaranteed, and existing script-list clients may ignore the added status fields. Partial failed packages are retained for diagnosis; they are not reported as successfully saved. Close errors (including ambiguous EINTR) are reported; close is not retried against a potentially reused descriptor.

## Verification completed on Windows

`node scripts/check-recorder-safety.mjs` compiles the production shared ring, encoder and batching/write helpers with C++14, MSVC /W4 /WX:

- 100,000 records round-trip through the actual RAW reader/touch parser, including all 20 fingers and down/move/up order; recorded delay sum is independent of a deliberately slowed write callback;
- **385 fixture writes** for those 100k records versus the old per-event write shape; this is a fixture result, not a device performance measurement;
- exact RAW golden records, long-gap splitting, regressing time and 1000 old-format coordinate comparisons;
- complete-frame capacity rejection, no eviction, pending-tail drain, stale generation/callback/stop rejection and geometry validation;
- partial writes, EINTR retry, zero-progress/ENOSPC/invalid-count failures;
- 8 clients x 1000 lifecycle cycles under the actual core locking/state contract.

All **36 existing source-contract checks** and native A01-A06 regression suites pass. git diff --check passes.

The rootfull/roothide workflow also compiles the actual recorder owner body on macOS with Foundation/CF/dispatch, ASan/UBSan, HID/UI doubles and real temporary files. The new harness covers same-loop/client teardown, synchronous response lifetime, normal drain, pending blocked write/stop admission, stale callbacks/stops, overflow, write/sync/close and startup failures, concurrent starts and repeated lifecycles. It was not run on this Windows host. UIKit metadata/indicator behavior and private HID delivery require device qualification. Production TrollStore recorder and TouchPOC are unchanged in B01; the findings implemented here refer to pccontrol.

## Build/device acceptance

1. Run macOS host CI, build rootfull/roothide and record/replay single- and multi-finger traces on iPhone/iPad in both orientations. Confirm actual HID indices/normalized coordinates satisfy the published limits; exercise the visible fail-stop path otherwise.
2. Stop through the volume shortcut, direct Task 15 and existing daemon queue route. Verify only completion-aware paths display success after file close; queued transport remains explicitly queued. Start/stop concurrently, including main-thread callers and delayed callbacks/source handlers.
3. Inject slow/full/read-only storage and metadata/client/open failures. Buffer exhaustion must stop with an error/failed status, preserve a bounded prefix, release HID ownership and prevent a new generation until cleanup finishes. Disk stalls may keep Stopping busy.
4. Compare input/RAW event order and arrival-to-delay timing, callback p50/p95/p99, write calls, allocation rate, RSS, wakeups and energy against A06. Include a long idle gap, stop with pending records and repeated same-second starts. Measure the dedicated idle owner thread's footprint before claiming net CPU/RAM gains.

Next: B02 (P0-07/P0-09/P1-20/P1-21/P1-24/P1-26), frame/image store ownership, byte budgets and compute outside the store queue.
