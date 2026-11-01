# C06j — coalesced pending TrollStore VPN status reads

Date: 2026-10-31 (Asia/Bangkok). Baseline: `c1c86d0a`; user reported C06i build passed and requested continued implementation. This checkpoint addresses another part of **P1-68** for production TrollStore brokers 6015/6016. TouchPOC excluded; rootfull/roothide broker behavior is unchanged.

Status: Windows source/portable validation. New actual broker/bridge Foundation/GCD/ARC/ASan/UBSan execution and iOS builds require macOS CI. No measured device performance improvement is claimed.

## Pending reads and independent waiters

Query and diagnostics call the same parameterless manager status provider. Route both through a process-local pending-read owner. A leader starts the provider; up to seven additional waiters join that pending flight. The first provider callback takes the waiter list once, clears current joinability and fans out the provider value outside the owner mutex. A callback fault is isolated so subsequent waiters still receive terminal evidence. Duplicate/stale provider callbacks cannot deliver again or clear a newer flight. The owner retains no completed result; the next read after completion starts a fresh provider call.

Each flight accepts joins for at most eight seconds from its initial continuous-clock admission. Followers cannot extend that window. Once it expires, a later request starts a separate flight while old provider work and old waiters retain their ownership. Reject invalid/regressed admission clocks. This join horizon is separate from every caller's existing eight-second phase and accepted-time thirty-second window; those budgets and completion closed-state gates remain unchanged. A parent-expired caller can discard its result while another still-live caller receives the same backend result.

The generic owner holds no socket or client lease. Production waiter callbacks retain only the existing completion state and pending-operation ticket. Each admitted waiter still consumes its original global operation quota until actual provider callback plus starter return. Coalescing reduces backend reads; it does not collapse eight waiter tickets into one. A lost callback can therefore consume up to eight slots as callers join/expire, conservatively retaining the preceding unknown-work policy. The eight-client/eight-operation caps bound production admissions across detached flights. The standalone owner bounds one flight to eight waiters and relies on that outer pending-work admission.

Provider starter NS/C++ unwind detaches only that flight's joinability, then rethrows through the existing caller boundary. It does not synthesize completion or release pending-work quota without evidence. A retained late callback can still retire those waiter tickets; a subsequent request can start a different flight if capacity remains. Clearing/taking/rejecting callbacks and dropping old flights release captures outside the owner mutex, including destructor reentry.

## Mutation boundaries and authority

Detach the joinable read when a broker connect/disconnect wins its mutation lane, before invoking the manager. Detach again on the first terminal mutation callback. Reads after either boundary start a fresh flight; reads already admitted can finish for their existing waiters. A duplicate mutation callback does not invalidate a later read. These barriers do not cancel backend work or promise an atomic connection-state snapshot across concurrent changes.

All per-caller foreground/license/entitlement checks, exemptions, diagnostics construction and reply formatting remain in place. Diagnostics and an independently authorized query may share the same pending read, but sharing does not grant admission to the query. C06i narrow preflight, full dynamic diagnostic fields, client/operation/mutation caps, phase/output deadlines and streamd fallback routing remain. Direct UI mutations, external VPN state changes and the other broker process do not share these barriers; cross-process coordination and backend cancellation remain separate work.

## Verification

Add the header-only pending owner and Objective-C bridge in `shared/TLinkVPNBrokerStatus.h`. Extend the existing TrollStore VPN runner with a portable core test, leaving the total runner count unchanged. A new staged reversal removes only the status wrapper/include/call routing and mutation invalidation, verifies both complete preceding broker hashes, then runs the existing C06i/C06h authority/IO/diagnostics guards. Native fixture extraction still compiles the actual current read wrappers and shared bridge, replacing only owner factories/providers/clocks for repeatable tests.

Portable cases pass on Windows: 100k flights with no completed-result reuse, eight waiters/ninth refusal, exact non-renewing join boundaries, invalid/regressed/near-limit clocks, old/new identities, mutation/detach barriers, callback/destructor release outside locks, owner lifetime and 256 concurrent eight-reader/duplicate-completion/invalidation races.

New macOS cases run separately for each broker:

- Eight real wait threads through the actual wait/read/bridge with one held manager request; both outer quota and inner waiter refusal; fresh read after completion and duplicate callback fencing.
- One caller expiring at its parent deadline while a fresh caller joins and receives the result. Retain/release an ephemeral result across pools and late callbacks. A full eight-second join horizon starts a separate backend read without allowing the older callback to clear it.
- NS/C++ provider starter faults before and after a terminal callback, conservative quota retention and late cleanup/retry; per-waiter NS/C++ callback isolation and nil completion.
- Actual mutation-start invalidation, a read during the mutation, terminal invalidation, old read completion and duplicate mutation callback while a newer read remains joinable.
- Retain C06h/i frozen reply/authority/metadata parity, fresh completed-query state, narrow admission, socket/queue/FD/fault matrices and mutation lane checks. No actual VPN, profile, radio, privileged helper or installed state is changed.

Windows validation: all **75 workflow runners** (36 source, 39 safety), **521 existing source checks**, JavaScript syntax, fixture extraction, expanded assert preprocessing and `git diff --check` pass. Console assertions passed on the first run, but temporary executable unlink hit EPERM; the focused rerun passed. Sixteen artifact-only checks are skipped. New Apple assertions, including the expected eight-to-one backend request count, await macOS CI and are not device measurements.

## Remaining work

P1-68/C06 remain partial. Workers still wait in bounded semaphore/poll slices, and provider starter/backend work cannot be preempted. This adds pending-read sharing, not a completed status cache, global mutation ordering, external-state invalidation, backend cancellation or fully asynchronous broker state machine. Uncontended reads add a small flight/callback allocation; the device tradeoff needs measurement. Private polling, cross-process fallback/deduplication, HTTP/active supervisor cancellation and device CPU/IO/RSS/power/latency qualification remain open.

## CI correction — 2026-11-01

User reported the portable status core aborting on macOS at the rejected-callback lifetime assertion (baseline `4c946416`). The test checked rejection and `released` in the same call expression, assuming the by-value parameter had already been destroyed and the moved-from std::function no longer held its capture. Those lifetime assumptions are not portable.

Check admission failure separately, then check `released` after both the call expression and the moved-from callback's scope have ended. Keep the destructor's reentrant `owner.invalidate()` call, the full eight-slot setup and the release assertion, so retained rejected captures or destruction under the owner mutex still fail the test. Production owner/bridge/brokers are unchanged.

The focused TrollStore broker runner passes source/frozen guards, 100k portable flights and 256 concurrent eight-reader/duplicate/invalidation races on Windows; `git diff --check` passes. A search found no other matching combined rejection/release assertion. Corrected libc++/macOS/sanitizer and Foundation execution still require macOS CI. This correction does not qualify C06m or device performance.

## Duplicate fixture declaration correction — 2026-11-02

User reported macOS compilation failing at the second `auto refused` declaration in coalescedStatusCases (baseline `fbb87a07`). The direct ninth-waiter refusal call and its assertion were duplicated verbatim in the same scope. Remove only the repeated pair. Retain the first direct refusal assertion and the separate outer pending-operation refusal check; no production source or warning policy changes.

The focused TrollStore broker runner passes source/frozen guards, 100k portable flights and 256 concurrent races on Windows; diff checks pass and the fixture now has one refused declaration. Corrected Objective-C++ compilation and execution for both broker variants still require macOS CI.
