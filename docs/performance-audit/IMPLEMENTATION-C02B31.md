# C02b31 — direct appInfo query

Date: 2026-10-27 (Asia/Bangkok). Baseline: `aca0719`; the user reported C02b30 built successfully.
Status: **build reported passed by the user before C02b32; published source baseline `0bad9fe`; independent device/performance qualification pending**.
Finding: **P0-13, task-33 application-info adapter**. Other adapters and performance qualification remain open.

## Result and compatibility

The rootfull/roothide appInfo bridge calls TLinkExecuteNativeAppInfo after the existing bundle-ID validation. It shares the app-query entry with appPid/appState, retaining immutable input snapshots, prefix-inclusive UTF-16/UTF-8 limits, NUL/encoding rejection and non-ASCII %s compatibility conversion. Only task IDs 32/33/50 are accepted by that internal entry. Other app adapters remain on their existing RAW path.

Process exposes appInfoForBundleIdentifier with the existing LSApplicationProxy lookup, localizedName/shortVersionString/bundleVersion reads, empty-field defaults and application-state fallback. The RAW parser delegates to it after its original %s decoding. State retrieval calls the same string-based state core instead of decoding the same RAW input again; lookup order and selector behavior remain. The RAW task-33 body is unchanged and checked against frozen source.

The typed path removes full RAW request formatting/encoding, processTaskWithContext dispatch, compatibility CF stream and response-vector accumulation/copy. Its backend still assembles the legacy multipart string, and the reply still parses compatible columns. This checkpoint does not claim a structured or allocation-free backend result.

The shared query formatter now selects Scalar, State or AppInfo metadata explicitly. AppInfo adds bundleId/name/shortVersion/bundleVersion/state only when at least six response parts exist, directly in the same result dictionary. Preserve ok/raw/parts, signed intValue state conversion, delimiter-induced column shifts, newline trimming, first-NUL truncation and the old unencodable-response empty-writer fallback. A truncated successful reply with fewer columns receives no extra appInfo fields. No running or pid field is added to appInfo. Default Scalar and explicit State preserve existing PID/frontmost/path/state replies.

Production TrollStore and TouchPOC execution sources are unchanged; both build workflows run the shared safety suites. No measured CPU, allocation, latency or RSS improvement is claimed.

## Authority and lifetime

Input rejection precedes the ordinary task-33 license gate and provider work. The shared child context retains caller owner fields, deadline and output settings with response capture disabled. Check stop before one selected gate, after it, after the complete proxy/state operation and after formatting/output admission. Calling the internal state core does not introduce a second task-32 gate. Owner automation authorization does not bypass task-33 authority. No C01-local timeout or compute admission is added.

Proxy/property/state operations remain synchronous, cooperative and opaque; they are not preempted by caller cancellation/deadline. NS/C++ exceptions normalize to native_exception. Per-query autorelease pools retain the reply outside the pool. The output wire budget does not bound private-provider strings, metadata assembly or Foundation temporary allocations. Input, output and existing NSError behavior remain compatible.

## Verification

All 62 workflow runners (36 source-contract, 26 native), 521 direct workflow source-grep assertions, expanded standards-conforming assert preprocessing and git diff --check pass on Windows. The assert checker retains its rejecting negative control. Sixteen artifact-only checks require CI outputs. No warning or sanitizer checks were disabled. New Foundation/ARC/ASan/UBSan branches cannot execute on this Windows host.

New macOS fixtures compile the actual Process metadata/parser core, bridge, shared task entry and formatter against controlled LS proxy objects plus the actual state core/selector fixture. Frozen task/core fragments and the existing frozen app bridge provide the old oracle. Coverage compares complete replies, normalized identifiers, read/authority counts, proxy-property order and state-selector order.

Cases include 160 ordinary applications, absent proxy/app, nil metadata, wide state values, Unicode, unexpected description-compatible property objects, delimiter/newline/NUL/encoding fields, exact/short output caps, a long provider field, exact/over-limit multibyte ingress, invalid arguments, one task-33 gate, stop/deadline, NS/C++ faults at proxy/getter/state boundaries, RAW errors and input/metadata/NSError lifetime across pool teardown. Existing appPid/appState/frontmost/path fixtures cover the shared metadata-mode change. Fixture dependency order is checked on every host. Actual LS/SpringBoard behavior and device/performance acceptance remain pending.

## Acceptance and remaining work

The user reported this checkpoint built successfully before C02b32. That report does not establish device or measured performance acceptance. The next checkpoint is documented in IMPLEMENTATION-C02B32.md.

Build rootfull/roothide variants and compare typed/helper appInfo with RAW task 33 for installed/running/stopped/missing apps and Unicode names/versions. Check exact metadata/error replies, caller stop/deadline, license denial/revocation and input/output caps. Recheck appPid/appState/frontmost/path after the formatter change. Measure bridge overhead separately from LS/state work. Continue other P0-13 adapters, P1-40 invalidation and P0-12 qualification/unknown-start cases; C02 remains partial.
