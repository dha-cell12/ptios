# C05b — Monotonic AX snapshot deadline and late-result completeness

Date: 2026-11-04 (Asia/Bangkok). Baseline: `6148fc53`; user reported C05a build passed. Its documentation updates were already present and retained. Shared AX snapshots used by rootfull/roothide and production TrollStore; TouchPOC excluded. Addresses P2-22 and a bounded part of C05's snapshot/action timing.

## One local monotonic window

Snapshot timing previously used CFAbsoluteTimeGetCurrent for the deadline and duration. Clock changes could extend/shorten traversal or produce negative duration_ms. Deadline checks only before an element also allowed a final serialized node or empty root query to return after expiry with complete flags.

Use TLinkNativeNowNs, the existing steady monotonic clock shared with native caller budgets. Keep the existing 100–3000ms/default-1500ms normalization and start point after lock/preparation/options work, before root creation. One local window spans root creation/query and traversal. Cap the root messaging timeout by its remaining time as well as the existing caller remainder/500ms ceiling. If creation consumes the local budget, release the root and return the existing ui_cancelled_or_timed_out error without querying.

Check the same window before and after each serialized node. A node returning at/after expiry is discarded; report the scanned count and mark the snapshot truncated/partial. Check final completeness even for zero elements or an early filtered/row-cap exit. A late empty/final result therefore cannot satisfy the existing TLinkAXResultCompleteForAction predicate; Task 81 and wait-gone retain their existing incomplete-result guards. Read-only callers retain the successful partial-snapshot envelope and any previously accepted rows.

Use the monotonic elapsed interval for duration_ms; keep captured_at_ms as the existing wall-clock timestamp. Invalid, regressed or overflowing window clocks fail closed, with duration frozen at the last valid nonnegative observation. A final caller stop also returns the existing cancellation envelope, including when the last node was filtered. A shorter caller budget is never renewed or changed.

## Scope and limits

Preserve the complete symbol caches, numeric attribute serializer, filters, row/scanned/source/failure fields, option aliases, output accounting, screen/lock state, selector matching and foreground/action guards outside these timing/completeness changes. Existing ordinary successful replies retain their schema and formatting.

The local window excludes caller queue residence and lock/preparation work, as before; an inherited native caller deadline still covers its existing scope. This does not add active cancellation, hard RPC preemption, a scanned-element cap or per-attribute-group deadline checks. The existing serializer can issue several opaque attribute RPCs before the new post-node check sees expiry. Native steady-clock behavior is reused; no new continuous-across-sleep clock contract is introduced. Overshoot, full root materialization, selector early exit, strings/output and device qualification remain open. C05 remains partial.

## Verification

Freeze the complete preceding snapshot function. Exact reversal allows only the window/clock/query remainder and post-node/final completeness changes, validates the entire preceding AX hash, then chains C05a's full-source restoration. Both production workflows add check-ax-snapshot-safety.mjs.

The actual portable window passes 100k normalized-budget/remaining/elapsed cases, exact deadlines and overshoot, invalid ranges/sentinel/overflow/regression, finite conversion and nonnegative frozen elapsed values. MSVC uses its minimum selectable C++14 mode; macOS compiles as C++11 to match the root target.

The native Foundation/CF/CoreGraphics/ARC/ASan/UBSan fixture extracts complete current/frozen snapshot loops, integer normalizer, error builder and action-completeness predicate. AX root/serialization/screen/parent/clock providers are controlled; arrays, CF ownership and output rows are real Foundation objects. Cases compare 96 ordinary filter/count/metric graphs and eight preflight/root/query/error shapes, root creation consumption/caller remainder, backward/forward wall jumps, invalid clocks, final-node and empty-query overrun, action refusal, filtered final cancellation, output/fault behavior and 128 returned-result/pool lifecycles. It does not invoke real AX, UIKit, a foreground app or a tap.

Windows validation: all **90 workflow runners** (36 source, 54 safety), **521 existing source checks**, full preceding AX/C05a hashes, fixture extraction, JavaScript syntax, expanded assert preprocessing and `git diff --check` pass. Sixteen artifact-only checks skipped. New Apple native/iOS compilation/execution and private AX/device timing qualification require macOS CI; no measured device performance gain is claimed.
