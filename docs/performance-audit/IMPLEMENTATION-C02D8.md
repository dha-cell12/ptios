# C02d8 — release helper change waits on opted-in peer EOF

Date: 2026-10-26 (Asia/Bangkok). Previous slice: C02d7 (`12a915e`), build passed according to the user.
Status: **user reported build `b206649` passed before C02d9; independent device/performance qualification remains pending**.
Finding: **P0-12 prompt cancellation of abandoned helper waits**.

## Behavior and compatibility

The rootfull/roothide helper client adds the envelope extension `waitPeerEOFContract: cancel_v1` only to waitForChange requests. It keeps the write side of that connection open until reply, timeout or cancellation. For these opted-in requests the helper watches socket read readiness through a dispatch READ source: EOF, a fatal read error or additional post-request input cancels that connection's wait. The handler peeks nonblocking; EINTR/EAGAIN do not cancel a live wait. The source cancels itself after its first terminal event, avoiding a repeated EOF/data callback loop.

An EOF cancellation returns no reply. It releases the condition waiter and, after source cleanup and socket close, the existing client admission lease. It does not stop the script, change native request ownership, advance the helper sequence or wake another waiter as a change. The other waiters recheck their own predicates after the shared condition notification. No new cancellation polling timer or polling interval is added to the server; C02d7's client cancellation poll slices remain.

EOF also represents a legitimate write half-close, so it cannot universally mean that a client abandoned its response. A request without the extension retains the old bounded-wait/half-close behavior. The new extension remains outside the strict two-field wait payload; older helpers ignore it using their existing envelope codec and continue the bounded wait. Unknown, null and non-string extension values are rejected as invalid_wait_request by the new wait handler. Status and handshake capabilities advertise `changeWaitPeerEOFContract: cancel_v1`; runtime wait/snapshot negotiation and reply hints are unchanged.

## Ownership, bounds and deadlines

The portable notifier has one non-copyable cancellation token per wait, accessed under its own notifier mutex. Cancellation and condition registration use that same lock, including the pre-cancel path, so a close between source activation and wait registration cannot lose its wakeup. Tokens must remain associated with the same notifier and alive through all callbacks.

The monitor borrows the already-owned, prepared client socket. A single dedicated serial GCD event queue handles these sources independently of the concurrent client queue and its barriers. Each opted-in client can own one source and completion semaphore; the existing eight-client admission cap bounds monitor objects, and at most four clients can sleep in the notifier. No additional socket descriptor or dedicated thread per wait is allocated. Source/semaphore setup failure returns the existing recoverable change_wait_busy error before entering a condition wait.

Normal return, cancellation and C++/Objective-C exception unwind cancel and join the source before the socket owner closes the descriptor or the token goes out of scope. The source's cancellation handler signals completion after event callbacks and underlying-handle registration have been released. This follows [Apple's dispatch source cancellation requirements](https://developer.apple.com/la/documentation/dispatch/dispatch_source_set_cancel_handler_f) and prevents callbacks from touching a reused descriptor or a dead token. The monitor never closes the borrowed socket; the existing Socket/finally owner does so once. Cleanup is idempotent and does not run on the source event queue.

The command owner is still released before waiting. Wait duration remains at most 750 ms within the original sender/accepted deadline, with the existing 25-ms output reserve; no deadline is renewed. Source cancellation joins are scheduler-dependent, so no hard cancellation-latency guarantee is made. A close racing an already-produced hint can still cause an attempted bounded write, but cannot execute native work or mutate session state.

## Verification

The portable change-wait suite adds 100000 pre-cancel cases, 64 targeted-cancellation/isolation rounds and 1000 cancellation/registration races. It checks unchanged cursors, reusable waiter capacity, unaffected peers, repeated cancellation and zero final waiters, alongside the existing 100000 publication/registration cases and 80000 concurrent publications.

The actual macOS transport fixture now compiles the production monitor and extracted wait/socket handlers. It covers EOF and extra-input notification with a 10-second test deadline (a timeout cannot pass as cancellation), 128 source lifecycles with forced watched-FD reuse, normal timeout, invalid setup, repeated cleanup and NS/C++ unwind. Socket integration covers four waiters with one disconnect and slot replacement, legacy versus opted-in half-close, EOF before registration, strict extension values and the actual public client's cancellation with server waiter/admission cleanup. The long direct-monitor deadline is a test watchdog, not a production wait allowance.

Both existing workflow runners include the new coverage; no new CI runner is required. All 62 workflow runners (36 source-contract, 26 native), 521 direct source-grep assertions, standards-conforming assert preprocessing and git diff --check pass on Windows; 16 artifact-only checks require CI outputs. The Darwin dispatch/POSIX/Foundation/ARC/sanitizer paths cannot run on this Windows host. Device qualification must include rapid stop/disconnect, quiet waits, busy admission, helper/session replacement and FD/memory recovery. No measured CPU, energy or latency improvement is claimed.

## Remaining work

P0-12 remains partial: persistent sockets, unknown-start outcome recovery, richer status reconnection and device/performance qualification remain open. Legacy or old-helper waits still retain their bounded slot until publication/expiry/stop. Disconnects while waiting for command ownership and cancellation of already-entered opaque handlers are not made prompt by this slice. Remaining P0-13 adapters, P1-40 invalidation and C01/C02 measurement work continue separately. TouchPOC and production TrollStore execution source are unchanged; both build workflows run the shared safety checks.
