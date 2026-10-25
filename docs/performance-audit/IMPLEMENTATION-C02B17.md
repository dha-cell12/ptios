# C02b17 — structured image cleanup

Date: 2026-10-25 (Asia/Bangkok). Baseline: `d2c9343`; the user reported C02b16 built successfully before this slice.
Status: **source implemented; new macOS/iOS CI and device qualification pending**.
Finding: **P0-13, releaseImage portion**. Creation/other native adapters and helper transport/config/dedupe remain open.

## Result and scope

Root JS releaseImage calls a direct structured cleanup entry sharing the numeric image-store release implementation with RAW task 48/action 3. The public method avoids the full task string/dispatch, CF stream, response vector and complete response parsing. It retains successful count/raw/parts and image tracking behavior.

The bounded owner suffix still uses the existing sanitation and 96-UTF16-unit field cap, actual UTF-8/NUL validation and a small compatibility parser. Image action 3 historically parses its C string using Foundation %s and keeps trailing owner whitespace; this path deliberately preserves that behavior. Delimiter overlap and empty-runtime omission also remain. Prefix, handle and owner fields fit within 309 UTF-16 units, below the existing 8192-unit/32-KiB ingress limits.

Production TrollStore and TouchPOC source are unchanged. Capture/open image implementations and ordinary license gates remain. Both workflows already invoke the expanded shared runner; real store/queue integration remains in the root runner. No measured allocation, latency or RSS improvement is claimed.

## Compatibility, cleanup and ownership

- Keep Foundation intValue handle conversion, negative-handle error, zero/missing handle behavior and count-zero success. Untrack the supplied image ID only after a successful reply, including a successful no-op removal.
- Keep owner token sanitation, truncation and encoded-byte admission before release. Reconstruct the bounded owner representation with the same Foundation %s parsing and use the same first three parsed owner fields. Trailing whitespace stays meaningful for image owner matching.
- The common owner-queue transaction handles single, scoped-all and global-all with the existing wildcard matcher. RAW keeps case-insensitive all/scoped targets, permissive numeric conversion, absent target returning nil, ignored extra fields and partial scoped tuples as a no-op serial barrier. The %s pointer cast changes its C type only, not the bytes or format.
- Image lifetime remains explicit. Erase drops store ownership; admitted readers retain the immutable gray payload and memory charge until they release their snapshot. Image cleanup does not modify frame entries, rearm frame expiry or require image-compute admission.
- The typed entry creates the existing cleanup context for task 48/action 3. It retains the cancellation/deadline/license exemption already applied by the RAW bridge for this cleanup action. It cannot capture/open an image; those actions retain their ordinary gates. Ordinary RAW admission is unchanged.
- Release effects precede the output-cap check as before. A too-small reply budget returns response_too_large without updating JS tracking, while the completed deletion stays committed. NS/C++ faults at the typed call boundary map to native_exception; no rollback of a partially exceptional owner operation is promised.

Cleanup and owner-queue waiting remain synchronous and may outlive a cancelled caller's original deadline. No hard completion bound is claimed.

## Validation

- All 56 workflow runners pass on Windows: 36 source-contract and 20 native runners. All 521 direct workflow source-grep commands pass; 16 artifact-only checks require CI outputs.
- The storage runner compiles the actual numeric image release body on every host, replacing only its synchronous owner hop with an immediate lambda. 10,000 cycles cover single/scoped-all/global/empty removal, owner/whitespace mismatch, held readers, unchanged frame entries/timer rearm counts and zero final charges. Existing frame-release, 20k storage lifecycle and 8 x 10k reservation regressions remain.
- The Foundation bridge fixture adds 160 comparisons against the frozen pre-C02b17 JS branch through the actual bounded RAW bridge and a controlled release backend. It compares full replies, parsed owners, count and tracking for zero/negative handles, Unicode/NUL/invalid UTF16, delimiter overlap and truncation, plus a focused trailing-whitespace case.
- Further bridge cases verify cleanup after cancellation/deadline/license denial and inherited ordinary output overflow, exact reply caps after committed effects, NS/C++ faults, no RAW dispatch/captured response sink and no cleanup license gate.
- The actual Foundation store fixture adds 144 comparisons against the frozen action-3 parser/handler, checking return values and remaining image IDs for numeric/all/scoped/partial/malformed targets, trailing whitespace and extra fields. Both compute admissions can be held while numeric cleanup succeeds and an admitted reader remains valid.
- All-host extraction includes the actual action-3 parser/core and checks entry dependencies and macro-independent booleans. Standards-conforming assert preprocessing passes the existing runtime fixtures, including storage, with a rejecting negative control.
- **New Foundation/macOS execution, ASan/UBSan, iOS builds and device measurements were not run on this Windows host.** The expanded branches await macOS CI/device qualification. The portable queue substitution does not qualify real GCD scheduling.

## Acceptance and next slice

Build rootfull/roothide observe/enforced variants. Compare JS releaseImage and RAW task 48/action 3 for matching/mismatched owners, Unicode/truncation/whitespace, missing/zero/repeated IDs, exact count/raw/parts/tracking, cancellation/deadline/license failures and output overflow after deletion. Verify admitted matcher readers survive release, resources recover, and active frame storage/expiry remains unchanged.

Continue remaining measured P0-13 creation/other adapters, P0-12 event-driven helper RPC, P1-40 policy snapshots and P1-41 byte-bounded dedupe. C01/C02 performance/device acceptance remains open.
