# C05ab — Batched UI handler, retry, tap and matcher cancellation

Date: 2026-11-07 (Asia/Bangkok). Baseline: `316fe598`; user reported C05aa build passed and requested a larger implementation batch. Continues C05/P1-59 with three connected layers in one review/build checkpoint. Rootfull/roothide and production TrollStore are in scope; TouchPOC excluded.

## Task78–81 request lifecycle

Capture the native caller before request decoding. After the existing decoder validation, refuse observed stop before foreground resolution and after a successful context. Recheck after successful AX work/completeness validation, before context verification, after the unchanged context-change guard, during action preparation and before the final codec. Cancellation/deadline uses the existing UI cancellation wire; already-latched native OutputLimit keeps the size wire.

Live requests retain the same parser, query selection, context verification, metadata and result codecs. Decoder errors and reached failed context/non-retry query/action results keep their existing branches. An observed stop can skip later validation/work not yet entered. There is no new timeout, value cache, permission decision, output reservation or background queue. Task77/C05aa behavior is unchanged.

## TrollStore retry and Task81 action

The existing one-retry policy remains limited to ui_element_query_failed. Before invalidation, after invalidation, after a successful retry context and at query-loop entry, check the captured caller. A stopped retry no longer invalidates a useful cache or starts another foreground/query call after the stop has been observed. A stopped retry-eligible error now returns cancellation/size refusal instead of continuing retry work. No extra retry is introduced.

Keep the post-query foreground race check and incomplete-snapshot/action guards. Task81 also checks before coordinate/screen work and immediately before entering the existing native tap helper. This refuses a stop observed during scale/coordinate construction without dispatching a tap. Reached tap failures keep their original errors. Once the helper commits a tap, existing JSON/final gates may refuse delivery, but this code never repeats or rolls back that effect. Owned touch release/cancellation remains the responsibility of the unchanged production tap backend.

## Shared matcher and queue admission

Find checks caller stop after building selector-derived options, before synchronous queue admission, so option-time cancellation need not wait behind a held owner. The admission lease still retires on return/unwind.

Within matching, check between identifier/role/text stages, between label and value normalization, before count/selection and after result assembly. This skips remaining normalization/matching after an observed stop. Live predicate order, full traversal/match_count, requested index, visibility/clickability filters, per-row pools, metadata and partial/completeness policy remain. Existing selector validation and failed-snapshot passthrough retain priority.

## Cost and remaining limits

This batch avoids work after cooperative boundary checks; it does not interrupt a private foreground/AX call, string method, queue owner or tap helper already entered. Stop/commit/publication is not atomic. Missing caller bindings, blocked queue/transport time, provider/root materialization, global memory and device/end-to-end qualification remain open. Additional reason/clock reads add ordinary work, especially per matcher row; no measured latency/RSS/throughput gain is claimed. C05/P1-59 remain partial.

## Verification

Freeze both full C05aa task handlers and the complete shared find formatter/public wrapper. Reverse only the staged gates and earlier caller capture, require complete root/TrollStore/shared-AX HEAD hashes, then continue all previous restoration chains. Input parser implementations, context-check helpers, ordinary response codecs, capability code, native budget/gate and touch backends remain unchanged.

Extend the existing Foundation/CoreFoundation/CoreGraphics/ARC/ASan/UBSan wire executable to compile full actual/frozen Task78–81 handlers and actual context-check/completeness helpers. Private queries, screen, tap, decoder and foreground are controlled seams; JSON/base64/formatting/native budgets are real. Cover256 complete live task graph cases, live retry/work-count parity, unchanged context/completeness/element/coordinate refusals, stop at decoding/foreground/query/verification/scale, retry stop before/after invalidation/context, captured caller across nested TLS, deadline/overflow, reached-provider NS/C++ faults/weak retirement and committed tap without replay. These are handler/provider-call observations, not measurements of real AX/HID work or device delivery.

Extend the existing shared snapshot executable with actual/C05aa formatter/wrapper comparisons: four normalization cancellation boundaries skip downstream methods, option-time stop produces zero current enqueue versus one preceding dispatch attempt, admission returns to zero, and128 ordinary full graph/sorted-JSON comparisons retain fields/counts/index. Explicit MRC owners validate normal pool retirement; no Foundation class-cluster assumptions are used for the option getter seam. All previous quota/stop/pool/guard/ownership tests remain enabled.

Windows validation: all **90 workflow runners** (36 source,54 safety), **521 existing source checks**, complete frozen/source restoration, fixture extraction, JavaScript syntax, expanded assert preprocessing and `git diff --check` pass; sixteen artifact-only checks skipped. Existing portable suites run locally. New Apple/iOS compilation and Foundation/ARC/ASan/UBSan execution require macOS CI; no real private/UI/tap/transport effect or device performance gain is qualified.
