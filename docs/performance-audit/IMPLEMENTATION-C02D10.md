# C02d10 — cancel opted-in waits while queued for helper command ownership

Date: 2026-10-26 (Asia/Bangkok). Baseline: `c96f525`; the user reported C02d9 built successfully.
Status: **source implemented; new Darwin/Foundation/ARC/sanitizer CI and device qualification pending**.
Finding: **P0-12 abandoned change-wait admission and command-owner cleanup**.

## Behavior

C02d8 monitored peer EOF only after a wait request acquired the command owner and validated its helper/session identity. A client that disconnected while queued behind another command could still retain one of the eight client leases until the original transport deadline. The helper now monitors opted-in wait connections during that owner queue as well.

The command owner uses a condition-based gate with one active guard. Ownership availability, queued cancellation, stop and waiter registration share one predicate mutex. EOF notification cancels only the matching queued token and wakes the condition; it does not wait for the current command to finish, release its guard or publish a lifecycle change. Other queued clients recheck their own conditions. There is no added polling loop or cancellation timer.

Before checking helper/session identity, the worker cancels and joins its queued-socket monitor, then checks the token, original deadline and client-admission state again while holding its command guard. A cancellation observed before this entry check cannot proceed to the identity handler. Once validation releases the command guard, the existing C02d8 notifier wait and monitor take over. The original sender/accepted deadline still constrains both phases, the wait remains at most 750 ms and the 25-ms output reserve remains in place.

Listener shutdown also stops the command gate. Queued legacy commands and opted-in waits wake and return without entering a new handler; a command that already obtained ownership can finish and release its guard. Ordinary commands use the same gate without a peer cancellation token. Peer disconnect cancellation in this slice is limited to waitForChange requests carrying the existing waitPeerEOFContract: cancel_v1 extension.

## Compatibility and ownership

The wire protocol, client API and capability values do not change. Missing EOF opt-in retains legacy write half-close semantics. The active command still excludes other command handlers, and command ownership is released before socket output and before a notifier wait. As with the previous timed mutex, this gate promises exclusion, not FIFO ordering among concurrent clients. It does not preempt an entered opaque command, undo a committed native effect or authorize replay/restart.

The gate returns a move-only RAII guard, including C++/Objective-C exception cleanup. Cancellation never implicitly releases an already-granted guard; the request's entry check and normal scope exit remain responsible for that ownership. Tokens are non-copyable and must be associated with the same gate for every access. The gate must outlive guards, waiting workers and cancellation monitors; the helper/client block retains the server for those scopes.

The existing READ monitor now accepts a typed owner/token pair and stores a cancellation callback, so its socket and source lifecycle code is shared by the command gate and change notifier. Each phase joins its source before token destruction or closing/reusing the borrowed FD. The two monitors are sequential, with at most one active source/semaphore per connection, bounded by the existing eight client leases; the four notifier-wait cap is unchanged. EOF remains level-triggered across the monitor handoff, so a close in that gap is visible to the next source. A close racing an already-produced hint can still cause an attempted bounded reply, without native/session mutation.

Source setup failure retains the existing recoverable change_wait_busy error. Completed cancellation releases the queued worker's client lease through the existing socket/finally/admission owner. The watcher never closes the borrowed FD. Source joins and OS scheduling are not hard real-time guarantees. Two source lifecycles for an opted-in wait add setup/cleanup work; net latency, wakeup and energy effects require measurement.

## Verification

The existing portable admission runner adds 100000 command-guard/pre-cancel lifecycles, move ownership, expired/free and blocked-owner deadlines, 64 targeted cancellation rounds with three unaffected peers, 1000 cancellation/registration races, post-grant cancellation without ownership revocation, C++ unwind, shutdown and 80000 serialized transactions across eight threads. Existing eight-client descriptor/admission tests remain intact.

The actual macOS transport fixture compiles the production gate, generic source monitor and extracted owner/wait handlers. It covers READ EOF cancellation against a held command owner, draining an abandoned client without unlocking that owner, replacement notifier admission, legacy versus opted-in half-close, gate stop for both request types and NS/C++ source/guard unwind. A direct gate/READ test uses a 10-second deadline and requires cancellation while time remains, distinguishing a real wake from normal timeout; the production transport cap is unchanged. Existing client/socket identity, queue expiry, source FD reuse and status-wait suites remain wired into both workflows.

All 62 workflow runners (36 source-contract, 26 native), 521 direct source-grep assertions and standards-conforming assert preprocessing pass on Windows; 16 artifact-only checks require CI outputs. The new portable gate tests run on this host. Darwin dispatch/POSIX/Foundation/ARC/ASan/UBSan fixtures and complete iOS/device runs require macOS/device qualification. No measured performance improvement is claimed.

## Remaining work

P0-12 remains partial: persistent connections, unknown-start outcome recovery and device/performance qualification remain open. Non-wait commands and legacy waits retain bounded deadline-based handling of peer disconnects; cancelling an entered opaque handler is outside this slice. Qualify heavy command contention, rapid opt-in disconnect/reconnect, stop during both wait phases, helper restart, half-close compatibility and FD/memory recovery on matching rootfull/roothide builds. Remaining P0-13 adapters and P1-40 invalidation continue separately. TouchPOC and production TrollStore execution source are unchanged; both workflows run the shared checks.
