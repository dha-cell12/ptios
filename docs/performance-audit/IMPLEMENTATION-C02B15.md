# C02b15 — structured OCR result publication

Date: 2026-10-25 (Asia/Bangkok). Baseline: `2475200`; the user reported C02b14 and its OCR-success correction built successfully before this slice.
Status: **build reported passed by the user before C02b16 (`e9e0b1c`); device qualification pending**.
Finding: **P0-13, ocrFrame response portion**. Other remaining native adapters and helper transport/config/dedupe remain open.

## Result and scope

Root ocrFrame now receives a structured result from the shared OCR core: decoded text, six immutable compatibility columns and the legacy body. The licensed task entry publishes raw/parts and the existing public numeric fields directly. Its success path no longer splits the complete wire response or Base64-decodes the text it just encoded. JS returns the success dictionary directly; the existing error enrichment path remains.

RAW task 91 returns the same six-field body from that shared result. Formatting remains inside the OCR owner operation before delegate/image cleanup and the final request-budget check. This preserves the request scope across queue wait, preprocessing, engine work and result publication. No screen recapture or separate recognition implementation is added.

Compatibility Base64 encoding and body/raw construction remain because raw/parts are public fields. Small scalar-column conversions also remain to preserve the published numeric rounding. The shared formatter reuses the actual UTF-8 bytes to normalize decoded text exactly as the old Base64 decoder did; it avoids Base64 decoding, not every string conversion. This slice makes no measured allocation/latency/RSS claim, and the extra structured fields can change transient allocation behavior.

Production TrollStore and TouchPOC source are unchanged. Both workflows already invoke the expanded shared runners.

## Compatibility, lifetime and authority

- Preserve trimmed engine text, Unicode/NUL and unencodable-string behavior, empty text and the same Base64 option. The public text is reconstructed from the same UTF-8 bytes used for its compatibility column, retaining legacy conversion behavior even for unusual NSString contents.
- Confidence retains %.2f; OCR/preprocess/total timing retains %.3f; age retains unsigned decimal spelling. The task reads the numeric fields from those exact small columns using the historical doubleValue/longLongValue conversions. It does not publish the unrounded internal double values.
- Six body columns and seven reply parts keep their original order. raw retains the status prefix and CRLF. The frozen formatter compares complete bodies, including signed zero, half-decimal boundaries, nonfinite values and large ages.
- ARC-owned text/body/columns survive the queue autorelease pool. The public typed function clears the output value before admission and only moves a completed result to the caller after final budget/error checks. Failed requests do not publish stale result fields. No block escapes the synchronous queue handoff.
- Keep C02b14 input validation/defaults/encoding/8192-unit accounting, one task-91 license gate, three-second C01-before-license, parent cancellation/output limits and two-request OCR admission. Engine cache identity/LRU/pressure epochs, preprocessing and pixel/gray limits remain unchanged.
- Error/denial parsing and Base64 error enrichment remain on their compatibility path. Keep the prior corrected column-aware OCR error/fallback adapter, output cap and stop checks, NS/C++ exception handling, and engine delegate/image teardown. No strict warning or sanitizer setting is disabled.

Opaque license, queue, CV and engine calls remain cooperative/nonpreemptible. Device latency, recognition accuracy and memory behavior require measurement.

## Validation

- All 56 workflow runners pass on Windows: 36 source-contract and 20 native runners. All 521 direct workflow source-grep commands pass; 16 artifact-only checks require CI outputs.
- Existing portable OCR coverage retains 10k ingress plans, 100k scale/buffer plans, 100k LRU identities, 80k admission/deadline cycles, and the native output/cancellation suites.
- Both Foundation fixtures add the actual production formatter against a frozen pre-C02b15 body formatter: 1000 cases for Unicode/NUL/invalid UTF16, confidence/timing rounding, signed zero/nonfinite values, age boundaries and immutable cross-pool ownership.
- The actual bridge/entry fixture retains 100 frozen JS/RAW input cases and adds 80 result comparisons with the old JS decoding/enrichment branch. These verify text, numeric fields, complete raw/parts and correct success status, alongside existing one-gate, denial/deadline/cancel/fault/output-cap cases.
- The actual OCR queue/cache fixture retains 12 RAW/typed adapter comparisons and adds result lifetime after queue/caller pools, dynamic engine text and stale-output clearing after a subsequent fault. CV/engine remain controlled doubles; real Foundation/CoreGraphics/provider and production orchestration run on macOS.
- All-host extraction includes the real formatter and rejects whole-response splitting/Base64 decoding in the typed success path. Standards-conforming assert preprocessing passes the three existing runtime fixtures and the new result fixture, with a rejecting negative control.
- **New Foundation/macOS execution, ASan/UBSan, iOS builds, real OpenCV/Tesseract and device measurements were not run on this Windows host.** Those expanded branches await macOS CI/device qualification.

## Acceptance and next slice

Build rootfull/roothide observe/enforced variants. Compare JS ocrFrame with RAW task 91 for empty/Unicode/multiline recognition, ROI/TTL, language/whitelist and OEM/PSM/scale/threshold choices. Verify confidence/timing precision and exact raw/parts shape, license/stop/timeout/output behavior, pressure/cache recovery and result lifetime. Measure bridge cost separately from recognition accuracy/latency and process memory.

Continue remaining measured P0-13 adapters, P0-12 event-driven helper RPC, P1-40 policy snapshots and P1-41 byte-bounded dedupe. C01/C02 performance/device acceptance remains open.

The user reported C02b15 build `e9e0b1c` passed before C02b16. Structured frame cleanup is tracked in `IMPLEMENTATION-C02B16.md`. This records the user report; no independent macOS/device execution was performed on this host.
