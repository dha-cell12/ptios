# B05 — license hot path: snapshot and admission foundation

Date: 2026-10-17. Baseline: `303b5be`. The user reported the corrected B04 build passed before this group. B04 device performance qualification remains pending.

Status: **B05a source implemented; new macOS/iOS build and device checks pending. B05 is not yet fully complete.** This slice establishes the refresh/invalidation boundary before changing cryptographic artifact caching or diagnostic freshness. Production rootfull/roothide and shared TrollStore verifier paths are included. Prototype TouchPOC remains excluded.

## Implemented scope

- **P0-24:** full verification/authority refresh runs on one independent serial worker. A short snapshot mutex no longer covers file reads, JSON, crypto, Keychain, checkpoint operations or authority exchange. At most one refresh is outstanding; notification/invalidation cannot wait behind that worker.
- **P1-15:** both daemon and SpringBoard enforcement boundaries remain active and use the shared memory lookup. A denied root task/component formats its response from the nonblocking cached status instead of issuing a second fresh verification.
- **P1-71:** generation reads move to an independent active-only timer queue. They cannot be held behind an authority request on the verification worker.
- **P1-72:** authority admission is capped at **8 clients before dispatch**. Rejected connections close immediately. A finally block owns accepted-client close and admission release across the complete handler, including early returns.
- **P0-02, partial:** RAW keeps every task gate and heartbeat; warm per-line calls now read memory rather than performing generation/crypto/I/O work. A distinct session authorization/token and its per-line lookup reduction remain follow-up work.

## Freshness, invalidation and cold behavior

The existing fully verified status remains the sole source of access decisions. Local verification still runs release integrity, device binding/possession, signed lease validation and signed anti-rollback checkpoints. Authority clients still generate a new nonce and verify its signed response on each actual refresh; no signed envelope is replayed for another request.

The snapshot has a **5-second monotonic maximum age measured from refresh request start**, with proactive refresh at **4 seconds** while in use. Verification that itself takes 5 seconds or more cannot publish a newly fresh snapshot. Captured invalidation epochs plus generation reads before/after verification reject results from obsolete work. The verified status generation must also match the generation read after verification. A notification clears the snapshot immediately under the short mutex; it does not synchronously dispatch onto the verifier queue.

The independent generation timer runs every **250 ms**, with 25 ms leeway, while recently used. A usable snapshot requires a completed generation observation no more than **500 ms old**. Notifications are an early invalidation hint; polling is the fallback for missed notifications. Generation zero retains its prior meaning as a possible missing/initial generation value; it never replaces signature verification. Filesystem latency and notification delivery still need device qualification.

The timer disarms after **10 seconds without a snapshot lookup** and resumes on the next lookup. This trades bounded background work during an active session and its short idle tail for proactive verification between 5-second H264 heartbeats. There is no permanent idle timer polling. This is not a measured energy improvement.

A warm valid snapshot returns without waiting for refresh. A cold/stale check may wait up to **3 seconds**, releasing the mutex through a condition variable; at most **16 callers** may wait. Additional callers and timed-out callers receive `license_verification_pending` and fail closed. There is no implicit allow for a nil or unavailable snapshot, including a cold observe-mode process whose configuration has not yet been verified. An actually published observe-mode status retains its existing allow behavior.

Every enforced licensed lookup also checks the signed offline/license-expiration limits against current wall time and rejects non-finite values or rollback beyond the existing 300-second tolerance. Lease renewal expiry alone does not remove the existing signed offline grace. Monotonic snapshot/probe ages remain independent of wall-clock changes. The full verifier/checkpoint path still runs at refresh.

## Diagnostics and metrics

`TLinkLicenseCachedStatusDictionary()` is a nonblocking memory view. It can schedule refresh but returns a fail-closed pending/expired view when access cannot use the snapshot. It does not replace the public fresh `TLinkLicenseStatusDictionary()` contract.

Fresh task 60/75/76/97 diagnostics and authority responses retain their existing fresh verification behavior and may still perform synchronous I/O. This slice changes only root denial formatting to use the cache. No legacy diagnostic response is silently made stale.

Metrics version 2 adds `completed_refresh_count`, `cold_check_count`, refresh/freshness/waiter policy fields and the idle-stop policy. The legacy `cache_miss_count` now aliases completed background refreshes; it is no longer a count of feature calls that synchronously refreshed. `cache_hit_count` counts feature checks that began with a usable memory snapshot. Feature latency includes cold waits; refresh latency includes the existing full verification path. Existing field names remain available for clients.

## Verification

All **36 existing source-contract checks** and **11 native runners A01–B05a** pass on Windows. The new policy/admission runner compiles with MSVC warnings as errors and covers exact snapshot/probe/refresh boundaries, late epochs/generation races, slow/nil verification, signed expiry/rollback/non-finite metadata, **80,000** invalidation cycles and **120,000** concurrent authority admission attempts. It verifies no more than eight admitted owners and balanced final release. Existing enforcement/authority/anti-rollback contract checks remain unchanged.

Both production workflows include `check-license-hot-safety.mjs`. Its macOS ASan/UBSan branch compiles the actual snapshot adapter, metrics and shared policy with real Foundation, mutexes, condition variables, queues, timer events and threads. Only the full verifier/generation provider, notification registration and monotonic clock boundary are controlled. It exercises a blocked refresh with 20,000 hot reads, independent probes, stale/notification/generation rejection, signed-status generation consistency, bounded cold waiters, recovery, time expiry, observe mode, idle timer disarm and resume. Clock progression is controlled during the hot-read stress section to avoid scheduler-speed-dependent expiry assertions.

This new Foundation branch has not run on this Windows host. It doubles the cryptographic verifier/authority provider and does not validate signed envelopes or real Keychain/device/checkpoint behavior. The authority admission core is stress-tested; the final service accept/handler wiring is source-checked and requires artifact/device validation. No iOS latency/CPU/RSS/energy claim is made.

## Remaining B05 work and acceptance

1. **Build and runtime acceptance for B05a:** run rootfull/roothide and production TrollStore artifact builds plus the new macOS integration. On devices exercise cold start, 5-second H264 and 1-second script heartbeats, RAW high-rate playback, refresh failure and recovery, authority unavailable/slow, generation changes with lost notifications, revoke/expiry, configuration changes and anti-rollback failure. Confirm gates remain active at both root process boundaries and stale work cannot restore authorization.
2. **B05b / P1-73 + P2-27:** cache immutable configuration and verified artifacts with explicit generation/key/build invalidation, while retaining fresh per-request nonce signatures and required device/checkpoint checks. The full verification body and authority exchange are unchanged in B05a.
3. **B05b / P0-02:** decide and test the RAW session authorization contract. The current per-line gate remains, with its warm lookup made cheaper.
4. **B05b / P1-78:** provide explicit diagnostic snapshot/freshness modes and review serial response work; keep legacy fresh behavior until that contract is defined.
5. Measure warm/cold latency, verifier queue contention, full-verification counts, active/idle generation I/O and energy on identical devices/workloads before and after.

Authority admission bounds FD/worker count, not the duration of opaque verification/Keychain operations. Its existing per-socket receive/send timeout can still be extended by a trickling peer; absolute service I/O deadlines remain follow-up hardening. Saturating all eight admitted clients can deny availability without creating unbounded workers. Cold callers have a bounded wait, but the single verification or generation worker is not forcibly cancelled; expired snapshots fail closed while it is stuck. The snapshot mutex is short, not lock-free, and does not provide a hard scheduler-latency guarantee.

Next implementation slice: **B05b**, then B06. OCR remains C01.
