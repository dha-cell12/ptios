# B05 — license snapshot, artifact cache and RAW authorization

Date: 2026-10-17. B05a baseline: `303b5be`; B05b baseline: `992a43a`. The user reported corrected B04 and B05a builds passed before their following slices. Device performance qualification remains pending.

Status: **B05a/B05b source implemented; new B05b macOS/iOS build and device acceptance pending.** Production rootfull/roothide and the shared TrollStore verifier remain in scope; prototype TouchPOC is excluded. Next group: **B06**. OCR remains C01.

## Snapshot and refresh — B05a

P0-24/P1-15: full verification runs on one independent serial worker. The snapshot mutex covers only memory metadata and publication; it does not cover file reads, JSON, crypto, Keychain, checkpoint updates or authority exchange. Both root enforcement boundaries remain active. Root denial formatting uses the cached status instead of making a second synchronous authority request.

Snapshots expire **5 seconds after refresh request start** and refresh proactively at **4 seconds** while active. Verification lasting 5 seconds cannot create a newly fresh result. Invalidation epochs and generation reads before/after verification reject obsolete results; the returned status generation must also match. Notification invalidation clears the snapshot without queueing behind the verifier worker.

P1-71: an independent generation timer polls every **250 ms** with 25 ms leeway. Snapshot use requires a completed observation at most **500 ms old**. It disarms after **10 seconds without a lookup** and resumes on demand. This introduces bounded background work during activity and its idle tail, including between H264 heartbeats; no measured energy improvement is claimed. Generation zero remains a possible missing/initial hint and does not replace cryptographic verification.

A cold/stale gate waits at most **3 seconds**, releasing the mutex through a condition variable. At most **16 callers** may wait; excess/timed-out callers fail closed with `license_verification_pending`. A nil/unavailable snapshot never authorizes a call. A published observe-mode status retains its previous allow behavior. Enforced licensed lookups also check offline/license expiration and the existing 300-second rollback tolerance against current wall time, rejecting non-finite metadata. Lease renewal expiry still permits valid signed offline grace.

P1-72: root authority admits at most **8 clients before dispatch** and closes excess connections. A finally block closes admitted FDs and releases capacity, including early returns.

## Immutable configuration and signature artifacts — B05b

P1-73/P2-27: a single parsed configuration entry is cached by exact file bytes, selected path, generation and invalidation epoch. Discovery of candidate paths and reading current bytes remain fresh. Deletion, malformed content, replacement at the same path, and same-size/same-timestamp rewrites cannot return an old cached dictionary. Parsing happens outside the artifact mutex; stale work cannot insert after invalidation.

A separate single-entry cache stores only a **successful server signature verification**. Its identity includes immutable copies of payload/signature bytes, both server public-key coordinates, key ID, build mode, generation and epoch. Failed verifications are not cached. A generation/epoch change during verification prevents insertion. Changes to bytes, signer/configuration, key ID or build mode require another verification.

Each cache admits at most **1 MiB of input bytes**; signature-key text fields also have a 4096-unit admission ceiling each. Larger inputs still follow the existing uncached verification/parsing path. These are cache admission limits, not rejection limits or process RSS guarantees. The cache does not retain SecKey references.

Both the local lease verifier and the authority client's lease-anchor check use this signature artifact cache. Device public-key binding/possession, product/contract checks, signed time limits, features, release integrity and signed anti-rollback checkpoint validation remain at their existing call sites. Keychain access/device signatures and checkpoint updates remain fresh. Invalid server-key configuration retains its prior error behavior and does not incorrectly quarantine a lease as a bad signature.

Authority requests still generate a fresh nonce; every returned nonce-bound status signature, nonce and proof time window are verified. The authority response/client transport implementation is unchanged. A cached lease-signature result is not a reusable authority response or an authorization decision. Crypto remains outside both cache mutexes. Concurrent cold callers can independently verify the same artifact; this slice does not add a crypto single-flight queue for fresh diagnostics.

## RAW session automation view — B05b

P0-02: RAW preparation creates one capability callback bound to a unique session owner and its cancellation token. Dense **task 10 touch** and **task 18 delay** use a numeric immutable view of the currently published license status. The view checks owner, current epoch, snapshot/probe ages, current automation permission, offline/license expiration and clock rollback. It avoids the ordinary snapshot dictionary/mutex and task-feature NSString construction for those successful fast checks. C++ shared-pointer atomic loads may use an internal lock; this is not a lock-free claim.

A missing, expired, revoked, mismatched or unavailable fast view falls through to the original full task gate. Other RAW tasks keep their ordinary gates. The 1-second script heartbeat and daemon/SpringBoard boundaries remain active; a RAW session does not hold a permanent grant. The heartbeat keeps generation polling/refresh active during playback.

Child contexts copy the capability and owner. Cancellation prevents copied callbacks from authorizing later work. Final completion retires the cancellation token and clears the parent capability before idle, so normal completion also disables stale copies. Owned touch-UP cleanup still executes through its existing cleanup path.

## Explicit diagnostic freshness — B05b

