# C05f — Drain temporary AX node objects during traversal

Date: 2026-11-05 (Asia/Bangkok). Baseline: `d9a48972`; user reported C05e build passed and requested continued implementation. Shared rootfull/roothide and production TrollStore AX snapshot traversal; TouchPOC excluded. Continues P0-20/P1-60/C05.

## Per-node pool

Place an autorelease pool around each admitted node's existing serialization, filtering, output estimate and append. All admission checks remain outside the pool. The node body changes only by indentation: scan counting, local/caller gates, serialization-failure accounting, filtering, byte accounting, returned fields and CF/root handling retain their preceding source.

Normal continue, break and return exits drain that pool. Temporary objects from filtered or invalid nodes can therefore retire between iterations, rather than accumulating until the caller drains its pool. Accepted dictionaries and their fields remain retained by the rows array and then the returned snapshot. An error dictionary returned from inside a pool survives through ARC return ownership.

Cleanup time falls inside the existing continuous snapshot window: the next admission/final clock sample includes pool draining. A costly drain may therefore reach the existing partial/truncated deadline sooner. No deadline renewal, earlier completeness claim or foreground/action-guard relaxation is introduced.

Clang does not drain an autorelease pool on exception exit. An enclosing pool that exits normally drains abandoned inner pools; tests check final destruction after that normal boundary, not inside a catch. Exception propagation is unchanged. See [Clang ARC autoreleasepool semantics](https://clang.llvm.org/docs/AutomaticReferenceCounting.html#autoreleasepool).

This bounds ordinary per-node temporary-pool accumulation, not the full snapshot's memory. The root still materializes the whole source array; accepted rows, arbitrary strings, JSON/base64/wire copies and opaque AX calls retain their current limits/behavior. It does not establish a global allocation/RSS ceiling, preempt AX, fuse matching or claim measured device gains. P0-20/P1-60/C05 remain partial.

## Verification

Freeze the complete preceding snapshot. A source reversal permits only the per-node pool and indentation, checks the complete C05e AX file hash, then runs the existing C05e/d/c/b/a restoration chain. Reuse the existing snapshot safety runner and both workflows; runner count remains 90.

Extend its current/frozen Foundation/CF/CoreGraphics/ARC/ASan/UBSan fixture with 128 full dictionary/sorted-JSON comparisons, real mutable row dictionaries and heap labels. AX providers, serializer, clock and parent are controlled. A separately compiled MRC helper attaches an explicitly autoreleased owner to each test row. Its live/peak/create/drop counts avoid ARC return-value autorelease elision and Foundation class-cluster assumptions; the helper is test-only and never linked into production.

Native cases expect peak one versus 128 tracked owners for all-hidden, unclickable and invalid rows; mixed results retain exactly the accepted owners after the input pool exits, with readable labels and metadata. Directed normal continue/break/output-error/cancellation returns must drain the rejected node while preserving returned error ownership. NS/C++ faults must leave zero owners after the enclosing normal pool exits. A controlled 30ms owner drain under a 100ms window expects four scans/120ms/partial versus the preceding eight scans/0ms/complete before caller drain. This demonstrates clock accounting, not real cleanup cost. Another 128 lifecycles require balanced root/array/owner cleanup.

Windows validation: all **90 workflow runners** (36 source, 54 safety), **521 existing source checks**, complete staged AX hashes, fixture extraction, JavaScript syntax, expanded assert preprocessing and `git diff --check` pass. Existing portable 100k window cases pass; sixteen artifact-only checks skipped. New native Apple/iOS compilation and Foundation/ARC/sanitizer execution require macOS CI. No real AX/UIKit/tap effects occur in the fixture; actual memory and device performance remain unqualified.
