# C02d2 — deadline-bounded helper socket I/O and framing

Date: 2026-10-26 (Asia/Bangkok). Baseline: `3e9f798`; the user reported C02d1 built successfully before this slice.
Status: **build reported passed by the user before C02d3 (`d89c4d3`); device qualification pending**.
Finding: **P0-12 transport prerequisite: bounded socket ownership before concurrent event waiting**.

## Result and scope

The root helper client and helper server now use a common nonblocking AF_UNIX I/O layer. Client connect, full request write and response read share one monotonic absolute deadline; neither partial progress nor EINTR/EAGAIN restarts the budget. The server gives each accepted client one 1000-ms I/O window when handleClient begins. Sockets require successful nonblocking/CLOEXEC setup and suppress SIGPIPE through SO_NOSIGPIPE on Darwin or MSG_NOSIGNAL where available.

Every socket has one RAII owner. Explicit finally-close protects the Objective-C I/O/handler scopes, and close is idempotent. Prefix/partial data received before timeout or I/O failure is never passed to the JSON parser. Complete server request parsing is followed by a deadline check before handleEnvelope/native work. Client responses are still subject to C02d1 command/request/session/helper correlation and start binding.

The server still accepts/handles clients serially, helper status still polls every 200 ms, and each command still uses a new socket. This does not enable concurrent admission or event waiting. Native/license policy, one-slot response admission, replay reservation and retired-ID behavior are unchanged. Production TrollStore and TouchPOC source is unchanged; both workflows run the new shared safety runner. No device latency/CPU/wakeup/RSS improvement is claimed.

## Deadline and failure contract

Reject non-positive client timeoutMs as invalid_timeout; cap positive values above 30 seconds at 30 seconds. Existing production callers use 250/500/1000-ms budgets. Use saturating deadline construction, recompute remaining time before retry/poll/I/O, and check expiry after receives and before reporting completed writes. Nonblocking connect verifies SO_ERROR and peer connection after readiness; a busy Unix backlog that returns an immediate connect error fails without an automatic retry.

Partial writes preserve the unsent suffix, EINTR retries within the same deadline, and EAGAIN waits for readiness. A zero write or fatal receive/send/setup error terminates the operation. HUP/ERR readiness reaches recv/send so buffered bytes/EOF or the actual socket error are observed. Polling does not renew the deadline. Client failures expose io_timeout, frame_too_large, invalid_timeout or stage errors with errno.

This is an I/O deadline, not a hard preemptive timeout for Foundation serialization/parsing, filesystem path lookup, allocator work or handleEnvelope/license/native handlers. Their elapsed time is accounted for by checks at the surrounding boundaries, but an opaque call can overrun before returning. The 1000-ms server window begins when the accepted descriptor enters handleClient, not at client send time; backlog delay and a sender's absolute deadline are not propagated in the wire protocol. A queued complete request may still execute after its client has timed out. Once a handler begins, closing/timing out a socket does not undo its effects. No automatic command retry or durable exactly-once claim is introduced. Request expiry/cancellation propagation and concurrent admission remain P0-12 work.

## Framing and size compatibility

The JSON body of each envelope is limited to exactly 1 MiB, excluding the terminating LF. The bound includes envelope fields, so native payloads need room for their metadata; a result at its separate 1-MiB replay ceiling may not fit the transport envelope. Outgoing client frames reject before connect; incoming oversized frames reject before parse/dispatch. A server response exceeding the limit is replaced by a small correlated frame_too_large protocol error, never a truncated response. Sending an oversized native-response command from the client is rejected locally; it does not roll back an already completed native effect or acknowledge delivery to the helper.

Normal peers continue writing one compact JSON envelope followed by LF. Preserve the legacy one-command EOF frame for peers that half-close their write side: only explicit EOF may complete a nonempty unterminated frame, and the actual JSON parser still rejects truncated JSON. Timeout/error never substitutes for EOF. Only the first line is handled; trailing bytes are discarded with the single-command connection, preserving the former no-pipelining behavior. An empty frame fails.

The reader scans only newly received chunks, holds at most 1 MiB of body bytes, and checks capacity before append. This does not establish a 1-MiB RSS limit: vector capacity, conversion to NSData, parsed objects and serialization temporaries are additional. Removing copies or bounding Foundation's internal allocations is outside this slice.

## Validation

- Portable tests add 100k partial-read/write, EINTR/EAGAIN and frame round-trip cases; exact/oversized frames, legacy EOF, empty frames, slow trickle, persistent interruption, stalled readiness, partial/fatal/zero writes, SIZE_MAX output rejection, invalid/clamped/saturating deadlines and unchanged absolute budgets.
- The POSIX branch adds actual Unix connect/accept, socketpair framing, peer-close without SIGPIPE, real backpressure/read timeouts, missing/oversized paths and idempotent descriptor cleanup. This branch is not compiled or run on Windows.
- The macOS fixture compiles the actual client implementation and server handleClient/error-envelope methods with the shared transport and real protocol serializer. It exercises 54 AF_UNIX exchanges, bound-helper/request mismatches, oversized response fallback, client preflight limits, silent-peer timeout, no dispatch of a valid-but-unterminated timed-out prefix, EOF compatibility, malformed EOF rejection and exception/descriptor cleanup. Handler behavior is a controlled fixture; the complete JavaScriptCore/license server is not run.
- Source guards require shared-deadline connect/write/read, prepare/finally-close, pre-dispatch expiry checks, explicit response-size failure and both workflow runner entries. All 60 workflow runners (36 source-contract, 24 native), 521 source-grep assertions, standards-conforming assert preprocessing and git diff --check pass on Windows; 16 artifact-only checks need CI outputs. Actual POSIX/Foundation/ASan/UBSan, iOS builds and device qualification await CI/device on this Windows host.

## Acceptance and next slice

Build rootfull/roothide and run helper traffic under slow/closed/stalled peers. Verify request prefixes do not dispatch on timeout, oversized frames return explicit failures, identity/replay policy survives failed delivery, and descriptors close on setup/parse/handler/error paths. Exercise native replies near the envelope ceiling and document delivery ambiguity after effects. Measure actual I/O/cancellation latency and allocation overhead separately from handler time and polling delay.

Continue P0-12 with bounded concurrent client ownership, request expiry/cancellation propagation, event wait generation/cursors and reconnect ordering while preserving the one-slot identity gate and no repeated native effects. P1-40 invalidation, remaining P0-13 adapters and C01/C02 performance/device acceptance remain open.

The user reported C02d2 build `d89c4d3` passed before C02d3. Bounded concurrent helper clients are tracked in `IMPLEMENTATION-C02D3.md`; no independent macOS/device execution was performed on this Windows host.
