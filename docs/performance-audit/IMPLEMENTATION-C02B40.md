# C02b40 — direct OCR language listing

Date: 2026-10-28 (Asia/Bangkok). Baseline: `86c0974`, containing C02b39; the user reported C02b39 built successfully.
Status: **source implemented; new macOS/Foundation/ARC/sanitizer CI and device qualification pending**.
Finding: **P0-13, ocrLanguages task-91 adapter**. Other adapters, metadata codecs/copies and performance qualification remain open.

## Result and compatibility

The rootfull/roothide JS ocrLanguages method calls TLinkExecuteNativeOCRLanguages directly. A small public TLinkTesseractOCRLanguages wrapper reuses the unchanged static check_langs implementation. This removes the typed full RAW request formatting/encoding, RAW command parser, processTaskWithContext dispatch, compatibility CF stream and response-vector accumulation/copy. The backend reply formatter and JS base64 decode/languages/value augmentation remain; this checkpoint does not remove their transient allocations.

The shared implementation lists /var/mobile/Library/TLinkauto/tessdata, selects the case-sensitive traineddata extension, removes that extension, sorts with compare:, joins names with commas and emits the same check_langs/base64 response. Duplicates remain; no extra file-type check excludes directory entries named *.traineddata. A missing/unreadable directory remains empty success. Preserve Unicode, delimiter and embedded-NUL names through the existing base64 codec, and ignored JS arguments. No new cache or Tesseract engine/compute admission is introduced. Listing still works when the OCR engine is compiled out. The RAW task-91 handler and full parser are unchanged and checked against frozen source.

Production TrollStore and TouchPOC execution sources are unchanged; both workflows run the shared safety suites. No CPU, allocation, latency or RSS improvement has been measured.

## Authority, deadlines and lifetime

Keep one ordinary task-91 license gate; owner automation authorization does not bypass it. The child call retains owner fields, cancellation, output settings and the inherited deadline with response capture disabled. A nested C01 budget uses the existing three-second classification, capped by the caller deadline. Initial local expiry returns the existing native_cancelled_or_timed_out wire error before the gate; initial caller stop retains AbortError/TimeoutError.

The existing check_langs branch performs no stop checks after its gate or inside the opaque filesystem listing. Preserve that behavior: accepted listing may finish successfully after local-only C01 expiry while the caller remains alive. The child does not renew or shorten the caller's deadline. Caller cancellation/deadline and output rejection still determine the returned reply after accepted work, including cancellation while the license gate is running. No hard filesystem completion deadline is claimed. This is deliberately different from the image OCR engine's cooperative checkpoints.

NSExceptions normalize to native_exception as on the RAW bridge; the direct entry also guards escaping C++ exceptions, consistent with other native entries. Scoped budgets restore TLS; a per-call pool retains the complete result through teardown. The backend multipart/base64 wire and JS metadata copies remain compatible.

## Verification

All 62 workflow runners (36 source-contract, 26 native), 521 direct workflow source-grep assertions, expanded standards-conforming assert preprocessing and git diff --check pass on Windows. The assert checker retains its rejecting negative control. Sixteen artifact-only checks require CI outputs. No warning or sanitizer checks were disabled. Windows cannot execute the new macOS/Foundation/ARC/sanitizer branches.

The historical OCR baseline check now verifies the direct JS language/frame entries and task-91 authority in Task.xm, rather than requiring the obsolete RAW task enum in the JS adapter. Frozen wire-contract fixtures are unchanged.

New macOS coverage compiles the actual shared base64/error helpers, language core, disabled-engine RAW parser, direct entry, reply formatter and bridge. Frozen JS/task/backend fragments from 86c0974 supply the old oracle. A controlled file-manager boundary checks the production directory path; separate cases list actual files and a *.traineddata directory inside a unique temporary fixture directory, then verify empty success after that directory is removed. Tests do not access the production tessdata directory or run an OCR engine.

Coverage compares complete replies and read/license counts across 160 ordinary cases; duplicates, case/suffix rules, Unicode/delimiter/NUL names, empty/error results and ignored arguments; exact/short output; ordinary authority and owner-denial behavior; pre-cancel/expiry; local C01 expiry before admission and during accepted gate/listing work; caller stop/deadline during accepted work; NSException parity and direct C++ guards; trimmed/case-folded RAW commands and disabled-engine errors; caller deadline preservation, no typed RAW dispatch/response vector and retained-result lifetime. Accelerated-overrun tests adjust only the admission timestamp passed to the real C01 budget factory; the production duration and budget implementation remain under test.

## Acceptance and remaining work

The user reported C02b39 build success at baseline 86c0974; that report does not qualify the new task-91 path. Build rootfull/roothide and compare typed/helper ocrLanguages with RAW 91check_langs against installed languages, empty/missing directories and unusual filenames. Verify exact fields/base64/languages/value, license denial/revocation, caller stop/output limits and the unchanged local-only C01 overrun behavior. Recheck RAW frame OCR and ocrFrame. Measure adapter overhead separately from filesystem listing. Continue remaining P0-13 adapters and metadata codecs/copies, P1-40 invalidation and P0-12 qualification/unknown-start cases; C02 remains partial.