P1-78: read tasks **60, 75 and 97** accept the body `cached` in root and production TrollStore paths. For example, a legacy request is `75cached\r\n` (actual CR/LF on the wire); JSON clients use task 75 with body `cached` through their existing task encoder. Whitespace/case normalization is supported.

The default/empty body and `fresh` retain synchronous fresh status behavior. Task **76** retains reload/advance mutation plus fresh verification; it does not become a cached read. Authority responses also remain fresh.

Cached mode returns a memory status or a fail-closed pending/expired view, marks JSON license status with `diagnostic_freshness=cached` and `snapshot_max_age_ms=5000`, and retains the original verification timestamp when available. It can schedule background refresh but does not perform foreground license verification/generation reads. Task 97 advertises `licenseFreshness=cached`; root framing still contains exactly one terminal CR/LF. Cached task 75 takes generation fields from that snapshot, using zero when unavailable, rather than rereading disk.

For task 60, this mode applies to its **license portion**. Other device/VPN/history/status work retains its existing behavior and may still perform I/O or serialize on its own queues. Cached mode does not promise the entire diagnostic task is I/O-free. No legacy status is silently made stale.

## Metrics and validation

Metrics version **3** retains existing fields and adds configuration/signature cache hits/misses, cache admission policy and RAW numeric check attempts. `cache_miss_count` remains the B05a alias for completed background refreshes (`completed_refresh_count`), not the number of synchronously refreshing feature calls. `cold_check_count` is separate; feature latency includes bounded cold waits. No per-record production logging is added.

Windows validation passes **36 source-contract checks**, **11 native runners A01–B05**, and all **528 static-file grep assertions** in the TrollStore workflow using GNU grep. The B05 portable core covers exact TTL/probe/refresh/time boundaries, 100,000 numeric-view checks, 80,000 invalidation cycles and 120,000 concurrent authority admission attempts. Existing touch, playback, budget, socket and H264 regressions remain green.

The macOS ASan/UBSan branches added to both workflows compile actual production code with:

- Foundation/dispatch snapshot publication, blocked refresh, independent probing, stale epochs/generations, bounded cold waits, expiry/observe behavior, idle disarm/resume, owner-bound numeric callbacks and explicit diagnostic selection. Verification/generation providers, notification registration and the monotonic clock boundary are controlled for these concurrency cases.
- Actual root 75/76/97 and TrollStore 75/76 diagnostic adapters, real JSON/base64/text framing and counters that detect foreground verifier/generation calls. Task 60 and TrollStore 97 selection are source-wired; their full UI/device dependency trees are not compiled by this fixture.
- Actual configuration/signature-cache helpers with **real ephemeral P-256 keys and Security-framework signatures**. Only the signature-call boundary is delayed/counted; it still executes real verification. Cases cover invalid signatures, altered payload/signature/key/key-ID/build/generation/epoch, mutable inputs, late insertion races, oversized uncached verification, real plist replacement/deletion and same-size/same-mtime edits.
- Actual playback session code with controlled runtime hooks, capability-owner checks, cancellation, retirement after completion and restart isolation. Native task bodies remain doubled in that player fixture.

These new macOS branches have not run on this Windows host; they and final iOS artifacts require CI confirmation. The existing B05a fixture reached a later obsolete grep assertion in the user's TrollStore build; that assertion was corrected to the new generation/epoch policy, and the user subsequently reported build pass. B05b adds new code beyond that accepted build.

## Device acceptance and limits

1. Build rootfull/roothide and production TrollStore with the new macOS branches enabled. Exercise signed activation, expiry, revocation, offline grace, configuration/key changes, anti-rollback failure, missed notifications, authority outage/recovery and cold-start overload. Confirm no stale result or callback restores authorization.
2. Run high-rate RAW touch/delay playback, arbitrary other RAW tasks, stop/repeat/restart and JS transitions while changing features/generation. Verify cancellation and balanced touch cleanup, including retained child contexts.
3. Compare default/fresh diagnostics against prior responses. Exercise `cached` for 60/75/97 before warm-up, during blocked verification, at expiry and after invalidation. Confirm read 75/97 does not perform foreground license I/O; task 76 still mutates and verifies fresh.
4. Rotate/rewrite config, lease and device-key files, including same-size/mtime changes, and interrupt refresh during mutation. Device proof and checkpoint validation must remain fresh despite signature cache hits.
5. Measure hot/cold latency, allocations, verifier contention, full-verification/cache-hit counts, generation/config reads, RAW timing and energy against B05a. Signature/config caches reduce repeated parsing/crypto opportunities; they do not remove current file reads or prove an end-to-end CPU/RSS/energy improvement.

Authority admission bounds FD/worker count, not opaque verification/Keychain duration. Its existing per-call socket timeout can still be extended by a trickling peer; absolute service I/O deadlines remain follow-up hardening. Saturating eight authority clients can deny availability without creating unbounded workers. The single verification or generation worker is not forcibly cancelled; expired views fail closed while it is stuck. Snapshot and artifact locks are short, with no hard scheduler-latency guarantee. Fresh diagnostics can still perform synchronous work. No persistence, anti-rollback, lease/checkpoint transaction or capture backend contract is changed.
