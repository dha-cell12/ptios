# C02b12 — structured live multi-color search

Date: 2026-10-25 (Asia/Bangkok). Baseline: `30789db`; the user reported the C02b11 build passed before this slice.
Status: **source implemented; new macOS/iOS CI and device qualification pending**.
Finding: **P0-13, live findMultiColor portion**. Image/OCR adapters and helper transport remain open.

## Result and scope

Root JS findMultiColor decodes ROI and point offsets into a bounded numeric plan and calls one licensed task-28 entry. It avoids per-row Foundation strings, a joined request table, aggregate request formatting/UTF-8 allocation, RAW/CF dispatch, captured response-vector allocation and successful reply parsing. RAW action 3 retains its parser and shares fresh capture, ROI clamping, anchor/crop planning, RGBA rendering and first-match scanning with the numeric backend.

One bounded Foundation %.4f tolerance string remains to preserve exact four-decimal rounding, signed-zero/nonfinite spelling and input units. Output raw/parts formatting remains. The constant empty success token only reuses the existing admission/stop/exception wrapper; result coordinates stay numeric. Each admitted valid search still takes one fresh capture. No capture reuse or measured allocation/latency benefit is claimed.

The old JS point-color encoder has no production caller after this slice and is removed from production to avoid an unused helper. Its complete baseline body is frozen in a test fixture for existing legacy bridge and ColorPicker comparisons. Both numeric decoders remain extracted from production. Production TrollStore and TouchPOC source are unchanged; both workflows run the shared expanded tests.

## Compatibility and error order

- Preserve JS 1..512 dictionary rows, finite point checks, defaults and long/short RGB aliases/respondsToSelector behavior. Decode every row before ROI validation or size rejection, including a malformed later row after an oversized numeric prefix.
- ROI fields still round through %.0f and strict signed-int parsing. Store the original formatted ROI lengths even when strict-int conversion fails; do not count an invalid huge finite ROI as a short sentinel integer. Nonfinite ROI retains the old JS validation error.
- Preserve all signed-int ROI values: x/y clamp to source bounds, nonpositive width/height select the remaining dimension and oversized positive extents clamp. Signed offsets include INT_MIN/INT_MAX without negation overflow in anchor planning. Any nonnegative signed-int skip, including INT_MAX, keeps the scanner's 64-bit step.
- Reuse the bounded point plan: at most 512 stored rows, count saturated at 513, cached integer/RGB validity and table units saturated at 131073 for the RAW 131072-byte table limit. Validate the complete table before deciding that no anchors or no matches exist.
- Preserve equivalent 8192-character JS ingress, including task/action, eight separators, four formatted ROI fields, table, signed mode/skip and actual tolerance units. Checked subtraction handles SIZE_MAX/overflow. Every encoded field is ASCII; numeric conversion preserves the old UTF-8/NUL behavior and keeps the 32 KiB transport bound satisfied. RAW/backend table/count limits remain separate from the JS ingress cap.
- Keep tolerance four-decimal conversion before mode validation; mode 0 uses similarity 0..1 and mode 1 retains integer per-channel tolerance 0..255. Rounded invalid/nonfinite values fail after authorization/compute admission.
- Order remains request prelude stop, C01 child scope, stop/license/stop, compute admission/stop, ROI/skip/mode/tolerance, complete table, capture/source geometry, clamped region, signed anchors/crop, render/memory, row-major scan and final stop. Invalid mode/ROI beats an invalid table; invalid table beats capture or a prospective no-anchor/mismatch result. Busy beats numeric invalidity.
- No anchors still requires capture/source validation, then returns a successful miss without a rendered buffer or RGBA reservation. A capture failure still wins over no anchors. Matching keeps the first eligible anchor and skip traversal.
- Success retains matched, x/y, raw and three string parts. A miss stays ok=true with matched=false and x=y=-1. No value/RGB/age/time fields are added.

## Authority, budgets and resources

The typed task installs the existing task-28 three-second C01 child scope before one license gate and checks stop before/after authorization. Caller owner/token/output limits and parent deadline isolation remain. The common ColorPicker core retains two compute admissions, its three-second cooperative request, per-point work accounting, source/ROI pixel bounds, 32 MiB RGBA policy and scope-owned capture/crop/context/buffer cleanup. RAW moves its already parsed vector into the shared screen adapter; typed requests do not copy or reparse the table.

Final output bytes, denial, caller cancellation/deadline, local C01 expiry and native exceptions keep their existing mappings. Capture/graphics/license calls remain cooperative/nonpreemptible; no hard completion deadline or process-RSS guarantee is claimed. Device measurements remain necessary.

## Validation

- Targeted Windows color/native-budget/dependency runners and standards-conforming assert preprocessing pass (three runtime fixtures plus a rejecting negative control).
- Portable coverage adds 10,000 frozen ROI/offset/anchor/crop/mode/skip/first-hit comparisons, signed extents, INT_MIN offsets/INT_MAX skip, finite coordinate overflow, exact wire accounting and 8192/8193 boundaries, plus saturated ingress. Existing point/range/predicate/golden scan/admission/work/cancel/deadline/frame/touch/budget regressions remain.
- The actual ColorPicker/CoreGraphics fixture adds 110 RAW/numeric ROI/offset/skip cases and full-table/mode order, 512/513, no-anchor success under a full RGBA memory budget without calling allocation, capture/graphics faults, retained NSError, compute-busy-before-invalid mode, cancellation/no capture after stop and recovered resources/admissions. Its clock policy loads before the new numeric header.
- The Foundation bridge fixture compares 160 cases against the frozen 30789db JS branch, actual bounded RAW bridge and controlled capture backend. Additional cases cover defaults/aliases, malformed/oversized lists, exact ingress, tolerance rounding/nonfinite values, signed/extreme ROI and offsets, no-anchor results, INT_MAX skip, full-table/global/capture error order, exact dictionaries, one task-28 gate, C01-before-license/caller isolation, denial, stop, NS/C++ faults and exact output caps for hit/miss. Typed calls make no RAW dispatch and allocate no captured response vector.
- Legacy compatibility fixtures now read the frozen complete encoder independently of the production numeric decoders; all-host checks verify one function and no numeric type dependencies. Native bridge extraction includes the actual numeric helper dependencies and compiles entries with YES/NO undefined. Production no longer references the legacy encoder.
- All 56 workflow runners pass on Windows: 36 source-contract and 20 native runners. All 521 direct workflow source-grep commands pass; 16 package-artifact checks require CI outputs.
- **Foundation/macOS execution, ASan/UBSan, iOS builds and device measurements were not run on this Windows host.** Both workflows already invoke the expanded fixtures; their new Foundation branches await macOS CI.

## Acceptance and next slice

Build rootfull/roothide observe/enforced variants. Compare JS findMultiColor with RAW task 28/action 3 on unchanged screen content for ROI rounding/clamping, signed offsets/extents, full-table validation, both tolerance modes, skip including INT_MAX, first hit/miss/no anchors, exact replies/input/output bounds and error ordering. Verify one fresh capture per admitted valid request, no RGBA allocation on no anchors, authorization/cancellation and recovery. Measure bridge allocation/latency separately from capture cost.

Continue remaining measured P0-13 image/OCR methods, P0-12 event-driven helper RPC, P1-40 config snapshots and P1-41 byte-bounded dedupe. C01/C02 performance/device acceptance remains open.
