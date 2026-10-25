# C02b16 — structured frame cleanup

Date: 2026-10-25 (Asia/Bangkok). Baseline: `e9e0b1c`; the user reported C02b15 built successfully before this slice.
Status: **build reported passed by the user before C02b17 (`d2c9343`); device qualification pending**.
Finding: **P0-13, releaseFrame/releaseAllFrames portion**. Other remaining native adapters and helper transport/config/dedupe remain open.

## Result and scope

Root JS releaseFrame and releaseAllFrames now call a structured cleanup entry directly. It returns the existing successful status/count/raw/parts without aggregate task dispatch, CF response stream, native response vector or parsing the complete reply. RAW task 67 retains its parser and invokes the same numeric owner/store/expiry implementation.

The owner suffix still uses a small compatibility formatter/parser. Its sanitation, 96-UTF16-unit truncation, delimiter overlap, final whitespace trimming and actual UTF-8/NUL conversion are observable in owner matching; directly copying the context fields would change those edge cases. The suffix is bounded to 294 units, so a valid nonnegative int frame ID plus task prefix fits within the existing 8192-unit/32-KiB ingress limits. No new full request string is created for dispatch. The released count still uses its small compatibility column where the JS API enriches releaseAllFrames.

Production TrollStore and TouchPOC source are unchanged. Both workflows invoke the expanded shared native runner; actual image-store integration remains in the root runner.

## Cleanup and ownership contract

- Preserve Foundation intValue handle conversion, the negative-handle error, zero-handle behavior, count-zero success and frame tracking updates only after a successful reply. A successful single release still untracks the supplied handle even when no store entry matched.
- Preserve owner-field sanitation and suffix omission when runtime is empty. Owner strings are converted through the same UTF-8 representation and only the same first three parsed owner fields are used. Invalid encoding/NUL is rejected before release.
- The common serial owner transaction handles single, scoped-all and global-all release with the existing wildcard owner matcher and one expiry rearm. RAW keeps case-insensitive all/scoped commands, permissive numeric parsing and scoped-without-a-complete-owner as a no-op that still rearms expiry.
- releaseAllFrames retains its existing global store scope. This slice does not change that public API into an owner-scoped operation.
- Stored payloads remain immutable shared references. Erasing a store entry drops its store ownership; admitted readers keep pixels and the memory charge until their own release. Image entries are not modified. Cleanup does not need an image-compute admission.
- The typed entry explicitly creates the same cleanup context used by the existing RAW bridge. As in processTaskWithContext for task 67 under a cleanup budget, it skips cancellation/deadline and license gates that could strand cleanup resources. Ordinary RAW task admission is unchanged. The typed entry can only release frames.
- Output limits still apply after the release effect. If the reply is too large, return response_too_large and do not update JS tracking, while the already-completed release stays committed, matching the previous wire path. NS/C++ faults at the typed call boundary map to native_exception. This does not promise rollback of a partial exceptional owner operation.

Owner-queue waiting and cleanup remain synchronous and can outlive a cancelled caller's original deadline. No hard cleanup completion deadline or measured allocation/latency/RSS improvement is claimed.

## Validation

- All 56 workflow runners pass on Windows: 36 source-contract and 20 native runners. All 521 direct workflow source-grep commands pass; 16 artifact-only checks require CI outputs.
- The storage runner compiles the actual numeric release body on every host, replacing only the synchronous owner-queue hop with an immediate lambda. 10,000 cycles cover owner mismatch, single/scoped-all/global/empty removal, exact expiry rearm count, held readers and zero final payload charges. Existing 20k storage lifecycles and 8 x 10k concurrent reservations remain.
- The Foundation bridge fixture compares 160 cases with frozen pre-C02b16 JS branches through the real bounded RAW bridge and a controlled release backend. It checks complete results, parsed owner requests, tracking, handle/count behavior, sanitation/delimiter overlap, Unicode/NUL/invalid UTF16 and truncation. Additional cases cover cleanup after cancellation/expiry/license denial, output caps after committed effects and NS/C++ faults. Typed calls do not use RAW, a captured sink or a license gate.
- The actual Foundation image-store fixture adds 120 comparisons against the frozen pre-C02b16 release handler, including remaining store IDs after single/global/scoped/partial/malformed commands. It also tests numeric release while both compute admissions are held and a retained reader remains valid.
- All-host extraction checks the cleanup context, helper dependencies and macro-independent task entry. Standards-conforming assert preprocessing passes the existing runtime fixtures with a rejecting negative control.
- **New Foundation/macOS execution, ASan/UBSan, iOS builds and device measurements were not run on this Windows host.** The expanded branches await macOS CI/device qualification. The portable owner-hop substitution does not qualify real GCD scheduling or timer delivery.

## Acceptance and next slice

Build rootfull/roothide observe/enforced variants. Compare JS frame cleanup with RAW task 67 for matching/mismatched owners, missing/zero handles, repeated releases, all/scoped-all and existing global release behavior. Check cancellation/deadline/license failure cleanup, exact raw/parts/count/tracking, expiry rearm, output overflow after effects and active OCR/Vision/matcher readers. Measure repeated capture/OCR/release bridge cost separately from capture/compute.

Continue remaining measured P0-13 creation/other adapters, P0-12 event-driven helper RPC, P1-40 policy snapshots and P1-41 byte-bounded dedupe. C01/C02 performance/device acceptance remains open.

The user reported C02b16 build `d2c9343` passed before C02b17. Structured image cleanup is tracked in `IMPLEMENTATION-C02B17.md`. This records the user report; no independent macOS/device execution was performed on this host.
