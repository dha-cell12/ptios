# C02b9 — structured frame multi-color search

Date: 2026-10-25 (Asia/Bangkok). Baseline: `fc1b96a`; the user reported the corrected C02b8 build passed before this slice.
Status: **build reported passed by the user before C02b10 (`036c2b7`); device qualification pending**.
Finding: **P0-13, frameFindMultiColor portion**. Other typed methods and helper transport remain open.

## Result and scope

Root JS frameFindMultiColor decodes dictionary points and ROI into a bounded numeric plan, passes one licensed task-69 entry and searches one immutable BGRA snapshot. It avoids per-point Foundation strings, a joined request table, aggregate request formatting/UTF-8 allocation, RAW/CF dispatch, a captured response vector and parsing the successful wire reply. The RAW find_multi_point adapter retains its wire parser and shares ROI/offset preparation and the same numeric BGRA scan.

One bounded Foundation %.4f tolerance string remains to preserve the old rounding, signed-zero/nonfinite spelling and input length. The coord string retains actual UTF-8/NUL validation; compatibility output strings remain. Production TrollStore and TouchPOC source are unchanged; both production workflows run the shared expanded tests.

## Compatibility and error order

- Preserve JS 1..512 dictionary rows, finite point coordinates, defaults and long/short RGB aliases. Decode every row before method effects, including a malformed later row after a large encoded prefix.
- Preserve %.0f ROI/offset rounding, strict table integers/RGB, tolerance formatted to four decimals, modes 0/1 and skip 0..1023. Stored rows are capped at 512, count at 513 and table units at 32769. Coordinate or RGB failures are cached until backend validation, preserving their historical error position.
- Preserve the equivalent 8192 UTF-16-unit wire cap, including find_multi_point, task 69, eleven separators, four signed integer fields, all ROI/table/tolerance/coord units. Checked subtraction rejects SIZE_MAX/overflow. Size admission precedes UTF-8/NUL validation and authorization. The remaining fields are ASCII, so this also respects the old 32 KiB UTF-8 limit.
- Preserve the existing request prelude stop check and entry order: C01 child scope, stop, one task-69 license gate, stop, color admission, global frame/mode/tolerance/ROI/skip parameters, image admission, snapshot/BGRA/geometry, TTL, scaled ROI conversion, full table validity, conversion of every signed offset, then anchor planning and row-major scanning.
- A scaled ROI failure wins over an invalid table. An invalid later table row wins over an overflowing earlier offset or early mismatch. Every offset is converted before deciding that no anchors exist. Unlike frameIsColors, an unconvertible search offset returns frame_coordinate_invalid.
- ROI clamps to the frame; nonpositive width/height uses the remaining dimension. Signed offsets retain their direction and bound eligible anchors. The first matching anchor and skip traversal are unchanged for both pixel/point coordinates and padded BGRA stride. No display recapture occurs.

## Authority, budgets and output

The typed task installs the existing three-second C01 child budget before authorization without shortening the parent. It retains the owner/token/output limit, two color/two image admissions and one shared immutable frame reader. Work is charged per point comparison, with row and final stop checks. The bounded scaled-offset copy is at most 512 points.

Success preserves matched, x/y, ageMs, the two three-decimal time columns, totalMs rounded through that text, raw and parts. A miss is a successful response with matched=false and x=y=-1. It does not add frameIsColors value or RGB fields. Final output bytes, parent cancellation/deadline, local C01 expiry, authorization denial and native exceptions retain their mappings.

No measured allocation/latency/RSS reduction or hard completion deadline is claimed. Opaque license/store/framework waits and device accuracy/performance still need qualification.

## Validation

- Windows targeted checks pass: modern-image, native-budget/dependency extraction, ColorPicker fixture isolation and standards-conforming assert preprocessing (three runtime fixtures plus a rejecting negative control).
- Portable coverage adds 10,000 comparisons against a frozen pre-C02b9 ROI/offset/pixel evaluator: both modes, signed offsets, point scales, padded stride, ROI clamping, skip/first-hit/miss, coordinate overflow and exact 8192/8193 wire accounting. Additional probes reject saturated input and exercise deterministic work, cancellation and local deadline bounds. Prior scalar/search/comparison/matcher cases pass.
- The Foundation Image fixture adds 220 RAW/numeric ROI/skip cases and explicit ROI/table/offset/TTL/frame error order, 512/513 counts, held snapshot after erase, full admission recovery, cancellation cleanup and no recapture.
- The Foundation bridge fixture uses the frozen fc1b96a JS branch and actual RAW adapter with a controlled frame backend. It compares 160 cases plus aliases/defaults, invalid/oversized lists, Unicode/NUL, ten tolerance spellings, exact input caps, ROI/table/offset errors and exact result dictionaries. It also checks one task-69 gate, zero typed RAW calls/response-vector capacity, local/caller deadlines, denial, exceptions, cancellation and exact output caps for hit/miss.
- The obsolete private BGRA predicate is removed; the modern fixture extracts the complete table parser/reader at its new boundary. The independent ColorPicker encoder fixture remains isolated from numeric frame helpers. New entry/header/dependency extraction is checked on every host.
- All 56 workflow runners pass on Windows: 36 source-contract and 20 native runners. All 521 direct workflow source-grep commands pass; 16 package-artifact checks require CI outputs.
- **Foundation/macOS execution, ASan/UBSan, iOS builds and device measurements were not run on this Windows host.** The expanded Foundation tests await macOS CI.

## Acceptance and next slice

Build rootfull/roothide observe/enforced variants. Compare JS/RAW frameFindMultiColor on one frame for ROI rounding/clamping, signed offsets, point scale, both color modes, skip/first-hit/miss, invalid later rows and ROI/table/offset/TTL error precedence. Check exact response fields, input/output boundaries, task authorization, cancellation and recovery; verify no recapture or retained admission/reader. Measure allocation rate and latency independently of frame creation.

Continue the remaining measured P0-13 methods, P0-12 event-driven helper RPC, P1-40 config snapshots and P1-41 byte-bounded dedupe. C01/C02 device and performance acceptance remains open.

## Following checkpoint

The user reported C02b9 build `036c2b7` passed before C02b10. Live findColor is tracked in `IMPLEMENTATION-C02B10.md`. This records the user report; no independent macOS/device execution was performed on this host.
