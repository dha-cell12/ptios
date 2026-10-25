# C02b19 — structured captureFrame result and metadata

Date: 2026-10-25 (Asia/Bangkok). Baseline: `765d989`; the user reported C02b18 built successfully before this slice.
Status: **source implemented; new macOS/iOS CI and device qualification pending**.
Finding: **P0-13, captureFrame response portion**. Other creation adapters and helper transport/config/dedupe remain open.

## Result and scope

Root captureFrame receives a numeric result from the common capture/store core. Its task entry publishes the final compatibility raw/parts and metadata dictionary directly. JS tracks the returned ID and returns that dictionary without splitting the complete successful reply, reading its metadata columns or copying it into another mutable dictionary.

The compatibility formatter builds fifteen reply columns and joins them for raw. It retains small scalar conversions for the scale, four timing values, ID and timestamp so the public values match the historical Foundation conversions exactly. In particular, publishing the unrounded internal doubles would change the API. RAW task 66 keeps the historical single fourteen-field body formatter using the same numeric capture result.

This removes full response parsing from the typed success path, not compatibility string construction or every scalar conversion. Individual column formatting changes transient allocation behavior; no measured allocation, latency, CPU or RSS improvement is claimed. Production TrollStore and TouchPOC source are unchanged. Both workflows retain the expanded shared native-budget runner.

## Compatibility and ownership

- Keep C02b18 input options, owner sanitation/encoding/defaults, channel policy, TTL normalization, compute admission, pixel/byte/count limits, immutable store publication and expiry. No additional capture, conversion or store lookup is introduced.
- Preserve ID, dimensions, stride, pixel/BGRA labels, flags, legacy wall timestamp, scale and all four timing fields. Scale/timing columns retain %.3f, signed zero and decimal rounding. Metadata uses the exact formatted scalar doubleValue conversions and timestamp longLongValue conversion; raw keeps the status prefix and CRLF. Gray-only capture retains the historical format and stride fields.
- The capture value contains only numeric fields; it owns no pixels, Objective-C objects or store references. The public function resets it and the publication ID before admission. Published payload ownership and charged held readers remain in the existing store.
- RAW formats its body inside its existing compute-admission scope. Typed formatting now follows the numeric call, after that compute scope is released; it operates only on copied scalar fields and does not hold a pixel reader. totalMs still ends at the same pre-format capture-core point. This does not qualify a performance change or shorten opaque capture work.

## Authority, output and rollback

Keep the ordinary caller child budget, pre-stop and 1024-byte creation floor before exactly one task-66 license gate, followed by another stop check. Task 66 retains the caller deadline and uses no C01-local duration or response capture vector. Error/denial replies retain their existing adapter.

The core reports the published ID separately before copying the successful numeric output. The entry checks stop after capture, constructs the complete dictionary, then checks compatibility raw byte length and stop before commit. A formatter exception, cancellation during result construction, output overflow or earlier capture/publication failure therefore leaves the call uncommitted. Its existing finally block attempts direct cleanup of only that newly published ID in the exempt cleanup context. Best-effort cleanup and active expiry remain the fallback policy; unrelated frames are not removed.

Capture, renderer, CV, license and synchronous owner operations remain cooperative/nonpreemptible. No hard completion deadline or device qualification is claimed.

## Validation

- All 56 workflow runners pass on Windows: 36 source-contract and 20 native runners. All 521 direct workflow source-grep commands pass; 16 artifact-only checks require CI outputs. Standards-conforming assert preprocessing passes the existing fixtures, new result fixture and formatter header, with a rejecting negative control. git diff --check passes.
- **Actual Foundation/macOS execution, ASan/UBSan, iOS builds, real capture/OpenCV and device measurements were not run on this Windows host.** The new 3000-case formatter suite and expanded Foundation fault branches await macOS CI.
- The actual formatter has 3000 pending Foundation comparisons against the frozen C02b18 monolithic formatter, reply splitter and JS enrichment. Cases cover complete raw/parts/dictionaries, channel flags, three-decimal boundaries, signed zero, large finite scalars, unsigned ID boundaries and timestamps through UINT64_MAX. The compatibility body formatter is compared independently too.
- Retain 160 frozen JS/RAW input/owner/result comparisons, one-gate and caller-budget cases, capture/store errors, the 1024-byte floor and output overflow. Add NS/C++ result-formatter faults and cancellation after dictionary construction to the actual task-entry fixture; failed transfers must leave no fixture frame allocation.
- Adapt the actual capture/store fixture to numeric output while retaining 48 frozen old-handler body/owner/TTL/channel comparisons, controlled timing, real CoreGraphics provider ownership, compute/memory/pixel/render/gray/publish failures and zero final charges. Screen/renderer/CV are controlled doubles; real display capture and OpenCV remain unqualified.
- All-host guards reject whole-response splitting and JS metadata reparsing in the typed path, keep the license/floor/formatter/output/commit order, and ensure RAW still uses its historical body formatter. No warning or sanitizer setting is relaxed.

## Acceptance and next slice

Build rootfull/roothide observe/enforced variants. Compare captureFrame with RAW task 66 for channel/TTL/owner variants, exact metadata/raw/parts, fractional scale/timing, capture faults, low output limits and cancellation/deadline near publication/result construction. Verify failed calls leave no newly owned frame and held readers survive release/expiry/eviction. Measure bridge time and allocations separately from capture/conversion and store pressure.

Continue remaining P0-13 creation/other adapters, P0-12 event-driven helper RPC, P1-40 policy snapshots and P1-41 byte-bounded dedupe. C01/C02 performance/device acceptance remains open.
