# C06ab — UI snapshot recovery and pending handoff

Date: 2026-11-04 (Asia/Bangkok). Baseline: `d95af41c`; user reported C06aa build passed and requested continued implementation. Shared rootfull/roothide and production StreamControl coordinator; TouchPOC excluded.

## Single worker and pending updates

The UI snapshot worker could leave its single-flight flag set when verification/publication threw. It also cleared the flag before diagnostics, then re-entered the public method for an older pending reason. A trigger during that gap could enqueue an extra verification and cause the older pending reason to overwrite newer metadata. Empty pending reasons were silently dropped by a length check.

Copy each incoming reason before admission. Keep one worker/gate through publication, diagnostics and notification enqueue. At each pass, consume the latest pending reason under the coordinator monitor. Pre-start bursts therefore share the first verification. A change during a pass causes another pass in the same worker, with a per-pass autorelease pool. Retain the gate until no pending change remains, then clear it atomically under the same monitor. There is no public-method handoff gap or new job for each pass.

An empty pending reason now still requests a refresh, matching the public method's existing acceptance of empty initial reasons. Nil initial/pending defaults retain their preceding unspecified/coalesced values. Metadata reflects the latest request actually consumed, rather than replaying obsolete reasons. Continuing triggers can keep the worker active; there is no idle timer or new fairness/time bound.

## Failure and publication

Contain NS/C++ failures within each worker pass. If status preparation fails, keep the previous good snapshot (or initial loading snapshot), return the gate when idle and permit a future trigger. A pending change can still receive its follow-up pass after failure. There is no automatic retry without a pending/new trigger and no fabricated license/error status.

If snapshot publication succeeded, enqueue the existing UI notification even if later performance/diagnostics work throws. Preserve the snapshot fields/source, successful counter/elapsed/max updates, diagnostics keys, main notification payload, verifier call and all authority/HTTP/reload/publication/subscription code outside this method. The gate now describes the entire UI update flight, including diagnostics, rather than only status verification.

This remains UI state, not a runtime authorization decision. It does not cancel or preempt an opaque verifier/IO call, add an operation deadline, alter the diagnostics writer lock/durability policy or change wall-clock metric sampling. Queue residence, slow diagnostics, continuing-trigger workloads and device qualification remain open. C06/P1-77 stay partial.

## Verification

Freeze the complete preceding UI method. Restoring it verifies the full preceding coordinator hash before the C06v/C06p/C06o/C06g/C06f chain. Source guards require one UI-queue enqueue, a per-pass pool, immutable admission reason, pending-based gate release and ready notification after the guarded publication phase.

The native Foundation/GCD/ARC/ASan/UBSan fixture compiles complete current/frozen methods with controlled verifier/performance/persistence providers. It compares ordinary snapshots/diagnostics after normalizing elapsed metrics, verifies mutable-reason ownership and shows one rather than two verifications for 1,000 pre-start changes. A controlled status/diagnostics handoff shows two passes with the latest reason instead of the old three-pass stale-reason result. Other cases cover empty pending reasons, NS/C++ status/performance/diagnostics failures, old gate wedging, last-good retention, ready notifications and subsequent/pending recovery.

Thirty-two real GCD lifecycles hold the first provider while eight threads publish 256 updates. One worker must perform exactly two passes and deliver both main notifications. Transport/verifier/license/UI/persistence effects are controlled; no real license, authority, daemon or app state is modified.

Windows validation: all **87 workflow runners** (36 source, 51 safety), **521 existing workflow source checks**, full preceding-coordinator/earlier checkpoint hashes, fixture extraction, JavaScript syntax, expanded assert preprocessing and `git diff --check` pass. Focused UI/lifecycle/phase-5 checks pass. Sixteen artifact-only checks skipped. New Apple compilation/native execution/iOS builds require macOS CI. Fixture counts are expectations, not measured device gains.
