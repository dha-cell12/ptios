# C02b11 — structured live point-color comparison

Date: 2026-10-25 (Asia/Bangkok). Baseline: `6c9b095`; the user reported the C02b10 build passed before this slice.
Status: **source implemented; new macOS/iOS CI and device qualification pending**.
Finding: **P0-13, live isColors portion**. Live findMultiColor, image/OCR adapters and helper transport remain open.

## Result and scope

Root JS isColors decodes dictionary rows into a bounded numeric plan and calls one licensed task-28 entry. It avoids per-row Foundation strings, a joined request table, aggregate request formatting/UTF-8 allocation, RAW/CF dispatch, captured response-vector allocation and parsing the successful wire reply. RAW action 2 keeps its wire parser and shares full point bounds, fresh capture, crop/render and ordered pixel comparison with the numeric backend.

One bounded Foundation %.4f tolerance string deliberately remains to preserve four-decimal rounding, signed-zero/nonfinite spelling and the equivalent input size. Output raw/parts formatting remains. A constant empty success token reuses the existing admission/stop/exception wrapper without carrying result data. Each valid live comparison still performs one fresh capture. The live findMultiColor adapter body is retained and compared to its frozen baseline by an all-host source assertion. Production TrollStore and TouchPOC source are unchanged; both workflows run the shared expanded tests.

## Compatibility and error order

- Preserve upfront JS 1..512 dictionary rows, coordinate finite checks, missing-value defaults, respondsToSelector behavior and long/short RGB aliases. Decode the complete shape before admission: a late malformed row still wins over an oversized encoded prefix. Cached integer/RGB invalidity is deferred to the backend, matching the old parser.
- Point coordinates retain %.0f formatting followed by strict signed-int parsing. Rows are stored up to 512, count saturates at 513 and table units at 131073, corresponding to the ColorPicker RAW table limit of 131072 ASCII bytes. No invalid coordinate or RGB is silently clamped into an image.
- Keep the equivalent 8192-character aggregate JS ingress cap, including task/action, three separators, table, signed mode and actual formatted tolerance units. Checked subtraction rejects overflow. Every encoded field is ASCII, so no separate UTF-8/NUL rejection is needed after numeric decoding, and the old 32 KiB UTF-8 cap remains satisfied. RAW/backend limits are separate from the JS producer's transport limit.
- The tolerance still passes through Foundation's four-decimal representation before mode validation. Mode 0 retains similarity 0..1; mode 1 retains integer per-channel tolerance 0..255. Rounded nonfinite/out-of-range values fail as color_parameters_invalid after authorization and compute admission.
- Preserve the existing request prelude stop and task ordering: C01 child scope, stop/license/stop, compute admission/stop, mode/tolerance, complete table integers/RGB, all point coordinates in [0,8192), capture/source dimensions, all points inside the captured image, crop/render/memory, ordered pixel comparisons and final stop check.
- An invalid later row wins over an earlier coordinate bound or mismatch. All source-relative point bounds are checked before returning an early mismatch. A point at x=8 on an 8-pixel source is a post-capture error; x=8192 is rejected before capture. Busy still wins over invalid mode/table. Capture errors win over source-relative bounds, while protocol bounds precede capture.
- Success retains matched and value booleans, raw and two string parts. A mismatch is still ok=true with both booleans false. No coordinate/RGB/age/time fields are added.

## Authority, budgets and resources

The typed entry installs the existing task-28 three-second C01 child budget before exactly one license gate and checks stop before and after authorization. It retains caller owner/token/output limits without shortening the parent deadline. The common ColorPicker core retains two compute admissions, its cooperative three-second request, per-point work accounting, source/ROI pixel bounds, 32 MiB RGBA accounting and scope-owned image/crop/context/buffer cleanup. The table is validated before capture or comparison, including points after a prospective mismatch.

Output bytes are checked before success. Denial, parent cancellation/deadline, local C01 expiry, output overflow and NS/C++ exceptions retain the existing mappings. There is no measured latency/allocation/RSS claim or hard completion deadline; opaque capture/graphics/license calls and real device behavior still need qualification.

## Validation

- Targeted Windows color/native-budget/dependency runners pass, together with standards-conforming assert preprocessing for all three runtime fixtures and a rejecting negative control.
- Portable coverage adds 10,000 frozen encodings/bounds/crop/predicate comparisons, both modes, strict signed coordinates, exact 8192/8193 ingress, 512/513 storage/count, saturated table units, mode/tolerance and deterministic work/cancel/deadline bounds. Existing range, predicate, golden scan, admission/byte, touch/gesture, frame and native-budget regressions remain.
- The actual ColorPicker/CoreGraphics fixture adds 110 RAW/numeric scalar/mode cases plus full-table and pre/post-capture point errors, 512/513 rows, early-mismatch precedence, allocation/crop/color-space/context/draw/capture failures, retained NSError, compute-busy-before-invalid mode, memory pressure, cancellation/no capture after stop and recovered admissions/resources. Its controlled clock policy loads before the numeric header.
- The Foundation bridge fixture compares 160 cases against the frozen 6c9b095 combined JS branch, actual bounded RAW bridge and controlled color backend. Additional cases cover defaults/aliases/string-number conversion, malformed/oversized lists, 512/513, exact aggregate input boundaries, tolerance rounding/nonfinite/aliases, table/mode/protocol/source-bound/capture error order, exact response dictionaries, one task-28 gate, C01-before-license/caller isolation, denial, stop, native faults and exact output caps for match/mismatch. Typed calls make no RAW dispatch and allocate no captured response vector.
- All-host extraction checks include the new helper dependencies and entry with YES/NO undefined. The separate C++11 ColorPicker encoder fixture still extracts one complete legacy encoder and excludes numeric frame/live decoders; live findMultiColor continues using that encoder.
- All 56 workflow runners pass on Windows: 36 source-contract and 20 native runners. All 521 direct workflow source-grep commands pass; 16 package-artifact checks require CI outputs.
- **Foundation/macOS execution, ASan/UBSan, iOS builds and device measurements were not run on this Windows host.** Both workflows already invoke the expanded fixtures; their new Foundation branches await macOS CI.

## Acceptance and next slice

Build rootfull/roothide observe/enforced variants. Compare JS isColors with RAW task 28/action 2 on unchanged screen content: coordinate rounding and bounds, RGB aliases, complete-table error precedence, both modes/four-decimal boundaries, match/mismatch, exact input/output boundaries, authorization/deadline/cancellation and resource recovery. Verify one fresh capture per valid call and measure bridge allocation/latency separately from capture cost.

Continue live findMultiColor and other measured P0-13 methods, P0-12 event-driven helper RPC, P1-40 config snapshots and P1-41 byte-bounded dedupe. C01/C02 performance/device acceptance remains open.
