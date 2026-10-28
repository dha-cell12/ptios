# C02b44 — direct clipboard image adapter

Date: 2026-10-28 (Asia/Bangkok). Baseline: `d516066`, containing corrected C02b43; the user reported the build passed, including the toast fixture scope fix.
Status: **source implemented; new macOS/Foundation/ARC/sanitizer CI and device qualification pending**.
Finding: **P0-13, keyboard task-24 kind 8**. Other adapters, metadata codecs/copies and performance qualification remain open.

## Result and compatibility

The rootfull/roothide keyboard adapter now routes clipboard image kind 8 through TLinkExecuteNativeClipboardImage. Together with existing text kinds 6/7 and notification kinds, the full keyboard JS branch no longer constructs or dispatches a RAW request. Generic RAW task 24 remains available, with its handler unchanged. RAW and direct image paths share TLinkWriteClipboardImage for source/path validation, file metadata/read, format sniffing and UIPasteboard.items publication.

The direct path removes full task-string formatting/encoding, the full RAW split/intValue parser, processTaskWithContext, compatibility CF stream and response-vector accumulation/copy. Optional content %@ formatting and bounded reply formatting remain. Input admission keeps the entire rendered content, prefix-inclusive 8192 UTF-16 units, UTF-8 byte limits and embedded-NUL/encoding rejection before the ordinary gate. Missing content or a missing source/path separator retains the format error. Split only the first ;; into source and path; later delimiters remain in the path exactly as the old split/subarray/join sequence did. Keep Unicode, case-sensitive file source, empty-path and missing/directory errors, with the same validation order.

The backend remains unchanged apart from extraction: attributes must report nonzero size no greater than 16 MiB; NSData reads the file; the existing signature helper selects PNG/JPEG/GIF/WebP; pasteboard items contain one dictionary mapping that UTI to the original bytes. Signature detection does not decode or validate a complete image. The 16-MiB metadata preflight is not a post-read byte cap or process-RSS bound, and does not close the existing file-change window. No cache, new read policy, image conversion, path normalization or pasteboard verification is introduced. A missing pasteboard still produces the old success reply without an applied item.

Success remains the empty body response (0;; followed by CRLF). Existing image errors and keyboard text metadata are preserved. Production TrollStore and TouchPOC execution sources are unchanged; both workflows run the shared safety suites. No CPU, allocation, latency or RSS improvement has been measured.

## Authority, effects and lifetime

Each image call retains one ordinary task-24 license gate. Owner automation authorization does not bypass it. The child context retains owner fields, inherited deadline, cancellation and output settings with response capture disabled. Task 24 adds no C01-local deadline. Stop is checked after content conversion, before/after the gate and after backend/reply work.

File operations and pasteboard publication remain opaque synchronous work. Accepted operations may read and publish before caller cancellation/deadline, output rejection or an escaping exception is reported. There is no early output floor, cancellation check inside the unchanged backend, retry or rollback of an uncertain pasteboard effect. NS/C++ exceptions escaping the entry normalize to native_exception. Content snapshots, scoped budgets and per-call pools preserve input/error/result ownership and restore TLS. Actual file access and UIPasteboard thread/privacy/device behavior require qualification.

## Verification

All 62 workflow runners (36 source-contract, 26 native) have passed on Windows. The full sweep passed 61 and hit a Windows EPERM while deleting helper-transport.exe after that runner's native checks succeeded; its focused rerun, including cleanup, passed without source changes. All 521 direct workflow source-grep assertions, expanded standards-conforming assert preprocessing and git diff --check pass. Final focused native-budget/extraction and assert checks pass after whitespace normalization. The assert checker retains its rejecting negative control. Sixteen artifact-only checks require CI outputs. No warning or sanitizer checks were disabled. Windows cannot execute the new macOS/Foundation/ARC/sanitizer branches.

New macOS coverage compiles the actual shared image backend, original signature helper, full RAW parser, direct entry and complete keyboard JS branch. The d516066 frozen keyboard bridge and existing unchanged C02b41 backend/task fragments supply the old oracle. Source guards reconstruct and compare the complete backend after helper extraction, ignoring only trailing line whitespace removed from moved source. The shared controlled pasteboard records published item bytes/UTIs and effects; file metadata, file reads and signature detection use real Foundation and unique temporary fixture files. Tests never modify the real pasteboard.

Coverage includes 160 ordinary calls across four formats; byte/UTI/reply parity; Unicode/;; file paths and extension-independent sniffing; empty/missing/directory/truncated/unsupported files; real exact 16-MiB and sparse over-limit fixtures; absent pasteboard; missing/empty/NSNull/non-string content; exact/over-limit input, NUL/encoding and exact/short output; one task-24/owner-denial gate; initial/gate/provider cancellation/deadline; NS/C++ faults before/after publication; conversion cancellation; mutable content snapshots; retained item/result/error lifetimes and RAW branch parity. Source guards ensure the keyboard bridge contains no RAW dispatch. Existing text/notification regressions remain; the text fixture's kind-8 invalid-input comparison now expects the direct route.

## Acceptance and remaining work

The user reported corrected C02b43 build success at d516066; that does not qualify the new image path. Build rootfull/roothide and compare typed/helper keyboard image calls with RAW task 24 using real images, Unicode/delimiter paths, malformed/empty/large files, exact errors/ACK, permissions and missing pasteboard. Verify actual UTI/bytes and cross-app paste behavior separately from ACKs, including caller stop/output failures after accepted publication. Recheck clipboard text and keyboard notification routes. Measure bridge overhead separately from filesystem/pasteboard work. Continue other P0-13 adapters and metadata codecs/copies, P1-40 invalidation and P0-12 qualification/unknown-start cases; C02 remains partial.
