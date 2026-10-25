# C02b13 — structured image matching in a stored frame

Date: 2026-10-25 (Asia/Bangkok). Baseline: `404af5a`; the user reported the C02b12 build passed before this slice.
Status: **build reported passed by the user before C02b14 (`4a3b0d4`); device qualification pending**.
Finding: **P0-13, findImageInFrame portion**. Other image/OCR adapters and helper transport remain open.

## Result and scope

Root JS findImageInFrame creates a numeric request and calls one licensed task-68 entry. It avoids the aggregate request string/UTF-8 buffer, RAW/CF dispatch, captured response vector and parsing the complete successful wire reply. RAW task 68 retains its parser and compatibility text adapter over the same numeric matcher. The frame/template admission, immutable readers, ROI, scale/SAD core, work/memory policy and stored-frame behavior remain shared. No screen recapture is introduced.

Bounded Foundation scalar strings deliberately remain for four ROI and four matching parameters. They preserve the exact %.0f/%.4f spelling, including signed zero, nonfinite values and input length, rather than changing admission at a decimal boundary. The coord token retains actual UTF-8/NUL conversion checks. Output compatibility columns remain; public center/score/time numbers round through the corresponding small text columns, as before. There is no measured allocation/latency/RSS claim.

Production TrollStore and TouchPOC source are unchanged. Both workflows run the shared expanded tests.

## Compatibility and error order

- Keep positive frame/image ID JS checks, defaults/respondsToSelector conversion and coord delimiter validation. The old method does not reject nonfinite ROI/matching scalars in JS; the numeric plan preserves their encoded length and defers invalid parameters until the licensed backend.
- ROI strings use strict signed-int parsing. Matching parameters retain the rounded double values for the 63-interval traversal bound, plus legacy float scale values for the matcher. Preserve acceptable 0..1, float scale/step limits, pixelSkip 0..1023 and maxAgeMs 0..5000. Do not derive traversal admission from already narrowed floats.
- Keep equivalent 8192 UTF-16-unit ingress: task prefix, twelve separators, IDs/skip/age integer digits, four actual ROI and four actual scalar lengths, and coord units. Counters and checked subtraction reject overflow. Size precedes UTF-8/NUL rejection, and ingress precedes authorization. Numeric fields are ASCII; the bounded coord token keeps the existing 32 KiB UTF-8 transport ceiling satisfied.
- Order remains request prelude stop, task-local C01 scope, stop/license/stop, image request stop/parameters, image-compute admission, one owner-queue frame/template snapshot transaction, frame existence/gray, TTL, template existence, gray geometry, scaled coordinate conversion/clamped ROI, then the original matcher and final stop check.
- RAW keeps its request scope around parsing and invokes the shared matcher with that existing request. Nested SAD work reuses the same request; work/deadline/scratch budgets do not reset between adapter and matcher. Owner-queue critical sections still handle references/metadata only; CV runs afterward.
- Preserve hit/miss x/y, width/height, center, score, ageMs, totalMs, raw and eleven string parts. Miss text retains integer -1 center columns, not -1.00. Hit centers use two decimals, score four and both historical timing columns three. Enriched numeric fields reflect those published rounded columns.
- Keep the same frame/template reader ownership and __block transfer into ordinary C++ locals before lambda computation. Release/expiry of store entries cannot invalidate admitted readers.

## Authority, budgets and resources

The typed task installs the existing task-68 eight-second C01 child scope before exactly one license gate and rechecks stop afterward. It retains caller owner/token/output limits without shortening the parent deadline. Existing image-compute admission, template work ceiling, scale/pixel planning, scratch reservation and scope-owned references remain. The final raw byte length is checked before success; denial, parent cancellation/deadline, local C01 expiry, output overflow and NS/C++ faults keep their mappings.

Opaque authorization/queue/OpenCV work remains cooperative/nonpreemptible. No hard completion deadline, real OpenCV interpolation guarantee or device performance result is claimed.

## Validation

- Targeted Windows modern-image/native-budget/image-storage runners and dependency extraction pass. Standards-conforming assert preprocessing passes all three existing runtime fixtures with a rejecting negative control.
- Portable coverage adds 10,000 frozen decimal/int/float/admission cases and exact input accounting: signed/overflow ROI, rounded scalar traversal, age/coord policy, and saturated ingress. Existing frame color/search/multi/scalar/budget cases and 3000 frozen matcher golden cases remain.
- The Foundation bridge fixture compares 120 cases against the frozen 404af5a JS branch, actual bounded RAW bridge and controlled matcher backend. Additional cases cover defaults/conversions, nonfinite and decimal limits, UTF-8/NUL/Unicode coord, exact 8192/8193 ingress, exact hit/miss fields/rounding, frame/image/compute errors, one task-68 gate, eight-second C01-before-license/caller isolation, denial, stop, NS/C++ faults and exact output caps.
- The actual Image fixture adds 36 RAW/numeric pixel/point/ROI/skip cases with a controlled metadata clock, plus frame-gray/TTL/template/coord/busy/cancel ordering and no recapture. It compiles the actual snapshot/ROI/matcher adapter and uses the existing controlled CV implementation; it does not qualify real OpenCV interpolation.
- Storage regression extraction now targets the numeric matcher for actual admission/map-transfer/lookup statements. Its find fixture uses the new bool result shape, and the release fixture explicitly ends before the adjacent matcher. All-host assertions prevent unrelated matcher helpers/types from entering the standalone release fixture.
- All 56 workflow runners pass on Windows: 36 source-contract and 20 native runners. All 521 direct workflow source-grep commands pass; 16 package-artifact checks require CI outputs.
- **Foundation/macOS execution, ASan/UBSan, iOS builds, real OpenCV and device measurements were not run on this Windows host.** Both workflows already invoke the expanded fixtures; their new Foundation branches await macOS CI.

## Acceptance and next slice

Build rootfull/roothide observe/enforced variants. Compare JS findImageInFrame with RAW task 68 on one retained frame/template for decimal/float boundaries, reversed scale ranges, point-space ROI, TTL, missing template/frame, match/miss and exact output columns. Check authorization/cancellation, store release/expiry during admitted work, output caps and admission/resource recovery; verify no display capture. Measure bridge allocation/latency separately from matcher cost.

Continue remaining measured P0-13 image/OCR methods, P0-12 event-driven helper RPC, P1-40 config snapshots and P1-41 byte-bounded dedupe. C01/C02 performance/device acceptance remains open.

The user reported C02b13 build `4a3b0d4` passed before C02b14. Structured ocrFrame input is tracked in `IMPLEMENTATION-C02B14.md`. This records the user report; no independent macOS/device execution was performed on this host.
