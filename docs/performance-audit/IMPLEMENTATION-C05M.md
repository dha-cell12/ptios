# C05m — Refuse stopped snapshot/find work at entry and return

Date: 2026-11-05 (Asia/Bangkok). Baseline: `014f4359`; user reported C05l build passed and requested continued implementation. Shared rootfull/roothide and production TrollStore AX query wrappers/formatter; TouchPOC excluded. Continues C05/P1-59.

## Caller-stop boundaries

Add six cooperative stop checks. Public snapshot checks before enqueue and after dispatch returns. Public find preserves its existing selector class/required-criteria validation, then checks before building options/enqueue and after dispatch. The private find formatter preserves failed-input passthrough, then checks before selector work and after the full row traversal.

An observed stop returns the existing ui_cancelled_or_timed_out error with partial=true. Pre-stopped requests skip owner enqueue and all lock/prepare/root/query work. If the existing native dispatch wrapper skips queued work after the caller stops, the public API now reports cancellation instead of generic ui_snapshot_failed/ui_find_failed. If a caller stops after owner work completes but before the wrapper returns, its prior success or error is superseded by cancellation.

The formatter's final check closes the last-row gap: visibility/clickability/other predicate work can observe or trigger stop and then take continue, with no next loop admission to catch it. Empty successful inputs also refuse an already stopped caller. A failed input snapshot still passes through by identity before the new formatter checks. All non-stopped predicate ordering/count/index/selected-row identity, fields, normalization and error results retain their preceding source.

No query, local/parent deadline, CF ownership, Task foreground/action/authority guard or schema changes. Snapshot stop precedes its deferred inner PID validation; find's existing public selector validation remains first. These are cooperative boundary checks, not queue preemption, new admission capacity, coalescing or an atomic cancellation/publication transaction. In-flight opaque calls and dispatch_sync waiting for prior work still require their existing bounds. Root/selector/string-output and device qualification remain open; C05/P1-59 remain partial.

## Verification

Freeze the complete preceding snapshot wrapper/text matcher/find region. Reverse only the six guards, validate the complete C05l AX hash, then continue the existing C05l/k/j/i/h/g/f/e/d/c/b/a restoration chain. Reuse the existing snapshot runner/workflows; runner count remains90.

Extend its Foundation/CF/CoreGraphics/ARC/ASan/UBSan snapshot executable with complete current/C05l public wrappers and private matcher. The real Foundation snapshot/error/result graphs and CF owners remain in use; AX/serializer/clock and dispatch admission/return are controlled. The dispatch model now mirrors the existing wrapper's skip-on-stop rule and provides explicit queue/return stop seams, disabled for preceding fixtures. No real queue/IPC timing is qualified by this model.

Native expectations cover256 full public dictionary/sorted-JSON/work-count comparisons across ordinary snapshot/find fields and errors. Pre-entry, queued and post-return stop cases must report cancellation/partial, with zero expensive work for requests stopped before admission. Pre-stopped current requests expect zero enqueues versus one preceding modeled enqueue. A stop after a completed failure also takes precedence at public return. Existing selector validation and private failed-input identity remain checked.

Five formatter cases cover empty input, final match, final visibility rejection, final clickability rejection and final identifier mismatch. The preceding formatter can return a complete success/absence after the stop; the current formatter must return an incomplete error. Existing1000 frozen matcher cases remain enabled. Another128 post-return cancellation cycles require balanced root owners and source-array retirement after normal pool exit. Counts are controlled expectations, not measured queue/device gains; no real AX/UIKit/foreground/tap effect occurs.

Windows validation: all **90 workflow runners** (36 source,54 safety), **521 existing source checks**, complete staged AX/header restoration, fixture extraction, JavaScript syntax, expanded assert preprocessing and `git diff --check` pass; sixteen artifact-only checks skipped. Existing portable100k window cases pass. Extended Apple/iOS compilation and Foundation/ARC/sanitizer execution require macOS CI. Device qualification remains pending.
