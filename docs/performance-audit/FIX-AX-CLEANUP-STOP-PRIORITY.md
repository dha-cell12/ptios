# Task77 cleanup fixture stop-reason priority

Date: 2026-11-07 (Asia/Bangkok). Baseline: `c104e607`. The supplied macOS log confirms the preceding JSON ownership fix passed. Execution then stopped at capabilityCleanupCases line84, expecting Deadline for an ordinary child whose cancellation token was already cancelled and whose deadline was also expired.

## Cause and correction

TLinkNativeBudget::reason checks parent stop, local output overflow, cancellation and deadline in that order. Direct cleanup budgets ignore their own cancellation/deadline; ordinary children share those inputs and do not inherit the cleanup exemption. When both cancellation and expiry apply to that child, Cancelled wins. The fixture's Deadline expectation was wrong; production policy and Task77 handling are unchanged.

Split the native cleanup test into cancellation-only, deadline-only and both. Require direct cleanup None; require ordinary child Cancelled, Deadline and Cancelled respectively. Retain actual/frozen root/TrollStore provider-count, wire and JSON expectations. Report runtime/cause/child/current/actual/expected if handler execution changes the reason unexpectedly.

Add the same three-case matrix to the portable suite using the production C++ budget/classifier. Check each reason before Foundation is involved and then verify that inherited OutputLimit overrides both cancellation and deadline. This reproduces the relevant policy on Windows instead of leaving it only in an Apple-only test.

## Validation

Focused AX source/portable checks pass, including the new priority matrix. Expanded assertion preprocessing passes for both changed fixtures. All90 workflow runners pass across the full run and one focused retry;521 source checks and production HEAD identities also pass. The full Windows run passed89 runners; helper-identity assertions passed but temporary-executable cleanup hit EPERM. Its unchanged focused rerun completed successfully, including cleanup. The macOS log already confirms JSON ownership, late-wire/phase/publication pools and shared matcher/enqueue groups passed, but it stopped before the full Task78–81 runtime group. That later native execution still requires CI confirmation after this fixture fix. No production code, cancellation priority, authority, wire contract or action behavior is changed.
