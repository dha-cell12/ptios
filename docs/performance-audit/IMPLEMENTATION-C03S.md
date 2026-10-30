# C03s — shared NSData legacy Event Channel encoder

Date: 2026-10-29 (Asia/Bangkok). Baseline: `b8207e7a`, C03r build passed according to the user. Complete normalized source SHA-256: root `SocketServer.mm` = `bc5ea783caad88ca7eeccbadeb570e547a9f96749464eccd3ef1642a033f6189`; TrollStore `POCSocketServer.mm` = `99f1e8da43f663d95a4072e879be9d41663e5a8687f435e3f94f5448aca111f7`.
Status: **build passed according to the user before C03t; committed at `c20c70d9`; independent device qualification pending**.
Finding: **P1-56 legacy response conversion amplification**.

## Change

Add a private header-only Task-95 encoder shared by rootfull/roothide and production TrollStore. Serialize the batch once with the same NSJSONSerialization options, encode base64 directly as NSData with options 0, then append the existing ASCII prefix and CRLF to an owned NSData response. This avoids a base64 NSString, formatted legacy NSString and UTF8 conversion/C-string copy in the success wrappers. It retains JSON/base64 byte buffers and the final response; it is not zero-copy or a new producer-memory bound.

Use it in both async batch wrappers and synchronous Task-95 fallbacks. The remote adapter already calls the same TrollStore batch wrapper. No new linked implementation or build target is needed. TouchPOC is excluded.

Keep the exact legacy `0;;<base64 JSON>\r\n` contract, nil/empty JSON failure labels, per-runtime error formatting/NUL/newline behavior and existing serialization exception propagation. Success base64 options and batch JSON options remain zero. The C03r direct JSON-v1 helper, all licensing/cancel/weak-context/request identity checks, pending state, journal persistence, queues and output owners remain unchanged. No cap is newly applied to the legacy encoder; existing frame/output caps still apply downstream.

## Verification

Reverse only the shared-header imports and four success-encoding blocks, then hash each complete socket source against `b8207e7a`. Preserve the C03r and earlier complete-source reverse/hash guards. Freeze the previous TrollStore encoder alongside the existing frozen root encoder; its reconstruction participates in the complete TrollStore hash. Require the shared helper to serialize once and use byte base64/framing without NSString formatting or UTF8 conversion.

The actual-source Foundation fixture supplies the same encoded JSON bytes to old/new encoders and compares complete NSData wire bytes. Cover 256 graph/Unicode/NUL/number/boolean/null/extension cases and all three base64 padding residues. Count zero successful legacy C-string/formatted-success conversions in the new wrappers versus one per frozen root/TrollStore wrapper. Extract actual and frozen synchronous Task-95 blocks behind a controlled poll boundary and compare replies/errors and one poll/serialization per wrapper; licensing is exercised separately by the existing real async integration.

Additional cases cover raw/preformatted/delimited/Unicode/NUL errors without batch serialization, nil/empty serialization failure, unchanged NS/C++ propagation through all eight old/new async/sync entries, maximum canonical 32-event payloads, extension responses above one MiB without a new legacy cap, independent byte ownership across pools and fallback non-95 behavior. Existing C03r JSON-v1 graph/base64/error/frame cases and real root legacy/JSON/TrollStore/remote async, journal, locks, cancellation and cross-process cases remain. The socket transport fixture explicitly includes the new shared helper.

Windows validation passed: all 65 workflow runners, 521 source checks, focused event/source/contract and socket-output guards/portable cases, expanded assert preprocessing and `git diff --check`; 16 artifact-only checks were skipped. New Foundation/ARC/ASan/UBSan cases require macOS CI; real-device allocation/RSS/latency qualification remains separate.

## Remaining work

No measured device performance improvement is claimed. JSON/base64 encoding and buffer copies still occur; canonical output limits and admission remain the existing policies. P1-56 still needs device/protocol/producer qualification, while P1-54 full-journal rewrite cost, P1-58 epochs/recovery/durability, history/log retention and other outstanding C03 work remain open.
