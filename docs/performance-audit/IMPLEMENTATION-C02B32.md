# C02b32 — direct appPaths query

Date: 2026-10-27 (Asia/Bangkok). Baseline: `0bad9fe` (C02b31 source); the user reported C02b31 built successfully.
Status: **user reported build success before C02b33 at source baseline `1e5c795`; independent device/performance qualification pending**.
Finding: **P0-13, task-52 application-path adapter**. Other adapters and performance qualification remain open.

## Result and compatibility

The rootfull/roothide appPaths bridge calls TLinkExecuteNativeAppPaths after existing bundle-ID validation. It shares the ordinary app-query entry with tasks 32/33/50, retaining immutable input snapshots, prefix-inclusive UTF-16/UTF-8 limits, encoding/NUL rejection and non-ASCII %s compatibility. Open/kill retain their existing RAW adapters.

Process exposes appPathsForBundleIdentifier; the RAW parser delegates after its original %s decoding. Keep the LS proxy lookup, missing-proxy empty pair, bundleURL/dataContainerURL selector checks, KVC paths and containerURL fallback. Selector-returned nil does not enable the KVC-only fallback. KVC dataContainerURL returning NSNull likewise does not count as nil for fallback. Existing KVC NSException catches stay in place; other exceptions retain the typed entry's normalization.

The URL-like helper is unchanged and checked against frozen source: nil/CFNull/non-path objects map to empty strings, NSURL uses its path and other path-capable objects use the existing selector dispatch. No path normalization, cache, filesystem access or new lookup policy is added.

The typed path removes full RAW request formatting/encoding, processTaskWithContext dispatch, compatibility CF stream and response-vector accumulation/copy. Backend multipart string assembly and reply parsing remain. The shared AppPaths metadata mode builds bundlePath/dataPath in the same result dictionary, only when at least two parts exist; a missing third part supplies an empty dataPath. Preserve raw/parts, first-NUL truncation, delimiter-induced column shifts, newline trimming, unencodable-response fallback and missing-path defaults. No bundleId/state/pid alias is added.

The RAW task-52 body is unchanged and checked against frozen source. Production TrollStore and TouchPOC execution sources are unchanged; both build workflows run the shared safety suites. No measured CPU, allocation, latency or RSS improvement is claimed.

## Authority and lifetime

Invalid ingress is rejected before one task-52 license gate and proxy work. The shared ordinary child context inherits caller owner fields, deadline and output settings with response capture disabled. Check stop before/after the gate, after the opaque Process query and after formatting/output admission. Owner automation authorization does not bypass the gate. No C01-local timeout, compute admission, automatic retry or preemption is introduced.

Proxy/selector/KVC/URL-path operations remain synchronous and cooperative. NS/C++ exceptions escaping the backend normalize to native_exception; the backend's deliberate KVC NSException catches keep their existing fallback behavior. Per-query pools drain temporaries while retaining returned metadata outside the pool. Output wire limits do not bound private-provider strings or Foundation temporary allocation.

## Verification

All 62 workflow runners (36 source-contract, 26 native), 521 direct workflow source-grep assertions, expanded standards-conforming assert preprocessing and git diff --check pass on Windows. The assert checker retains its rejecting negative control. Sixteen artifact-only checks require CI outputs. No warning or sanitizer checks were disabled. New Foundation/ARC/ASan/UBSan branches cannot execute on this Windows host.

New macOS coverage compiles the actual parser/core, selector/KVC branches, URL-like helper, bridge, shared entry and formatter against a controlled LS proxy, real NSURL objects and path-capable Foundation objects. Frozen core/task fragments and the existing frozen app bridge provide the old oracle. It compares complete replies, normalized bundle IDs, gate/read counts and operation order.

Coverage includes 160 ordinary cases, four selector masks, nil/NSNull/no-path objects, absent proxy, KVC fallback and swallowed exceptions, escaping NS/C++ boundary faults, custom path objects, multipart/NUL/encoding fields, exact/short output, exact/over-limit Unicode ingress, authority/stop/deadline, RAW errors and input/path/NSError/result lifetime across pool teardown. Existing appPid/appState/appInfo/frontmost/path fixtures cover the expanded shared classifier/formatter. Private LS behavior and device/performance acceptance remain pending.

## Acceptance and remaining work

The user reported this checkpoint built successfully before C02b33 (`1e5c795`). The next source checkpoint is IMPLEMENTATION-C02B33.md; the report does not replace LS/KVC/device/performance qualification.

Build rootfull/roothide variants and compare typed/helper appPaths with RAW task 52 across installed/missing applications and available URL/KVC shapes. Verify exact path fields, caller stop/deadline, license denial/revocation and input/output limits. Recheck other shared query replies after the formatter change. Measure bridge overhead separately from LS/KVC/URL work. Continue other P0-13 adapters, P1-40 invalidation and P0-12 qualification/unknown-start cases; C02 remains partial.
