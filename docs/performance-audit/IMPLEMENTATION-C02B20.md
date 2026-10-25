# C02b20 — structured openImage entry and publication rollback

Date: 2026-10-25 (Asia/Bangkok). Baseline: `adf0a93`; the user reported C02b19 built successfully before this slice.
Status: **corrected build reported passed by the user before C02b21 (`0200261`); device qualification pending**.
Finding: **P0-13, openImage input portion**. Response parsing, captureImage/other adapters and helper transport/config/dedupe remain open.

## Result and scope

Root openImage prepares a structured path/owner request and calls one licensed task-48 entry. RAW action 2 and typed callers share the same path resolution, file existence/read, ImageIO metadata preflight, bounded OpenCV decode, charge/owner assignment and immutable image-store publication. The typed method avoids generic RAW dispatch, the CF reply stream and captured response vector.

The path/owner compatibility tail is still formatted, encoded and split at the JS bridge. The canonicalizer retains the complete action-2 body as the input to Foundation %s, including its ASCII prefix. The request retains the parsed NSString path through ARC, avoiding another UTF-8 decode before resolution. Paths historically permit protocol delimiters, including overlap between a trailing semicolon and the owner suffix; sanitizing or rejecting those paths would change the contract. Preserve the actual UTF-8/NUL admission and Foundation %s conversion, then pass the resulting path and owner fields directly to the common core. This does not remove all input string construction/parsing.

The three-field successful body and four reply parts remain. The task builds/parses the compatibility reply, and JS still enriches ID/width/height and tracks the returned image. Response parsing is deliberately retained for a later slice. No measured allocation, latency, CPU or RSS benefit is claimed. Production TrollStore and TouchPOC source are unchanged.

## Compatibility and resource ownership

- Preserve the existing empty-path error, full 8192 UTF-16-unit envelope and 32-KiB byte cap, with five ASCII units/bytes reserved for 482;;. Length rejection precedes encoding/NUL rejection, then the task budget/floor/license checks. Portable helpers use subtraction to reject saturated size values without overflow.
- Preserve relative path resolution through the current script directory or scripts folder, absolute paths, Unicode, whitespace and delimiter-derived fields. Empty owner session/run fall back to empty; empty runtime falls back to legacy. The original owner suffix sanitation/truncation and the RAW Foundation %s parser remain authoritative.
- Keep RAW action-2 compute admission before its missing-path check. Both APIs use the same two-request image compute gate and core; action 1 (captureImage) and action 3 (releaseImage) retain their existing paths.
- Keep the 32-MiB encoded read bound, 8192-axis/pixel checks, grayscale decode behavior and rotated-dimension acceptance. The same byte sequence is checked and decoded. File close, metadata release, image count/byte budgets, non-reused IDs, explicit lifetime and charged held readers remain unchanged. CV decode and script context are controlled doubles in the new macOS fixture.
- The public typed function resets its publication ID before admission. The common core reports the assigned ID before formatting its successful body. The result format remains ID;;width;;height; no additional decode or owner-queue lookup is introduced.

## Authority, output and failed transfers

The typed entry inherits the ordinary caller deadline, token, owner and output cap, using no response capture sink. Keep stop and the 1024-byte creation-response floor before exactly one task-48 license gate, followed by another stop check. Task 48 receives no additional C01-local duration.

Commit follows complete result construction and the final output-byte/stop checks. On cancellation, expiry, oversized output or an NS/C++ fault after publication, finally attempts direct release of only the newly published ID using the exempt cleanup context. It does not depend on recovering the ID from a response buffer or reproducing the original owner suffix. This also prevents delimiter-shifted owner fields from defeating the cleanup of this call's own allocation. An unrelated ID remains untouched; IDs are never reused.

Cleanup is best-effort and exceptions are contained. Image objects have explicit lifetime, so a cleanup failure has no frame-style TTL fallback. File, metadata, CV, license and synchronous owner operations remain cooperative/nonpreemptible; no hard completion deadline or guaranteed rollback after every possible process/cleanup failure is claimed.

## Validation

- All 56 workflow runners pass on Windows: 36 source-contract and 20 native runners. All 521 direct workflow source-grep commands pass; 16 artifact-only checks require CI outputs. Standards-conforming assert preprocessing passes the existing runtime fixtures and all new image-open fixtures with a rejecting negative control. git diff --check passes.
- **Actual Foundation/macOS execution, ASan/UBSan, iOS builds, real OpenCV and device measurements were not run on this Windows host.** The new bridge/file/Foundation branches await macOS CI.
- Portable storage tests add 100k input-unit/byte envelope plans plus exact 8187/8188 and 32763/32764 tail boundaries and SIZE_MAX rejection. Existing 20k storage, held-reader, frame/image cleanup and 8 x 10k ledger cases remain.
- The actual bridge/entry fixture adds 180 frozen pre-C02b20 JS/RAW comparisons for relative/absolute/Unicode/whitespace/delimiter paths, owner sanitation/truncation, UTF-8/NUL rejection, metadata/results and tracking. It also compares exact 8192/8193 envelopes, backend errors, one gate, denial/gate-time cancellation/expiry, 1024-byte floor, pre/post-publication NS/C++ faults, late cancellation/deadline/output overflow and cleanup isolation from an unrelated ID.
- The actual file/store fixture adds 96 frozen old-handler/RAW/direct comparisons with real PNG files and ImageIO, script-folder doubles, controlled CV and held readers. It covers missing format/path, compute busy, byte/count admission, failed publication, decode mismatch, corrupt metadata and oversized encoded files, ending with zero live image charges.
- All-host extraction verifies the new entry's floor/gate/core/finally dependencies and macro-independent booleans. The decoder fixture now ends before the adjacent open adapter so standalone decoder tests do not import unrelated functions. No compiler warning or sanitizer policy is relaxed.

## Acceptance and next slice

Build rootfull/roothide observe/enforced variants. Compare openImage with RAW task 48 action 2 for absolute/script-relative paths, Unicode/delimiters/whitespace, owner variants, file/decode/count/memory failures and exact raw/parts/metadata. Exercise caller stop/deadline near file reading, decoding, publication and response construction. Verify failed transfers remove only the new image and admitted readers remain valid after release; measure bridge overhead separately from decode and memory pressure.

Continue remaining P0-13 creation/response/other adapters, P0-12 event-driven helper RPC, P1-40 policy snapshots and P1-41 byte-bounded dedupe. C01/C02 performance/device acceptance remains open.

## CI correction — fixture helper declaration order

The C02b20 macOS build at `79c78ee` failed because image-open-runtime-fixture.inc was included before the definition of publishImage. Move that include below the complete helper definition. The production image-open/store path is unchanged. An all-host extraction guard now rejects the original ordering before compiling the runtime fixture; corrected macOS CI remains pending.

Correction validation: image-storage portable/extraction checks and standards-conforming assert preprocessing pass on Windows; git diff --check passes. Actual macOS Foundation/sanitizer compilation and execution must be rerun in CI.

The user reported corrected C02b20 build `0200261` passed before C02b21. Structured openImage metadata is tracked in `IMPLEMENTATION-C02B21.md`. This records the user report; no independent macOS/device execution was performed on this host.
