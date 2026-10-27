# C02b35 — direct listBundles task

Date: 2026-10-28 (Asia/Bangkok). Baseline: `68cd857`, containing C02b34; the user reported C02b34 built successfully.
Status: **user reported build success before C02b36 at source baseline `5d4c67a`; independent device/performance qualification pending**.
Finding: **P0-13, task-53 installed-application-list adapter**. Other adapters and performance qualification remain open.

## Result and compatibility

The rootfull/roothide listBundles bridge calls TLinkExecuteNativeListBundles with its existing BOOL conversion. The new ordinary entry calls listBundlesWithInfo directly, without a full RAW request, processTaskWithContext dispatch, compatibility CF stream or response-vector accumulation/copy. The RAW parser retains optional/null input, %s decoding and the exact intValue==1 rule before delegating to the same core. The RAW task body is unchanged and checked against frozen source.

The enumeration/encoding core is unchanged after extraction and checked against frozen source. Keep LSApplicationWorkspace/defaultWorkspace availability errors; allInstalledApplications precedence; allApplications fallback only when the preferred selector is unavailable; nil/no-selector empty lists; ordering, duplicates and filtering of empty bundle IDs. Preserve selector/KVC differences, swallowed KVC NSExceptions, safe-string conversions, metadata fields, comma-pair joining and JSON/base64 encoding/failures. No cache, sorting, deduplication, new enumeration policy or codec schema is introduced.

The shared string formatter adds an explicit Reply mode, retaining raw/parts without adding scalar/query metadata. It keeps UTF-8 wire bounds, first-NUL truncation, delimiter splitting, newline trimming and unusual-response compatibility. Existing formatter modes are unchanged. The JS metadata decoder and result augmentation are unchanged and checked against the frozen bridge: bundleIds uses the first body part and comma-pair split; withInfo decodes base64 JSON and supplies an items array. Backend string assembly, JSON/base64 encode/decode and metadata dictionary copy remain in this checkpoint.

Production TrollStore and TouchPOC execution sources are unchanged; both build workflows run the shared safety suites. No measured CPU, allocation, latency or RSS improvement is claimed.

## Authority and lifetime

One ordinary task-53 license gate precedes workspace work. The child context inherits caller owner fields, deadline and output settings with response capture disabled. Check stop before/after the gate, after the opaque Process call and after bounded reply formatting. Owner automation authorization does not bypass the gate. No C01-local timeout, cleanup exemption, automatic retry or compute admission is introduced.

Workspace/property enumeration and serialization remain synchronous and cooperative. Cancellation/deadline during those opaque operations is observed on return, not by preempting private selectors or Foundation serialization. Output admission bounds the wire response, not provider arrays/strings, JSON/base64 temporaries or decoded metadata. Existing post-entry JS decoding remains unchanged. NS/C++ exceptions escaping the backend normalize to native_exception; deliberate KVC NSException catches retain their existing behavior.

Per-call pools drain temporaries while retaining the raw result outside the pool. The bridge retains decoded metadata after provider/context/pool teardown. NSError writeback lifetime is covered separately.

## Verification

All 62 workflow runners (36 source-contract, 26 native), 521 direct workflow source-grep assertions, expanded standards-conforming assert preprocessing and git diff --check pass on Windows. The assert checker retains its rejecting negative control. Sixteen artifact-only checks require CI outputs. No warning or sanitizer checks were disabled. New Foundation/ARC/ASan/UBSan branches cannot execute on this Windows host.

New macOS coverage compiles the actual bridge/entry, Process parser/core and safe-string helper with controlled workspace/proxy objects and real Foundation codecs. Frozen bridge/task/core/helper fragments supply the old oracle. It compares full plain-list/error replies, enumeration/property order and license counts. JSON object key order is unspecified, so info-mode parity compares decoded objects/items and checks the exact wire against that invocation's captured production serialization bytes. It does not impose a new JSON ordering contract.

Coverage includes 160 ordinary cases; class/default-workspace/instance availability; preferred/fallback/no selector and nil preferred result; selector masks/KVC and swallowed exceptions; numeric/missing metadata; empty and Unicode IDs; comma-pair/task delimiters, newline and embedded NUL; JS BOOL normalization; exact/short output; ordinary license/owner denial; pre-cancel/expiry, gate-time stop, cancellation/expiry during opaque work; NS/C++ boundary faults; nil-data/error JSON failures; RAW null/intValue parsing; and NSError/decoded-result pool lifetime. Existing app/frontmost/path fixtures retain shared formatter regression coverage. No real LS inventory is accessed by the new fixture.

## Acceptance and remaining work

The user reported this checkpoint built successfully before C02b36 (`5d4c67a`). The next source checkpoint is IMPLEMENTATION-C02B36.md; the build report does not replace LS/device/performance or large-inventory memory qualification.

The user reported C02b34 build success at baseline `68cd857`; that report does not qualify the new task-53 path. Build rootfull/roothide variants and compare typed/helper listBundles with RAW task 53 for empty/ordinary/large inventories, both modes, supported selector/KVC layouts, missing workspace and license denial/revocation. Verify exact plain-list replies, decoded JSON schema/items, wire caps and caller stop/deadline. Confirm metadata survives pool teardown. Measure bridge overhead separately from LS enumeration and serialization; qualify large-inventory memory before considering removal of the remaining metadata codec/copy. Continue other P0-13 adapters, P1-40 invalidation and P0-12 qualification/unknown-start cases; C02 remains partial.
