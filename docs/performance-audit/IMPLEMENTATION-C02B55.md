# C02b55 — remove the intermediate RAW response NSData

Date: 2026-10-29 (Asia/Bangkok). Baseline: `be14508`, containing C02b54; the user reported that build passed.
Status: **user reported build `892d8de` passed before C02b56; independent device/performance qualification pending**.
Finding: **P0-13, remaining RAW response copies**. C02 remains partial.

## Result and scope

Rootfull/roothide's bounded executeRawPayload response path now initializes its owned UTF8 NSString directly from the completed budget vector. Remove the explicit NSData dataWithBytes snapshot and subsequent initWithData decode. The initializer consumes the vector synchronously; no borrowed/no-copy string storage escapes the scope. Empty responses retain the literal ACK.

This affects explicit rawTask and remaining internal RAW compatibility calls, including allocation rollback and unknown connectivity task fallback. Existing direct typed adapters remain unchanged. Production TrollStore and TouchPOC sources are unchanged; both workflows retain the shared checks.

The RAW input NSMutableData, compatibility CF stream, bounded response vector, NSString, parts array and dictionary still exist. This removes one explicit full-response NSData copy from application code; it does not establish a zero-copy pipeline, eliminate Foundation temporaries, or measure total allocation/CPU/latency/RSS savings. Responses remain bounded by the existing maximum 1-MiB sink policy.

## Compatibility and ownership

An always-host source guard compares the complete dispatcher against frozen `be14508` source after restoring only the two replaced decode statements. All validation, request encoding, C-string chunk admission, context/cleanup classification, license dispatch, stream open/close, exception handling, output policy and response parsing remain unchanged.

Preserve exact raw/parts/ok values, UTF8 decoding, newline trimming, delimiters, empty ACK behavior and invalid_response_encoding. Decode still precedes final stop conversion and allocation rollback. An invalid UTF8 response therefore retains its existing encoding-error precedence; a valid partial response containing a positive image/frame ID can still trigger release after cancellation or output overflow. Failed or nonpositive IDs do not gain a new rollback rule.

The frozen dispatcher is compiled under a renamed selector, including recursive release calls, so the new decoder cannot become its own oracle. New results must survive the request vector, retained test observation and caller pools retiring, later buffer replacements and failed decodes. Existing NS exception policy and opaque committed effects are preserved; no retry or scheduling change is introduced.

## Verification

All 62 workflow runners (36 source-contract, 26 native), 521 direct workflow source-grep assertions, expanded standards-conforming assert preprocessing and git diff --check pass on Windows. Focused native-budget/extraction passes. Sixteen artifact-only checks require CI outputs. New Foundation/ARC/ASan/UBSan compilation/runtime cannot run on this Windows host and remain pending macOS CI. Warnings, assertions and sanitizers stay enabled.

The new Foundation fixture compares full actual/frozen dispatchers using the real bounded sink and CF stream, with task effects controlled. Coverage includes 160 ordinary chunked responses; every split point of representative Unicode, BOM, noncharacter and malformed UTF8 sequences; empty/no-write ACK, C-string NUL truncation, newline/delimiter/status/parts behavior; exact output caps and 1-MiB responses; pre-cancel/expiry, cancellation after writes, NS faults, invalid-encoding/output/stop precedence; frame/image rollback with ordinary, malformed, partial and invalid replies; cleanup after stop; and immutable large results across pools and 128 buffer replacements. No task, image creation, file release or hardware effect is performed on a real device by these doubles.

Existing runtime cases retain actual deadline expiry during dispatch, cancellation and allocation rollback coverage. Source comparison retains these paths without introducing a new timing-sensitive oracle for this decode-only change.

## Acceptance and remaining work

Build rootfull/roothide and compare rawTask replies, invalid encodings, output failures and cleanup on controlled devices. Profile large RAW results to distinguish the removed application-owned NSData snapshot from NSString/parts and Foundation allocations.

Explicit rawTask, resource-release compatibility and generic unknown connectivity fallback remain deliberate RAW paths. Other metadata codecs/copies, P1-40 synchronous metadata/invalidation and P0-12 unknown-start/device/performance qualification remain open. This checkpoint does not close C02 or claim measured performance gains.
