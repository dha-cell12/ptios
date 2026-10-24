# C02b7 — structured frame color search

Date: 2026-10-25 (Asia/Bangkok). Baseline: `650a4f4`; the user reported the C02b6 build passed before this slice.
Status: **build reported passed by the user at `d6147de`; device qualification pending**.
Finding: **P0-13, frameFindColor portion**. Other frame color methods/helper transport remain open.

## Result and scope

Root JS frameFindColor prepares a numeric search request and uses one licensed task-69 entry. The reader holds one immutable BGRA frame snapshot and never recaptures the display. Numeric and RAW search_single routes share the same scan, including ROI conversion/clamping, row-major first match, BGRA stride, inclusive RGB ranges and skip traversal.

The typed bridge avoids aggregate request formatting/encoding, RAW/CF dispatch, captured response vectors and successful reply splitting. It still converts the bounded coord token for exact RAW encoding admission and builds small compatibility output strings. Production TrollStore and TouchPOC source are unchanged; both production workflows already invoke the expanded shared root fixtures.

## Compatibility and admission

- Preserve positive frame-id and finite JS ROI checks, delimiter rejection, option defaults, long RGB keys/short aliases and case-insensitive pixel/point selection. Coordinates retain the old %.0f then strict-double preparation, including half ties, signed zero and extreme finite inputs.
- Preserve the equivalent 8192 UTF-16-unit aggregate input limit using exact ASCII numeric lengths, integer digits, search_single mode/separators and coord units. Checked subtraction rejects overflow. Size precedes actual UTF-8 conversion/NUL rejection; encoding rejection precedes authorization. Other fields are ASCII, so the old 32 KiB UTF-8 cap is satisfied after these checks.
- Preserve frame options, signed INT_MAX-1 coordinate magnitude admission, inclusive RGB 0..255, ordered min/max pairs, skip 0..1023 and maxAgeMs 0..5000. Zero max-age retains the default TTL.
- The shared request prelude can reject a stopped caller before method validation. Within the method/entry preserve error order: JS validation, ingress, caller stop/task license, color admission, numeric parameters, image admission, snapshot/BGRA/geometry, TTL, then scaled coordinate conversion and scan work. A stale frame still wins over a point-scale coordinate overflow; invalid RGB/skip still wins before snapshot acquisition.
- Region coordinates clamp to the frame as before. Nonpositive width/height select the remaining region, positive sizes clip at the right/bottom edge, and skip+1 is the same row/column step. No-match remains a successful response with matched=false and x/y/RGB all -1.

## Authority, budgets and output

The task entry installs the existing three-second C01 child budget before one task-69 license gate and checks stop before/after authorization. It inherits the caller owner/token/output limit without shortening the parent deadline. The shared scan retains row stop checks and per-pixel work accounting; the adapter checks stop again before returning. Existing two color/two image admissions and snapshot ownership unwind on failure.

Output retains matched, x/y/RGB, raw/parts, ageMs, totalMs rounded through the same three-decimal text and both historical time columns. The final compatibility raw byte length is checked against the caller cap. License denial, local C01 expiry, parent cancellation/deadline, exceptions and output overflow retain their existing mappings.

No measured allocation/latency/RSS gain or hard completion deadline is claimed. License/store/framework waits remain cooperative. Physical coordinate accuracy and runtime performance still require device qualification.

## Validation

- Windows: all 36 source-contract runners, 20 native runners and 521 direct workflow source-grep commands pass. Sixteen artifact-only commands require CI package outputs.
- Portable modern-image runner: 10,000 cases compare against the frozen pre-C02b7 scan for padded BGRA stride, region bounds/defaults, point scale, skip, match and no-match. Additional cases cover exact 8192/8193 wire accounting, extreme signed/finite/parameter inputs and deterministic work/cancel/deadline termination. Existing 10k multi-point plans, 100k scalar cases and 3000 matcher golden cases pass.
- The Foundation bridge fixture compiles the actual bridge/task entry with YES/NO undefined. A frozen C02b6 JS branch plus the actual bounded RAW bridge and a controlled frame backend compare 160 ROI/RGB/skip/scale cases, defaults/aliases, invalid options, Unicode/NUL and input limits. It also checks exact hit/miss metadata/output caps, one task-69 gate, C01/caller deadline isolation, denial, authorization delay, cancellation, faults and no typed RAW dispatch.
- The actual Image adapter fixture adds 216 RAW/numeric search cases with a controlled metadata clock and real Foundation containers, plus frame/geometry/TTL/coordinate error precedence, admissions, held snapshot after erase, cancellation and released slots. It verifies no display capture.
- Standards-conforming macro preprocessing passes all three runtime fixtures with a rejecting negative control. Native-budget portable checks and actual-source dependency extraction pass on Windows.
- **Foundation/macOS execution, ASan/UBSan, iOS builds and device measurements were not run on this Windows host.** Expanded branches are already reached by both CI workflows and await qualification.

## Acceptance and next slice

Build rootfull/roothide observe/enforced variants. Compare JS/RAW searches on the same frame for scaled/clamped/default ROI, RGB aliases/bounds, skip, first match/no match, exact reply fields, TTL/error order, authorization/cancellation/output caps and recovery. Verify no recapture, retained reader or admission. Measure allocation rate and call latency independently of frame creation.

Continue frameIsColors/frameFindMultiColor and other measured P0-13 methods, then P0-12 event-driven helper RPC, P1-40 config snapshots and P1-41 byte-bounded dedupe. C01/C02 device acceptance remains open.
