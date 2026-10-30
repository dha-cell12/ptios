# C06h — bounded TrollStore VPN broker clients and manager operations

Date: 2026-10-31 (Asia/Bangkok). Baseline: `016d72f3`; user reported C06g build passed and requested continued implementation. This checkpoint addresses part of **P1-68** for production TrollStore ports 6015/6016. TouchPOC excluded. Shared operation-owner defaults used by rootfull/roothide remain unchanged.

Status: Windows source/portable validation. New actual/frozen Foundation/GCD/ARC/ASan/UBSan cases require macOS CI; no device performance measurement is claimed.

## Client admission and I/O

The foreground app broker no longer runs its client handler in the accept loop. Both it and vpnagent acquire one of eight process-local client leases before utility-queue dispatch. Count queued and running clients through handler I/O and autorelease-pool drain. Refuse an excess accepted socket immediately by closing it, without a potentially blocking busy reply. The scoped descriptor covers failed admission/allocation/enqueue; the adopted lease closes once after handler completion or discarded-block/NS/C++ unwind. Keep listener ports, loopback binding, backlog, agent version, identity drop and daemon startup behavior.

Reuse the root broker's existing ingress and output policy. One thirty-second continuous-clock window starts at admission just after accept, includes queue residence, and is not renewed by partial reads, manager waits or response writes. Use nonblocking recv/send with bounded remaining-time poll. Expired, regressed-clock and failed partial input cannot dispatch a command. Retry EINTR/EAGAIN within that window. Keep the 256-byte chunks, 1024-byte request limit, LF/EOF/cap framing, UTF8 decoder, empty/invalid request replies and ordinary output bytes. Unlike the old handler, a receive error after a partial command now closes without executing it.

Check expiry before reading, after decoding, before response authorization, after foreground/license/preflight work and before output. Status/diagnostics waits retain their eight-second phase cap and transition waits their twenty-four-second cap, clipped to the original request window. A queued or trickled request therefore cannot obtain a fresh thirty seconds at each phase. Timed-out sockets may close without an error reply once no output budget remains.

## Pending manager ownership and mutations

Use the existing synchronized completion owner instead of a __block result written by an async callback. First-result/closed-state gates reject duplicate or late results, release their values and do not retain the socket/client slot. Check the deadline after acquiring the result mutex. Wait in at most 250-ms slices to recheck continuous time after sleep.

Each process has eight total pending manager tickets, independent of the eight client leases. A client timeout or thrown/discarded starter is not proof that backend work finished. Retire a started ticket only after both starter return and the first terminal callback; a missing callback conservatively consumes capacity until process restart. No automatic replay or early capacity release is added. Manager admission overload returns `vpn_broker_busy` through the existing error envelope after the ordinary authorization path. Diagnostics/ping keep their existing exemption.

Additionally allow only one pending broker connect/disconnect in each process. It holds a second one-slot owner through the same return/callback fence, including after the client times out. A competing mutation receives busy; query/diagnostics can use remaining global tickets. Extend the shared operation owner with a configurable capacity clamped to zero through eight; its existing constructor cursor and default eight-slot policy stay intact for rootfull. The mutation wrapper retains the original twenty-second manager timeout and parameters.

Keep complete preflight, license, foreground, command, reply and diagnostic field source outside these scoped changes under reversal/hash guards. Preserve signed/runtime authority and fresh dynamic VPN state. Mutation admission covers this broker's calls only: direct UI callers and the other broker process do not share its lane. Streamd fallback routing remains unchanged and can try the other process; this is not global VPN serialization or deduplication.

## Verification

Add `check-trollstore-vpn-broker-safety.mjs` to both production workflows. Freeze complete preceding foreground/agent sources with SHA-256 respectively `36688d853eaa9fd45cb49533e57032c6b328323acf315c6673a9a6c25038aa35` and `f1010a22e8b6b258cf2d42c029d470f1d1c91a86ae7774895bd1064cbd937064`. Reverse only the changed admission/I/O/wait/mutation sections and require complete prior-source equality. Require the wait and enqueue policies to match the root implementation after symbol/error-code adaptation. A separate hash reversal preserves the original shared operation-owner source except configurable capacity. Exercise native fixture extraction on every host.

The new runner builds four macOS executables, two per broker:

- Reuse the actual/frozen socket-handler matrix: held/running GCD queues, eight-slot/ninth rejection, ordinary LF/EOF/UTF8/NUL/1024/1025 framing parity, stalled readers, admission/enqueue/handler NS/C++ faults, discarded blocks, owner lifetime, FD reuse, queue/trickle/decode expiry, real socket backpressure and 8k concurrent clients per broker. Response computation is controlled.
- Compile actual/frozen wait/response/diagnostics functions with controlled foreground state, entitlements, manager, authority and clock. Compare ordinary success/failure/inactive/denied/unentitled/ping/query/connect/disconnect/diagnostics replies and decoded metadata. Cover asynchronous/duplicate/nil/late results, pool lifetime, timeout/clock/phase consumption, provider unwind, eight pending operations across timeout, stale ticket recovery, mutation busy with independent reads, late mutation completion and NS/C++ mutation-starter unwind. No actual NetworkExtension manager, VPN profile or radio is changed.

Extend the portable operation suite with disabled/single/clamped capacity, stale identities and 8k contended single-slot admission attempts; retain the existing 100k lifecycles, 80k concurrent default-cap operations and 1000 completion/return races.

Windows validation: all **75 workflow runners** (36 source, 39 safety), **521 existing workflow source checks**, JavaScript syntax, fixture extraction, expanded assert preprocessing and `git diff --check` pass. The affected root broker portable suite is rerun after the shared capacity change. Sixteen artifact-only checks are skipped. New Foundation/GCD/ARC/sanitizer execution and iOS builds remain pending macOS CI.

## Remaining work

P1-68 is partial: client/manager work is bounded, but workers still wait in poll/semaphore slices; this is not a fully asynchronous state machine. Equivalent status requests are not coalesced. Main-queue foreground reads, preflight, provider starter calls and backend work are opaque and cannot be preempted by the window. An admitted mutation can still act after its caller times out; no rollback, cross-process lane, fallback deduplication or backend cancellation is provided. Static preflight caching/private polling, C06g shared HTTP cancellation, active supervisor cancellation and device CPU/RSS/latency/power qualification remain open.
