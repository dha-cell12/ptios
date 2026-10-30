# C04b — bounded root VPN broker clients

Date: 2026-10-30 (Asia/Bangkok). Baseline: `08ddc0e9`, C04a build passed according to the user. Complete normalized broker source SHA-256 before this change: `7d85c63f3243f25761a98a80db049f04a82da03cb2255affb0b52e1d3717aaf7`.
Status: **user reported build passed at `127580fb` before C04c; independent device qualification pending**.
Finding: **P1-63 unbounded accepted VPN broker clients**, client admission portion. P0-19 end-to-end timeout/IPC blocking and underlying manager operation admission remain open.

## Change

The root broker previously dispatched a global worker for every accepted socket. Its listen backlog of eight did not limit accepted sockets, queued blocks or active handlers. Acquire one of eight process-local client leases before dispatch. The limit covers both queued and running handlers, including request reads, synchronous manager waits, response writes and autorelease-pool drain. One just-accepted candidate can exist briefly while admission is checked; this is not a limit on all process descriptors or kernel connections.

When full, close the new candidate immediately through an existing scoped socket owner. Do not create a client worker or attempt a possibly blocking overload reply. The caller follows its existing transport-failure path (for example no response or send failure); no new busy wire message is introduced. There is no waiting admission queue in the accept loop.

Reuse the existing shared client admission lease and scoped descriptor implementation. Before admission succeeds, the scoped socket owns the FD, including allocation/NS/C++ enqueue failures. After successful adoption, the shared lease owns both FD and capacity throughout the queued block and handler; the handler borrows the descriptor and no longer closes it itself. Explicit finish occurs after handler I/O and pool drain. Lease destruction also handles a discarded block, and its exact-once finish prevents a later block destruction from closing a reused descriptor. The captured lease retains its own state after the server admission owner is destroyed.

Contain NS/C++ enqueue and worker exceptions so their resources are released and the accept loop can continue. Keep the existing command parser, 1,024-byte request policy, response/diagnostics encoding, ordinary license gates, manager calls, 8/24-second waits, 30-second per-socket I/O timeouts, listener binding/backlog and loopback boundary. Rootfull/roothide broker port 6014 is covered. Production TrollStore foreground/agent listeners are separate and unchanged; TouchPOC is excluded.

## Verification

Both workflows run `check-vpn-broker-admission-safety.mjs`. It verifies the complete broker against a frozen SHA-256 baseline after reversing only admission, descriptor ownership and dispatch changes. The old/new handler comparison permits only the two removed closes. Existing VPN P0–P5 contracts and the original response/authority/manager source remain protected.

On macOS the runner compiles actual enqueue/handler code and the frozen handler with Foundation, real POSIX socket pairs and GCD, ARC and ASan/UBSan. The response provider, exceptional allocation/dispatch paths, logging and lease-close observer are controlled; the actual shared lease and scoped socket are used. Cases cover eight held-queue clients, eight active stalled readers, immediate ninth rejection without response work, 208 old/new parser/I/O cases (LF/EOF/UTF8/NUL/empty/exact and oversized input), acquisition/enqueue/response NS/C++ failures, discarded blocks, retry, stopped admission, owner destruction, deliberate FD reuse inside the closer, and 8,000 concurrent client attempts. Response parsing accepts EOF/reset on intentional early closes. No real manager, VPN connection, profile or license state is changed.

Windows validation passed: all 67 workflow runners (36 source checks, 31 safety runners), 521 existing workflow source checks, expanded assert preprocessing and `git diff --check`. Sixteen artifact-only checks are skipped. The new Foundation/POSIX/GCD runtime was not executed on Windows and requires macOS CI. These are resource/ownership checks, not measured device latency or throughput.

## Remaining work

Eight slow clients can occupy the entire capacity. Existing relative receive timeouts can be extended by trickled input, and underlying manager operations/completions may outlive a broker wait. This stage bounds accepted client leases/workers, not every asynchronous manager operation. End-to-end accepted-time deadlines, late completion synchronization/cancellation, manager admission/coalescing, synchronous IPC head-of-line blocking, TrollStore listener admission and device qualification remain open. Do not mark all C04/P0-19/P1-63 work closed on this basis.
