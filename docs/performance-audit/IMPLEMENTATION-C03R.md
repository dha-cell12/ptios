# C03r — direct Task-95 JSON-v1 success envelopes

Date: 2026-10-29 (Asia/Bangkok). Baseline: `0340a8e3`, C03q build passed according to the user. Complete normalized baseline `tlinkauto-binary/SocketServer.mm` SHA-256: `12fe0aa807c4bab89648035fd060caea2525532441499261d6c6f90051a63b20`.
Status: **build passed according to the user before C03s; committed at `b8207e7a`; independent device qualification pending**.
Finding: **P1-56 response conversion amplification**, limited to the asynchronous root JSON-v1 Task-95 success path.

## Change

Previously the async completion serialized the batch and encoded base64, formatted a legacy line, converted through UTF8 into NSData, decoded that NSData back to NSString, trimmed/split it, then built and serialized the JSON-v1 envelope. Build the successful envelope directly after the same batch serialization/base64 step. Keep id (nil defaults to 0), ok=true, a one-element base64-string data array and error=null. The client-visible batch, protocol version and SDK remain unchanged; data does not become a nested batch object.

Errors continue through the exact existing legacy encoder/parser, preserving preformatted license denials, delimiter/newline/NUL behavior and event_channel_json_failed for nil/empty encoded data. Serialization exceptions retain the existing propagation policy. Duplicate-pending errors retain their existing path. The same frame encoder still enforces a one-MiB envelope body and supplies response_too_large/response_encode_failed as before.

Only the async completion selects the new encoder for JSON-v1. Root legacy, synchronous task fallback, TrollStore and remote legacy encoders are unchanged. Licensing, cancellation checks, weak context/request identity checks, pending state and socket output ownership remain byte-for-byte unchanged. TouchPOC is excluded.

## Verification

The guard reverses only the added helper and completion selection and compares the complete socket source with the user-passed baseline hash. Freeze its old legacy event encoder separately and require exact source equality with that baseline. Earlier complete Event Channel journal reverse/hash checks remain.

The actual-source Foundation fixture injects only the batch serialization boundary and legacy-parser wrapper to count operations and supply identical encoded bytes to the old/new pipelines. For 160 graph/Unicode/NUL/number/boolean/null/pagination/id cases, require equal envelope graphs, exact base64 bytes, valid ZXTP headers and equivalent framed graphs. Successful direct encoding must serialize the batch once and perform zero legacy C-string conversions/parses; the frozen path performs one of each. JSON object key order is not a wire-byte guarantee.

Additional cases cover nil/zero/negative/wide request IDs, raw/preformatted/delimited/Unicode/NUL error normalization without attempting batch serialization, nil/empty encode results, unchanged NS/C++ exception propagation, both sides of the one-MiB frame limit, 32 events with maximum canonical payloads and retained envelope/base64 lifetime across pools. Existing live async integration gains decoded JSON-v1 batch assertions and duplicate-pending/license-denial frames. Original cancellation, stale/disconnect, root legacy, TrollStore, remote, journal/locking and cross-process cases remain.

Windows validation passed: all 65 workflow runners, 521 source checks, focused event/contract/socket-output/C01-ingress guards and portable cases, expanded assert preprocessing and `git diff --check`; 16 artifact-only checks were skipped. Foundation/ARC/ASan/UBSan execution of the new cases requires macOS CI; real-device latency/RSS/allocation qualification remains separate.

## Remaining work

This removes legacy text conversion/reparse from one protocol success path. It retains base64, batch/envelope JSON serialization, frame/output limits and the existing bounded output owner. It introduces no queue/admission, durability or journal changes and claims no measured device improvement. Broader P1-56 encoding/output qualification, P1-54 journal rewrite amplification, P1-58 epochs/recovery, history/log retention and other outstanding C03 work remain open.
