# C02b10 — structured live color-range search

Date: 2026-10-25 (Asia/Bangkok). Baseline: `036c2b7`; the user reported the C02b9 build passed before this slice.
Status: **source implemented; new macOS/iOS CI and device qualification pending**.
Finding: **P0-13, live findColor portion**. Live isColors/findMultiColor, image/OCR adapters and helper transport remain open.

## Result and scope

Root JS findColor decodes ROI and RGB bounds into a fixed numeric request and calls one licensed task-28 entry. It avoids aggregate request formatting, UTF-8 request allocation, RAW/CF dispatch, captured response-vector allocation and successful reply parsing. The RAW action-1 parser and numeric entry share parameter checks, fresh capture, dimensions/ROI checks, RGBA rendering and the range scanner.

The existing Objective-C ColorPicker API retains its compatibility string adapter over the same numeric scan. The numeric backend returns coordinates/RGB directly; a constant empty success token only reuses the common admission/stop/exception wrapper and carries no result data. Output raw/parts formatting remains. This slice still captures the screen once per valid search; it does not promise capture reuse. Production TrollStore and TouchPOC source are unchanged; both workflows run the shared tests.

## Compatibility

- Preserve JS option defaults/respondsToSelector conversion and nonfinite x/y/width/height errors. Coordinates round through the existing immutable C-locale %.0f formatter and strict signed-int parsing. Failed conversion stays in the request until after authorization and compute admission.
- x/y must remain in [0,8192); screen-relative ROI errors still occur after capture. Width/height accept all signed integers: zero/negative uses the remaining dimension and oversized positive extents clamp to the screen. Integer overflow is an invalid parameter, never a clamped location.
- Keep all RGB bounds in 0..255 with min <= max. Any nonnegative signed-int skip, including INT_MAX, remains valid; the scanner uses its existing 64-bit skip step. Do not apply frameFindColor's narrower skip limit here.
- Four finite coordinate fields plus seven signed integers have a conservative encoded ceiling below 2 KiB, so every finite request already fits the old 8192-character/32 KiB RAW ingress limits. The numeric path adds no smaller argument cap; nonfinite coordinates fail the same JS preflight.
- Preserve error precedence: request prelude stop, task-local C01 scope, stop/license/stop, color-compute admission/stop, global numeric parameters, capture/source geometry, screen-relative ROI, render/memory/fault handling, scan and final cooperative stop. Invalid parameters still lose to compute-busy, and x/y beyond the captured dimensions still fail only after capture.
- Preserve row-major first match, skip traversal and exact RGBA interpretation. Success returns matched, x/y, red/green/blue, raw and six string parts. A miss remains ok=true with matched=false and all five numeric values -1. No age/time/value fields are added.

## Budgets and ownership

The numeric entry installs the existing task-28 three-second C01 child scope before one license gate. It retains the caller owner/token/output limit without shortening the parent deadline, and rechecks cancellation after authorization. The common ColorPicker core retains two compute admissions, the three-second cooperative scan request, 32 MiB RGBA reservation policy, source/ROI pixel bounds and scope-owned image/context/buffer cleanup. Output bytes are checked before success; denial, caller cancellation/deadline, local C01 expiry, output overflow and native exceptions keep their existing mappings.

No hard completion deadline, process-RSS bound or measured allocation/latency improvement is claimed. Capture, graphics and authorization calls remain cooperative/nonpreemptible; performance still needs device measurements.

## Validation

- Targeted Windows color/native-budget runners and source dependency extraction pass. Standards-conforming assert preprocessing passes all three runtime fixtures with a rejecting negative control.
- Portable coverage adds 100,000 frozen decimal/strict-int ROI comparisons, half ties/signed zero, huge finite/int boundaries, signed extents, RGB/skip validation and a conservative finite-input ceiling. Existing 100k color-predicate, 5000 range/multi golden cases, INT_MAX skip, deadline/work/cancel, 80k admission/byte lifecycles, touch/gesture/budget and frame regressions remain.
- The actual ColorPicker/CoreGraphics fixture adds 180 RAW/numeric ROI/skip combinations plus hit/miss and parameter cases, allocation/crop/color-space/context/draw/capture failures, retained NSError across pools, compute-busy-before-invalid input, memory exhaustion, post-draw cancellation, no capture after stop and recovered admissions/resources. The controlled-clock policy loads before the new numeric header so the real core's expiry probes remain effective.
- The Foundation bridge fixture compares 200 cases against the frozen 036c2b7 JS branch, actual bounded RAW bridge and controlled range backend. It checks exact response dictionaries, defaults/conversions/nonfinite/overflow/extents/RGB/skip, one task-28 gate, C01-before-authorization and caller isolation, no typed RAW dispatch/response vector, denial, cancellation, NS/C++ faults and exact output caps for hit and miss.
- All 56 workflow runners pass on Windows: 36 source-contract and 20 native runners. All 521 direct workflow source-grep commands pass; 16 package-artifact checks require CI outputs.
- **Foundation/macOS execution, ASan/UBSan, iOS builds and device measurements were not run on this Windows host.** Both workflows already invoke the expanded fixtures; their new branches await macOS CI.

## Acceptance and next slice

Build rootfull/roothide observe/enforced variants. Compare JS findColor with RAW task 28/action 1 for half-rounded ROI, negative/zero/large extents, RGB bounds, skip including INT_MAX, first hit/miss, exact replies and error/admission ordering. Check capture/render faults, authorization expiry, caller stop/output limits, resource recovery and one fresh capture per admitted valid request. Measure allocation rate and latency separately from capture cost.

Continue live isColors/findMultiColor and other measured P0-13 methods, P0-12 event-driven helper RPC, P1-40 config snapshots and P1-41 byte-bounded dedupe. C01/C02 device and performance acceptance remains open.
