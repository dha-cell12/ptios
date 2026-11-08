# C03aq — Bounded JSON persistence for event journal and history index

Date: 2026-11-08 (Asia/Bangkok). Baseline: `b509e33b`; user reported C02c4 build passed and requested a larger implementation batch. Scope: P1-48/P1-54, shared production rootfull/roothide and TrollStore event/history writers. TouchPOC is excluded.

## Delivered together

- Add a shared Foundation output stream backed by a checked C++ quota. Reject an entire write before appending if it exceeds the remaining allowance, including overflow/SIZE_MAX cases; failure is sticky. Preserve the existing 4-MiB event journal and 32-MiB history index limits, including equality.
- Accept only complete serialization: positive writer count, no NSError, an open/nonfailed stream, and an exact count match. Return no prefix on refusal. NS/C++ writer exceptions propagate through finally cleanup to the callers' existing handling.
- Detach the private data buffer on success and drop it on close/refusal. A retained stream cannot reopen or append to returned output. Output keeps normal NSData ownership across the helper's inner pool and caller pools; the mutable backing is private during production serialization.
- Route event journal encoding and only history **index** encoding through this stream. History record/evidence JSON retains its original data encoder and options. Prevalidation, post-encoding defensive size checks, atomic file write, permissions, locking, commit/ACK, recovery and event notification source retain their prior behavior. The history index-path classification now also runs before encoding, on the existing stable internal path.
- Link the implementation once per target: pccontrol, tlinkautod, tlinkautob and streamd. No framework, quota, schema, command or public event/history API changes.

This bounds the logical bytes accepted by the producer-owned output buffer. It does **not** bound Foundation encoder temporaries, NSMutableData capacity, total allocations/RSS, validation/provider CPU, or lock/IO duration. Atomic persistence still rewrites the complete journal/index. It adds no durability, cancellation or concurrent-input-mutation contract. Device memory/latency benefits are unmeasured.

## Verification

- Freeze both complete preceding writer regions. Current full-source/region SHA guards plus exact reversal recover the complete preceding event/history files, preserving all earlier source guards. Guard the complete new helper/core/header and one implementation per target.
- Portable quota cases cover 100k independent chunk/oracle lifecycles, zero/exact/over/SIZE_MAX boundaries, sticky failure and unchanged accepted bytes on rejection.
- Extend the existing history ASan/UBSan executable with the complete production implementation and 128 real Unicode/NUL/nested JSON cases across compact/pretty/sorted options, exact/short quotas, incoherent/error/closed/ignored-refusal writers, NS/C++ unwind, detached output and cross-pool lifetime. The event executable links the production helper; its existing exact-cap append refusal checks retain disk bytes, write counts and notifications. Existing history encoded-index failure hooks and transaction tests remain.
- All 90 workflow runners (36 source / 54 safety portable subsets), 521 workflow source assertions, six-file assertion macro preprocessing, JavaScript syntax and diff whitespace checks pass on Windows. The full run exposed the earlier indicator guard of the complete root Makefile; compose an exact current-to-preceding Makefile reversal instead of relaxing its historical hash. The previously passing 89 runners plus the corrected indicator runner and focused event/history reruns pass. Sixteen artifact-only workflow assertions are skipped. Apple Foundation/ARC/sanitizer branches require macOS CI; no local Apple build or device measurement is claimed.
