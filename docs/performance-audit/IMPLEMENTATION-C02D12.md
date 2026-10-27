# C02d12 — read-only recovery of a lost accepted-start reply

Date: 2026-10-27 (Asia/Bangkok). Baseline: `3bc4832`; the user reported the corrected C02d11 build passed.
Status: **build reported passed by the user before C02b23 (`c3f2443`); device qualification pending**.
Finding: **P0-12, bounded unknown-start recovery**.

## Result and contract

The rootfull/roothide client sends start once, using its generated UUID as the wire request ID and opting into startReceiptContract: accepted_start_v1. A local read_failed, write_failed, empty_frame or io_timeout can trigger one fresh, read-only status query with that original startRequestId, provided time remains. Start itself is never resent. Successful ordinary start replies require no additional lookup/socket.

The helper retains metadata for one accepted, opted-in start. A receipt contains its contract and a canonical start envelope: helper instance, original request ID, session ID and a starting/activeSessionId/runId payload. This is an acceptance record, not a current lifecycle snapshot. There is no script, manifest, native result or error/log text, growing collection or file persistence. Fixed server UUIDs and the bounded incoming request ID bound its size.

Prepare metadata before worker reservation so allocating it cannot add a reservation-without-execution failure path. Following existing license/busy/session admission, publish the receipt under rpcCondition before enqueuing execution. Denied/rejected starts do not replace it. Completion/retirement preserves it; every successful new session reservation, including a legacy start, clears it under that owner. Helper restart loses it. Production command ownership serializes start and lookup; lookup never enters start or execution.

An extended status query checks the exact accepted request ID and current session under rpcCondition, retains the immutable receipt locally, then constructs output outside the lock. Held receipts remain safe after replacement. Missing/different/replaced/restarted receipts return start_receipt_unavailable, which is not proof that a script never ran. Ordinary status behavior remains unchanged.

## Client validation, timing and compatibility

The query gets at most 500 ms, shortened to the original public start call's remaining time. Start and query sender deadlines are clipped to that original absolute expiry, including preparation between requests. The initial attempt keeps its full budget; a full-budget timeout cannot recover within this call. There is one query without polling/retry.

Only local whitelisted I/O failures enter recovery. Remote errors, cancellation, malformed/correlation/ownership errors, serialization/output limits, connect and setup failures do not. Failed lookup preserves the original uncertain-start failure and fallback fence. Existing definitely-safe connect/setup or helper-busy fallback behavior remains.

Before adoption, validate the outer status through the existing codec/correlation path, then the strict receipt schema/contract, canonical nested start command, original request ID, matching outer/nested helper, existing helper pin if present, session/activeSessionId ownership, bounded run ID and deadline/cancellation again. Errors, leases and noncanonical or extra fields are rejected. Pin the recovered helper and return startRecovered with the minimal accepted-start envelope. The runtime enters its existing fresh pinned status/native ownership/replay loop; the receipt alone never authorizes a native effect. Optional console paths can be absent, as with an ordinary starting acknowledgement.

Caller cancellation and the parent budget are now installed before initial start, covering that I/O and the optional query. Existing post-start cancellation, independent cleanup stop, connection reuse and owned-resource cleanup remain.

Old clients keep unextended start behavior. Old helpers ignore the start extension, so successful replies still work. If an old helper treats the query as ordinary status, strict receipt validation rejects the payload and the unknown outcome remains an error. Neither mixed-version path repeats execution.

## Verification

- All 62 workflow runners (36 source-contract, 26 native), 521 direct workflow source-grep assertions and standards-conforming assert preprocessing pass on Windows. Focused helper identity/transport runners were repeated after final publication changes. Sixteen artifact-only checks require CI outputs.
- Portable coverage adds 100000 original-window/lookup-budget cases, invalid/exhausted/max/saturated boundaries and the 500-ms cap without deadline renewal.
- The actual macOS client/socket fixture adds a lost accepted reply followed by the real lookup/owner/socket path and pinned status. It checks shared sender expiry, one start only, old-helper/unavailable/token/helper/session/schema/run/state/command/error/lease rejection and cancellation while reading. Business dependencies remain controlled in this transport fixture.
- The separate actual session fixture covers production publication before execution, license/busy/contract rejection, terminal retention, repeated queries with one evaluation, bounded metadata, invalid IDs, legacy replacement/restart invalidation and a held receipt after replacement. The actual runtime-loop fixture adds cancellation during start and retains its uncertain-start fallback cases.
- New Darwin/Foundation/ARC/ASan/UBSan branches and iOS/device tests cannot execute on this Windows host. No measured CPU, RSS, energy or latency improvement is claimed.

## Remaining qualification

The user reported build `c3f2443` passed before the next P0-13 adapter slice, `IMPLEMENTATION-C02B23.md`. This records the user report, without independent device/performance qualification on this host.

P0-12 remains partial. Full-budget timeout, no receipt, session replacement, helper restart or cancellation can still leave an unknown outcome. They remain errors without automatically running an in-process fallback or sending start again. The receipt is neither a durable execution journal nor an idempotency guarantee for a caller that explicitly submits another start.

Qualify owner/backlog contention, fast completion before ACK, lost replies, stop and restart on device. Existing opaque work and OS scheduling retain cooperative bounds. P0-12 transport/performance acceptance, other P0-13 adapters and P1-40 invalidation remain open. TouchPOC and production TrollStore execution source are unchanged; both workflows exercise the shared suites.
