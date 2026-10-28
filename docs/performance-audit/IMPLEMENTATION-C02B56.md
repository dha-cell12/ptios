# C02b56 — avoid re-encoding listBundles JSON metadata

Date: 2026-10-29 (Asia/Bangkok). Baseline: `892d8de`, containing C02b55; the user reported that build passed.
Status: **user reported build `94634ed3` passed before C03a; independent device/performance qualification pending**.
Finding: **P0-13, metadata codecs/copies, listBundles(true)**. C02 remains partial.

## Result and scope

The rootfull/roothide listBundles(true) consumer ordinarily parses JSON from the original base64-decoded NSData after Foundation UTF8 validation. Remove the previous UTF8 re-encoding and its second NSData on that ordinary path. Leading UTF8 BOM bytes retain the former text/re-encoding conversion, including repeated BOMs, to preserve Foundation's text conversion behavior. Keep the existing base64 options, UTF8 validation and default JSON parser options, without a custom encoding or parser. Standalone base64 text decoding for OCR/shell/other consumers stays unchanged.

This changes the metadata consumer only. Workspace enumeration, selectors/KVC, JSON/base64 production, RAW task 53, direct entry, one ordinary task-53 gate, context/deadline/output and false-mode bundleIds remain unchanged. Production TrollStore and TouchPOC sources are unchanged; both workflows retain the shared checks.

The intermediate validation NSString still exists, as do decoded NSData, backend JSON/base64, raw/parts, parsed objects and result-dictionary copying. No full producer/consumer roundtrip removal, universal allocation ceiling or measured CPU/latency/RSS improvement is claimed. The existing response bound remains at its original dispatch/entry boundary; the new private codec adds no separate limit.

## Compatibility

Keep strict base64 options 0 and the prior NSString UTF8 validation before Foundation's JSON encoding auto-detection. A failed validation produces no JSON object, just as the former empty-text fallback could not produce valid JSON. The public result still adds items only on the existing success/parts path, accepting a dictionary whose items field is an array and falling back to [] for other shapes or decode failures. Preserve raw/parts/ok and all existing fields exactly.

UTF16/32 cases are compared against the old sequence rather than treated as a new supported-encoding policy. In particular, BOM-bearing input rejected by the old UTF8 stage must remain rejected, while any input that previously passed that stage and Foundation's JSON auto-detection must retain its result. JSON fragments, duplicate keys, number conversion, escapes, malformed sequences and errors continue following Foundation with options 0.

Always-host guards restore only the former three codec statements and compare the entire JS branch against frozen `892d8de`, plus the existing pre-direct-bridge metadata oracle. Separate guards retain the exact standalone base64 text decoder, backend enumeration/encoding and RAW handler. The new helper feeds the original NSData to JSONObjectWithData ordinarily; its sole dataUsingEncoding call must stay inside the leading-BOM compatibility branch. Permissive base64/fragment options remain prohibited.

No scheduling, retry, authority, accepted-effect or exception policy is added. Result objects retain their own Foundation ownership after temporary bytes, strings and caller pools retire.

## Verification

All 62 workflow runners (36 source-contract, 26 native), 521 direct workflow source-grep assertions, expanded standards-conforming assert preprocessing and git diff --check pass on Windows. Focused native-budget/extraction passes. Sixteen artifact-only checks require CI outputs. New Foundation/ARC/ASan/UBSan compilation/runtime cannot run on this Windows host and remain pending macOS CI. Warnings, assertions and sanitizers stay enabled.

The codec fixture compiles the original base64 text decoder and former consumer independently of the new helper. Cases compare objects/nil for 160 nested Unicode/boolean/number calls; UTF8/16/32 with endian and BOM variants; malformed UTF8 and base64, NUL, JSON syntax/errors/fragments/types/duplicate keys/wide numbers/surrogates; 700-KiB JSON metadata; mutable input, cross-pool ownership and 128 repeated replacement/error lifecycles.

The actual listBundles fixture also injects controlled encoder bytes into both frozen and current full JS/task/core routes to compare metadata fallback for valid, missing/wrong-type items, empty/malformed JSON and UTF8/16/32 payloads. Its captured wire, backend operation order and single-gate assertions remain. JSON key ordering remains unspecified, so ordinary encoded dictionaries are compared by decoded payload and exact wire captured from that invocation, as before. Private workspace objects are controlled; no real application inventory is read.

## Acceptance and remaining work

Build rootfull/roothide and run the new Foundation fixtures. Compare listBundles(true/false) metadata and errors on supported devices, then profile consumer re-encoding separately from workspace enumeration, backend serialization and JSON parsing. No measured savings are inferred from source-call removal.

Other metadata codecs/copies, P1-40 synchronous metadata/invalidation and P0-12 unknown-start/device/performance qualification remain open. Explicit rawTask, resource-release compatibility and generic unknown connectivity fallback remain deliberate RAW paths. This checkpoint does not close C02.
