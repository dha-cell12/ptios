# C05e — Select AX matches without an intermediate array

Date: 2026-11-05 (Asia/Bangkok). Baseline: `66db07e3`; user reported C05d build passed and requested continued implementation. Shared rootfull/roothide and production TrollStore AX formatter; TouchPOC excluded. Continues P0-20/C05.

## Keep the count and requested row

TLinkAXFindInSnapshot appended every qualifying row to a new NSMutableArray, then used only its count and the requested item. Replace that array with an NSUInteger match counter and one strongly owned selected-row pointer. Select when the current match rank equals the normalized requested index, then increment the counter for every match.

Still visit every row in the already bounded snapshot. Preserve match_count, source order, index clamping/defaults, nil/out-of-range selection, aliases, case/text/role/visibility/clickability rules, metadata and the exact selected-row object. A first-row match does not bypass cancellation or an exception encountered in a later row. The returned selected row remains owned by the result after the input pool ends.

No matching predicate, public option, output field, scan/deadline/CF policy or foreground/action guard changes. Partial/truncated snapshots retain their flags and existing action refusal. Existing error snapshots still return directly. Result mutation/copy order is unchanged except that match_count reads the scalar instead of matches.count.

This removes one match-array allocation/growth and an append/extra retained reference per qualifying row. Temporary match bookkeeping becomes O(1); input snapshot/root rows and the selected result still have their existing ownership. It does not fuse AX querying with matching, short-circuit the scan, cache text normalization, cap arbitrary string/output allocations or claim a measured device improvement. P0-20/C05 remain partial.

## Verification

Freeze the complete preceding formatter. Exact reversal allows only the array-to-count/selected-row substitutions and validates the whole preceding AX hash before the C05d/C05c/C05b/C05a chain. Source guards require no matches array in the current formatter. Reuse the existing snapshot safety runner/workflows; runner count remains 90.

Extend its Foundation/CF/CoreGraphics/ARC/ASan/UBSan fixture with complete current/frozen formatters using the actual shared text matcher, integer normalizer, error builder and action-completeness predicate. Instrument only the frozen array append while still calling the real NSMutableArray method. One thousand ordinary cases compare full dictionaries and sorted JSON bytes across criteria/mode aliases, Unicode/case, filters, index normalization, empty/error and incomplete inputs. Assert selected-row identity as well as value parity.

The 1,000-match case retains full counts and index 0/1/999/clamped/out-of-range semantics with zero current versus 1,000 preceding appends. Controlled later-row flag reads verify cancellation and NS/C++ failures still occur after an earlier match, followed by recovery. A heap-allocated selected row must survive the input pool through the returned result. Existing snapshot/public selector/partial-action cases remain. No real AX, foreground lookup or tap occurs; append counts are fixture observations expected in macOS CI, not allocation/RSS/device measurements.

Windows validation: all **90 workflow runners** (36 source, 54 safety), **521 existing source checks**, complete staged AX hashes, fixture extraction, JavaScript syntax, expanded assert preprocessing and `git diff --check` pass. Existing portable 100k window cases pass; sixteen artifact-only checks skipped. New native Apple/iOS compilation and Foundation/sanitizer execution require macOS CI. Real AX/device qualification remains pending.
