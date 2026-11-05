# C05o — Drain temporary matcher objects after each row

Date: 2026-11-05 (Asia/Bangkok). Baseline: `ade377a1`; user reported C05n build passed and requested continued implementation. Shared rootfull/roothide and production TrollStore AX find formatter; TouchPOC excluded. Continues C05/P0-20/P1-60.

## Per-row pool

Add an autorelease pool around each row's unchanged visibility/clickability/text predicates and match count/selection. Keep the existing stop admission outside the pool and the final stop check after the loop. Normal row completion/continue drains autoreleased temporary predicate/normalization objects between iterations. The strong selectedElement variable remains outside the pool; the chosen original row and its fields survive through the returned result.

Continue evaluating the entire snapshot with the same predicate order, text normalization, count/index, selected-row identity, partial metadata and error behavior. Do not short-circuit at the requested match or hoist mutable selector values. NS/C++ exceptions still propagate. Clang leaves exception-exited pools undrained; final destruction is observed after a normally exiting enclosing pool, as in C05f. No deadline, admission, CF/root, capability, foreground/action/authority or wire/schema change.

This adds pool push/pop work per visited row and allows temporary autoreleased objects to retire sooner. ARC return-value optimization and Foundation implementation details determine actual string allocations/retention; no fixed heap/RSS reduction or latency gain is claimed. The full root/snapshot, text normalization work count, selector fusion/early-exit contract and string/output memory bounds remain open. C05/P0-20/P1-60 remain partial; device measurement is pending.

## Verification

Freeze the complete preceding formatter. Reverse only the row pool/indentation, validate the complete C05n AX hash and continue the C05n/m/l/k/j/i/h/g/f/e/d/c/b/a restoration chain. Reuse the snapshot runner/workflows; runner count remains90.

Extend its existing Foundation/CF/CoreGraphics/ARC/ASan/UBSan snapshot executable and test-only MRC owner helper. A controlled NSObject candidate implements lowercaseString, delegates returned string normalization to real Foundation and explicitly schedules a pending MRC owner through a void C helper. These candidates are method/lifetime seams, not production string subclasses or JSON fixtures; this avoids assumptions about Foundation class clusters or ARC autorelease-return elision. Existing1000 ordinary-string full graph/sorted-JSON comparisons remain enabled.

New current/C05n expectations use the same input graph and selected-row identity. One thousand text-matching rows produce2000 explicit owners: current peak2 versus preceding2000, with zero current owners left before caller drain. One thousand rejected identifier rows produce peak1 versus1000. Full match_count and first/last index remain unchanged. These are sentinel-owner counts, not measured Foundation string allocation counts.

Also verify a selected row/its original-case data after the input pool ends, final-row cancellation with a surviving error result, NS/C++ later-normalization faults with final owner balance after normal outer drain, and128 successful lifecycles. No mock row is serialized as wire JSON. AX/clock/providers remain controlled, no real UI/foreground/tap occurs, and actual memory/throughput benefits require device qualification.

Windows validation: all **90 workflow runners** (36 source,54 safety), **521 existing source checks**, complete staged AX/header restoration, fixture extraction, JavaScript syntax, expanded assert preprocessing and `git diff --check` pass; sixteen artifact-only checks skipped. Existing portable window/admission cases pass. Extended Apple/iOS compilation and Foundation/ARC/sanitizer execution require macOS CI.
