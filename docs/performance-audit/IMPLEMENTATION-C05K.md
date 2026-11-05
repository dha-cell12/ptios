# C05k — Apply the caller remainder to every non-snapshot AX attribute

Date: 2026-11-05 (Asia/Bangkok). Baseline: `589afb8a`; user reported C05j build passed and requested continued implementation. Shared rootfull/roothide and production TrollStore AX attribute/serializer path, including hit-test; TouchPOC excluded. Continues C05/P1-59/P2-22.

## Per-query parent gates

C05j bounded the hit-test root and refused a late result. Its serializer still set a node timeout once before the six-attribute group when no local snapshot window was supplied. Later RPCs could therefore retain the earlier timeout even after most of the caller's time had been consumed.

Apply the existing per-attribute setup and post-query checks whenever either a local snapshot window or a caller budget exists. Each reached attribute samples min(100ms, caller remainder), additionally clamped by the same local window when present. Check stop/expiry after setup and after query; an out-value returned too late retires through the existing finally block. A missing setter retains the checks, although it cannot bound an opaque query's duration. No parent/local deadline is renewed.

When the caller budget supplies these per-query limits, remove the redundant once-per-node setter and reject a late final serialized row, including expiry during decoding. The public hit-test's C05j checks still translate caller stop into ui_cancelled_or_timed_out and release its raw root/hit owners. Normal fields, attribute order, CF/errorOut/exception handling, geometry and Task foreground/action/authority policy remain unchanged.

Standalone serialization with neither a caller budget nor local window retains its original once-per-node100ms setter and result behavior. Snapshot serialization already used per-query setup under C05c and keeps that structure/local window. No new total500ms hit-test deadline, worker, admission limit or cancellation mechanism is introduced.

For an ordinary six-query hit-test with a caller budget, node setter calls rise from one to six; the root setter is unchanged. This is a deliberate deadline/cancellation tradeoff, not a claim of lower ordinary request latency. Device measurements must qualify the extra setter work. Opaque providers can still ignore/overshoot timeouts, and caller-free/queue/full-operation bounds, root/selector/string-output memory and device qualification remain open. C05/P1-59/P2-22 remain partial.

## Verification

Freeze the complete preceding attribute/serializer region. Reverse only parent-aware gates, setter placement and final-row check, validate the complete C05j AX hash, then continue the existing C05j/i/h/g/f/e/d/c/b/a restoration chain. Reuse the snapshot safety runner/workflows; runner count remains90.

Extend its existing Foundation/CF/CoreGraphics/ARC/ASan/UBSan attribute executable with complete current/C05j helpers. The actual public hit-test/serializer and CF ownership remain in use; AX/screen/clock/dispatch are controlled. Add an optional cooperative timeout model to the provider, disabled by default so all preceding fixtures retain their setup. The model rounds the recorded float timeout upward to nanoseconds and caps simulated query work; it does not emulate or measure a real AX implementation.

Native expectations cover128 full dictionary/sorted-JSON/field/key-order comparisons with a long parent. Normal output matches while current setters run per reached query versus one preceding setup. Under a100ms parent and60ms query work, the controlled cooperative provider expects current timeouts100ms/40ms and100ms total versus120ms with the preceding stale timeout; the late value is discarded and its raw owner released. A10ms setter plus20ms query model expects three queries/four setups versus five queries/one setup before expiry, demonstrating admission after setup work.

Other cases cover missing setter, expiry during decode, cancellation at each of six query positions, direct late CF values/errorOut, NS/C++ after-out-value cleanup, actual hit-test refusal with balanced root/hit ownership, and128 pool lifecycles. Final value-object destruction is checked after normal enclosing pool exit. Existing standalone/local/snapshot/hit-test frozen cases remain enabled. Counts/timing are controlled expectations, not device gains; no real AX/UIKit/foreground/tap effect occurs.

Windows validation: all **90 workflow runners** (36 source,54 safety), **521 existing source checks**, complete staged AX/header restoration, fixture extraction, JavaScript syntax, expanded assert preprocessing and `git diff --check` pass; sixteen artifact-only checks skipped. Existing portable100k window cases pass. Extended Apple/iOS compilation and Foundation/ARC/sanitizer execution require macOS CI. Device qualification remains pending.
