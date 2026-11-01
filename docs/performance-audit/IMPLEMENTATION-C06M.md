# C06m — bounded private profile creation verification

Date: 2026-10-31 (Asia/Bangkok). Baseline: `de8184ee`; user reported C06l build passed and requested continued implementation. This checkpoint addresses another bounded part of **P1-67** in production TrollStore private legacy VPN creation. TouchPOC excluded.

## Verification work and ownership

Previously, the creation-verification loop performed up to fifty complete configuration enumerations and slept 100 ms between them. Enumeration/comparison time was additional to those sleeps. Every attempt also materialized a new array of records with identifiers absent from the initial snapshot.

Keep fifty as the maximum attempt count and add a five-second continuous-clock window for the verification phase, starting after the successful create call returns. Each enumeration, candidate comparison, pool drain and inter-attempt wait consumes that same window. Check before a new attempt and again after each snapshot; a candidate discovered at or after expiry is discarded before profile selection or marker persistence. Invalid/regressed/overflow clocks fail closed through the existing `vpn_private_create_verification_failed` result. Retain the latest observed count and actual attempts in its existing fields.

Retain exact-name priority. If there is no exact-name match, retain the first new-identifier record and count all such records, accepting only a count of one. This avoids allocating the temporary delta array while preserving ambiguous and duplicate-record rejection. It does not change the underlying full enumeration or cache dynamic configuration lists.

Use an autorelease pool around each snapshot/comparison. The selected record is retained outside that pool for the existing selection/marker/old-profile cleanup sequence. Temporary arrays and nonselected records can drain between attempts; no device memory reduction has been measured.

## Main-thread publication and preserved behavior

Reuse C06l's remaining-interval policy with a separate creation adapter. Main-thread waits continue to run the existing current run loop so VPNPreferences can publish new services. If the run loop returns early, wait only the rest of the 100 ms interval before another enumeration. Off main, retry the remaining interval after EINTR; a fatal sleep error stops verification with the existing failure envelope. Pause/date temporaries also have a scoped pool. Neither early return nor interruption renews the five-second window, and the final wait is capped to remaining time.

Full-source reversal guards preserve create options, protocol/name normalization, initial identifier snapshot, the create call, result fields, marker persistence, old-owned-profile deletion, all private cleanup/transition and public NEVPNManager source. C06l's transition policy is unchanged except for a comment generalizing its shared window description. No frozen source fixture is edited.

The verification budget intentionally starts after creation; it does not preempt or budget the opaque create call, preflight, queue residence, profile selection or persistence. A slow enumeration/run-loop API may return after expiry; its candidate is then refused. The run-loop API still accepts a wall-clock NSDate for each short pause, so the continuous deadline is enforced between opaque calls rather than by preemption. A profile created but not safely verified may remain unclaimed, as in the previous verification-failure policy; this change does not guess ownership to delete it. The separate cleanup loop/publication delay, caller cancellation, polling backoff/full-list enumeration and async queue ownership remain open. P1-67/C06 are partial.

## Verification

Extend the existing private-polling runner; runner count remains unchanged. A new staged reversal restores only the verification loop and adapter, verifies the complete preceding C06l manager SHA-256, then executes the preceding C06l/public-transition guards. Both production workflows already invoke this runner.

The portable C06l window/wait suite still covers 100k windows, duration/clock/overflow bounds, early/interrupted/fatal waits and consumed work. The new macOS Foundation/ARC/ASan/UBSan fixture compiles the actual current complete configure function/adapter and frozen previous function with controlled store, clock, UUID, sleep and run-loop adapters. It compares both store schemas, exact-name/single-delta/ambiguous/duplicate/existing/empty/nil lists, delayed publication, create options and replies, preflight/selection/marker errors and old-owned-profile deletion. Additional cases verify expensive/late snapshots cannot select or persist, fifty-attempt and invalid-clock boundaries, early main publication/EINTR/fatal waits, NS/C++ unwind/recovery and record/result lifetime across pools. The actual status-fields formatter is extracted unchanged. No real VPN, profile, marker or installed state is changed.

New Apple execution and iOS builds require macOS CI/device qualification. Counts and controlled timing assertions are test evidence, not device performance measurements.

Windows validation passes all **76 workflow runners** (36 source, 40 safety), **521 existing workflow source checks**, staged complete-manager/public-transition hashes, JavaScript syntax, fixture extraction, expanded assert preprocessing and `git diff --check`. Sixteen artifact-only checks are skipped. The new Foundation fixture has not been compiled or executed on this host.
