# C06f — shared refresh decisions and combined lifecycle diagnostics

Date: 2026-10-31 (Asia/Bangkok). Baseline: `b31c2d10`; user reported C06e build passed and asked to accelerate implementation. This checkpoint groups **P1-75** and part of **P1-77**, with refresh-result identity and exception cleanup. Shared application coordinator for rootfull/roothide and production TrollStore; TouchPOC excluded.

Status: source validation on Windows. New complete current/frozen Foundation/GCD/ARC/ASan/UBSan runtime requires macOS CI; device qualification remains independent.

## Refresh admission and decisions

Reserve the existing refresh single flight before localStatus, policy and backoff evaluation. Only its leader is dispatched to a dedicated serial decision queue. Followers join the pending completion array immediately without another localStatus call or decision job. The initial verifier work therefore leaves the caller/main thread, and automatic/manual/background callers share the same pending decision and eventual result. In-memory requestInFlight now covers decision work as well as the manager request, so activation/deactivation/remove/repair can report busy earlier.

Automatic policy, six-hour window, offline-grace handling and backoff formulas retain their prior source. A manual force joining a pending automatic decision sets a force flag under the coordinator monitor. A skip is committed under that same monitor only if no force was requested. Check again after either policy or backoff refuses: a force arriving during either check promotes the shared flight to a manager request. A force arriving after a committed skip starts a fresh flight. The leader retains trigger/lease-before metadata; a promoted attempt records manual_force_refresh. A follower that previously would have skipped independently now receives the shared flight's result, including its failure.

Refresh admission initially reserves only memory state. Persist the original in-flight and attempt fields together when an attempt is chosen, then post the existing initial notification. A skipped flight combines its decision and terminal fields into one write and delivers every joined completion asynchronously on main. Final skip files now explicitly include request_in_flight=false and operation=none. An opaque pending decision is visible through requestInFlight before the persisted attempt/notification; skipped flights retain their previous no-notification behavior to avoid an extra UI-triggered status verification. These timing/schema additions are deliberate. Other operation admission and public APIs retain their existing source.

Each refresh flight has an object identity. Only the first manager callback for that identity can enter coordinator postprocessing. Duplicate or retained old callbacks cannot re-read status, append history, publish a change or clear a newer flight. The identity remains active until postprocessing/terminal delivery has been scheduled. Synchronous decision/request NS/C++ faults and result-processing faults close that flight with license_refresh_exception and release joined callbacks for recovery. If a result already claimed the flight, a concurrent exception unwinding the initiating manager call cannot close that result's work; only its owner can finish it. This does not undo a lease the manager already saved.

## Diagnostics and history

Use one synchronized read/modify/write helper for diagnostic values plus an optional refresh-history event. Retain the path, mode, updated timestamp, atomic Foundation writer, twenty-entry cap, ordering and event fields. Append history directly from the loaded plist instead of calling the public diagnostics method, avoiding unrelated UI/performance snapshot enrichment and a second read. Failure counter/backoff calculation and its associated event are serialized under the same coordinator monitor.

Combine refresh success/failure values with their history event. Combine refresh begin/attempt fields, and skip decision/finish fields. In the new fixture, with authority publication controlled, a network attempt is expected to use three diagnostic transactions versus five in the frozen coordinator; a skipped decision uses one in both. These are Objective-C RMW-boundary counts, not measured Foundation/POSIX syscall, allocation, latency, power or device improvements. UI snapshot, daemon reload, lifecycle-trigger timestamps and other independent diagnostics still write separately. There is no new cross-process lock, cache, delayed flush, durability guarantee or file-size bound.

## Verification

Both workflows add check-license-lifecycle-safety.mjs. The full normalized preceding coordinator is frozen with SHA-256 `652cac70147534280d3074e9f125a9a4c3caa22e44e6ed7ac65fcff849061290`. Scoped reversal preserves complete UI snapshot/cache, policy/backoff, public lifecycle/activation/deactivation/recovery and daemon reload/publication source outside the explicitly changed sections. LicenseManager, HTTP transport, signed proof, save/validation/checkpoint and runtime feature authority are unchanged.

The new native fixture compiles complete current and frozen coordinators. Use real private temporary plist IO and controlled manager/status, authority publication, clock/jitter and socket adapters. No real lease, Keychain, HTTP request, daemon, feature policy or installed diagnostics file is changed. Cases include:

- Twenty-four frozen automatic/forced, valid/far/invalid/offline-grace/no-expiry/backoff and success/failure result/metadata/history graphs. Final terminal skip fields are normalized explicitly rather than pretending the old file already contained them.
- Initial current decision off main; three held-decision bursts with 65 callbacks and one initial status read, including a forced follower; force arriving during a negative policy or active-backoff check.
- Stale callback during a newer flight, duplicate result while its first post-verification is held, exact-once publication and callbacks.
- NS/C++ faults in initial status, request submission and result status with recovery; inline result followed by an exception; a held async result retaining ownership when the initiating request unwinds with NS/C++ exceptions.
- Frozen activation/deactivation failure metadata, earlier busy refusal without verification, remove/repair gates during decision and subsequent recovery.
- Exact serial twenty-entry history parity, no performance-snapshot reads during current history appends, concurrent below-cap appends, capped concurrent history and 128 further refresh lifecycles.

Windows validation: all **74 workflow runners** (36 source, 38 safety), **521 existing source checks**, JavaScript syntax, expanded assert preprocessing and git diff --check pass. Sixteen artifact-only checks are skipped. The new Foundation/GCD/ARC/ASan/UBSan assertions and transaction-count expectations have not executed on Windows and need macOS CI.

## Remaining work

HTTP refresh is shared by background, foreground and manual callers. Cancelling it when one BGTask expires would affect other consumers; per-subscriber cancellation/ownership must precede transport cancellation. This checkpoint leaves that work open and does not change C06d/e's terminal/queued-ensure gates. Manager requests, decision verification, disk IO and callbacks have no new end-to-end deadline or admission cap; a manager that never replies can still hold a flight. An already admitted supervisor ensure can still act after task expiration.

The exception handling targets provider/decision/result faults, not arbitrary failure of allocation, terminal diagnostic writing or user completion code. No rollback of committed signed artifacts is added. Initial verification is coalesced per flight without a long-lived status cache; subsequent independent calls verify again, and the UI snapshot path remains independent. Remaining diagnostics IO, cross-process coordination, crash recovery, active supervisor cancellation/coalescing, private backend polling and device/performance qualification stay open. P1-75 has source implementation pending native/device confirmation; P1-77/C06 remain partial.
