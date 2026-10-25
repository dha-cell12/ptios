# C02b21 — structured openImage result and metadata

Date: 2026-10-25 (Asia/Bangkok). Baseline: `0200261`; the user reported the corrected C02b20 build passed before this slice.
Status: **source implemented; new macOS/iOS CI and device qualification pending**.
Finding: **P0-13, openImage response portion**. captureImage/other native adapters and helper transport/config/dedupe remain open.

## Result and scope

Root openImage receives a copied numeric image ID, width and height from the common file/decode/store core. Its task entry builds the final success dictionary directly, including compatibility raw/parts and the existing metadata fields. JS tracks the returned ID and returns that dictionary. The typed success path no longer splits the complete wire reply or reparses/copies metadata in JS.

Compatibility raw and four parts still exist. The formatter constructs those columns directly and joins them for raw; ID retains the historical NSString intValue conversion of its unsigned decimal spelling. Width/height are already native ints, matching the prior scalar parsing. RAW task 48 action 2 keeps its original ID;;width;;height body formatter over the same numeric result.

Input compatibility formatting/parser and path/owner conversions from C02b20 remain. This slice removes successful response parsing, not all string formatting or every scalar conversion. It makes no measured allocation, latency, CPU or RSS claim. Production TrollStore, TouchPOC and the captureImage adapter are unchanged.

## Resource and compatibility policy

- Preserve C02b20 input caps and error order, ARC-retained path, Foundation %s behavior, owner canonicalization, relative/absolute path resolution, file/read/ImageIO preflight, grayscale decode and rotated dimensions. Existing two-request compute, byte/pixel/axis/count limits and immutable store publication remain shared with RAW.
- Preserve three body columns, four reply parts, status prefix and CRLF, plus exactly the old ID/width/height public fields. Successful dictionary comparison covers the full shape and scalar Foundation conversions. Synthetic integer-boundary formatter tests do not expand the geometry accepted by the store.
- The numeric result owns no pixels, store reader or Objective-C objects. The public function clears it and the publication ID before admission. It only fills the result after store publication; failed admission/decode/publication does not expose a stale previous result.
- The core reports the publication ID separately before copying scalar metadata. RAW formats within its existing compute scope. Typed result formatting follows the public numeric call after compute admission has ended, holding only copied scalars. This introduces no new decode, screenshot or store lookup.
- The corrected image-open fixture remains included after the complete publishImage helper definition. The all-host order guard is retained.

## Authority, result commit and rollback

Keep the ordinary caller child budget, no response capture sink, pre-stop and 1024-byte creation floor before exactly one task-48 license gate, followed by another stop check. Task 48 adds no C01-local duration. Existing denial/error reply adapters remain.

After the numeric call, check stop before formatting. Construct the complete success dictionary, then check raw output bytes and stop before commit. The existing finally cleanup uses the exempt context and separately reported publication ID. NS/C++ formatter faults, cancellation/deadline during result construction and output failure therefore roll back only this call's new image. A false core result without NSError returns a defensive image_open_failed reply and also remains uncommitted.

Three formatted integer columns fit well below the retained 1024-byte floor; the final output check remains defensive. The fixture injects an oversized final formatter result to exercise that path. Cleanup failures remain contained and best-effort; explicit image lifetime has no frame-style TTL fallback. File/decode/license/owner operations remain cooperative/nonpreemptible, without a hard completion guarantee.

## Validation

- All 56 workflow runners pass on Windows: 36 source-contract and 20 native runners. All 521 direct workflow source-grep commands pass; 16 artifact-only checks require CI outputs. Standards-conforming assert preprocessing passes the existing fixtures, new image-result fixture and result header with a rejecting negative control. git diff --check passes.
- **Actual Foundation/macOS execution, ASan/UBSan, iOS builds, real OpenCV and device measurements were not run on this Windows host.** The new formatter/result/fault branches await macOS CI.
- The actual formatter adds 1000 pending Foundation comparisons against frozen C02b20 monolithic body/reply parsing/JS enrichment. Compare complete raw/parts/dictionaries across unsigned ID conversions and signed integer formatting boundaries, and retain a result beyond its producer autorelease pool.
- Retain 180 frozen JS/RAW path/owner/result comparisons and exact envelope/one-gate/caller/output/error cases. Add NS/C++ result-formatter faults, cancellation and deadline after dictionary construction, a false-without-error result, and injected final output overflow. All failed transfers must remove the new ID while preserving unrelated allocations.
- Adapt the actual file/store fixture to numeric output while retaining 96 frozen old/RAW/direct comparisons, real PNG files and ImageIO, controlled CV/script environment, held readers and existing failure/zero-charge checks. Add a populated stale-output check rejected by the busy compute gate.
- All-host extraction guards reject full-response splitting in the typed task and metadata reparsing/copying in JS, and verify RAW uses the compatibility body formatter and publication ID precedes scalar output. No warning or sanitizer policy is relaxed.

## Acceptance and next slice

Build rootfull/roothide observe/enforced variants. Compare openImage with RAW action 2 for exact metadata/raw/parts across paths/owners and real decode/count/memory errors. Exercise caller stop/deadline near publication and result construction, confirm unsuccessful calls release only their new ID and held readers remain valid. Measure bridge cost separately from image loading, decoding and memory pressure.

Continue remaining P0-13 creation/other adapters, P0-12 event-driven helper RPC, P1-40 policy snapshots and P1-41 byte-bounded dedupe. C01/C02 performance/device acceptance remains open.
