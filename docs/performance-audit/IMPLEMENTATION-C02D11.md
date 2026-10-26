# C02d11 — bounded persistent helper status/wait/ACK channels

Date: 2026-10-26 (Asia/Bangkok). Baseline: `f2c951e`; the user reported C02d10 built successfully.
Status: **source implemented; new Darwin/Foundation/ARC/sanitizer CI and device qualification pending**.
Finding: **P0-12 fresh-socket churn in helper status/native-response traffic**.

## Negotiation and runtime adoption

After a successful start pins the helper instance, the rootfull/roothide runtime enables synchronous connection reuse on its run-owned helper client. Only status, waitForChange and nativeRPCResponse with valid helper/session identity can opt into `connectionContract: sequential_v1`. Start, stop, handshake and unscoped status keep their separate one-command sockets. Stop first closes an idle reusable channel; cross-thread stop delivery remains independent of the run's in-flight socket.

The helper grants continuation by adding a strict connectionLease to a successful correlated reply: contract, continuous-clock untilMs and remaining exchange count. The client retains the FD only after framing, protocol, helper/session/request identity and lease validation, including a decreasing request count on reused FDs. No lease means that the reply remains valid but the socket closes normally. Old helpers ignore the request extension and return no lease, so the new client keeps the existing one-shot behavior without a probe/retry. Reuse is disabled by default for other client callers; the runtime explicitly enables and disables it.

An expired but otherwise valid lease can be ignored without rejecting its business reply. Before the next request, expired or differently scoped cache entries close and a fresh connection opens. A bad lease schema, boolean/non-numeric time/count, unknown contract, excessive future expiry or renewed count fails as invalid_connection_lease. A cached FD is transferred into the request's local Socket owner; I/O, protocol and ownership failures close that FD. No failed command is automatically resent by the client.

The existing runtime status recovery and lost-ACK reconciliation remain responsible for errors. A lost ACK can be reconciled through fresh pinned status and the replay ledger, rather than repeating the native effect. Unknown start outcomes remain fenced against automatic in-process fallback. Every run exit clears the cancellation hook, disables reuse to close any idle cached FD, and then performs its existing best-effort stop/owned-handle cleanup. Client destruction also closes its cached FD through its C++ owner.

## Server bounds and ownership

At most four persistent channels can hold capacity within the existing eight admitted clients. Descriptorless leases reuse the admission core's shared-state/exact-once finish rules; the ordinary client lease and Socket still own the actual descriptor. When all four persistent slots are occupied, a valid request still receives a one-shot reply without continuation, leaving the other client capacity usable by ordinary requests. Status diagnostics report the contract and active/limit counters.

Each channel admits at most 32 exchanges and has a fixed 10000-ms continuous-clock lifetime from its initial accept. A continuation lease gives at most 1000 ms to deliver the next complete frame and is clipped to the fixed lifetime. After that frame arrives, processing gets at most 1000 ms, intersected with the original sender expiry and channel lifetime. A fresh processing window cannot revive an expired queued sender request. The original accepted-time window still governs the first request. Entered opaque work and OS scheduling remain cooperative limits, so these are not hard real-time FD-release guarantees.

Subsequent requests must retain the channel's helper/session scope, opt-in and allowed command set. A scope switch, missing contract, malformed framing or disallowed mutation closes the channel after rejection without dispatching that request. Before offering another lease, the helper checks that the active session still matches. Native ACK admission and status/native ownership gates retain their existing authority checks.

The existing concurrent client worker handles a channel sequentially, with one outstanding request/reply and a per-exchange autorelease pool. No extra thread or queue is created for a channel. Command ownership still excludes other handlers and is released before response output and notifier waiting. The four-wait cap, C02d8/C02d10 EOF cancellation, bounded output, sender expiry and exception cleanup remain in place. Shutdown rejects new continuation slots; idle reads and active work retain their existing bounded/cooperative cleanup.

## Framing and FD transfer

The shared reader now optionally reports LF completion and trailing bytes in the receive chunk. Legacy one-command EOF framing stays supported. Opted-in persistent requests require LF and reject coalesced trailing input before dispatch; continuation replies also require LF without trailing bytes. This sequential protocol does not provide multiplexing or pipelining. Separate later frames still pass normal per-request scope, authority, deadline and exchange-count gates.

The cached descriptor is private to the synchronous owning client. It is never shared with the independent stop client. Its flags/SIGPIPE suppression were prepared on first connect and are retained on reuse. The cache moves FD ownership into a local Socket for a request and can receive it back only after a fully constructed valid result. Socket reset/adoption closes the previous owner exactly once. No additional response payload is retained by the cache; its helper/session keys are bounded identities and it holds at most one FD.

## Verification

The portable transport suite adds 100000 fixed-lifetime/request-count oracle plans, exact idle/count/saturation boundaries, 100000 descriptorless four-slot admission lifecycles and LF/EOF/coalesced framing metadata. Existing framing, backlog expiry, cancellation, owner and replay tests remain. The POSIX branch adds 1000 cache scope/expiry/transfer lifecycles and reset/adoption checks with real descriptors.

The actual macOS client/server fixture asserts 72 mixed status/ACK/wait exchanges over three 32-request channels after a one-shot start. Further cases cover client destruction, old-helper downgrade, idle reconnect, separate stop, correlation failure on reuse, a dead cached FD without automatic ACK retry, strict lease faults/count renewal, four-slot fallback and ordinary admission, scope changes, expired next requests, EOF/coalesced/mutation rejection, NS/C++ cleanup and cancellation of a wait on a reused FD. Business dependencies in that transport fixture remain controlled; actual native-slot/replay authority is exercised by the existing separate fixtures. Runtime-loop fixtures verify enabling reuse and disabling it on success, failure and exception cleanup.

All 62 workflow runners (36 source-contract, 26 native), 521 direct source-grep assertions and standards-conforming assert preprocessing pass on Windows; 16 artifact-only checks require CI outputs. Focused helper checks were repeated after the final cache ownership changes. The new POSIX/cache/Foundation/ARC/ASan/UBSan tests cannot execute on this Windows host and await macOS CI. Full iOS/device integration, FD/memory recovery and latency/wakeup/energy measurement remain pending. The fixture's expected accept counts are coverage assertions, not device performance results.

## Remaining work

P0-12 remains partial pending device/performance acceptance and unknown-start outcome recovery. Client cancellation still uses the bounded poll slices introduced in C02d7; larger event/cancellation transport changes require separate measurement and design. Qualify long native calls that outlive idle reuse, dropped ACK/status replies, slot contention, helper restart, stop in both wait phases, sleep/wake and mixed client/helper versions. Remaining P0-13 adapters and P1-40 invalidation continue separately. TouchPOC and production TrollStore execution source are unchanged; both build workflows run the shared suites. No measured CPU, energy, RSS or latency improvement is claimed.
