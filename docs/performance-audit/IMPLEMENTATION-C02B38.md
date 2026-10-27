# C02b38 — direct Wi-Fi and Bluetooth state adapters

Date: 2026-10-28 (Asia/Bangkok). Baseline: C02b37 working source based on HEAD `aed36da`; the user reported C02b37 built successfully. Its existing uncommitted changes are retained. Connectivity oracle fragments use `aed36da`, where those fragments were unchanged through C02b37.
Status: **user reported build success before C02b39 at source baseline `4c7e249`; independent device/performance qualification pending**.
Finding: **P0-13, task-55/56 connectivity adapters**. Other adapters and performance qualification remain open.

## Result and compatibility

The rootfull/roothide connectivity bridge routes only tasks 55/56 to TLinkExecuteNativeRadioState. Missing/NSNull value remains a query; other values use the existing boolValue conversion once and normalize to 0/1. Existing enabledKey/value metadata augmentation remains unchanged, including custom keys and collisions. Other connectivity task numbers retain their RAW formatting and dispatch. No public method or task whitelist outside this direct branch is changed.

Connectivity exposes wifiTaskWithAction and bluetoothTaskWithAction. RAW wrappers retain the unchanged action/value parser, then delegate to these numeric cores. The parser, singleton/selector helpers, provider bodies and task-55/56 RAW handlers are checked against frozen source. Preserve SBWiFiManager/BluetoothManager lookup, sharedInstance then sharedManager availability precedence, and no fallback when an available sharedInstance returns nil.

Preserve Wi-Fi setter/getter spelling precedence and Bluetooth powered/enabled precedence. Getter availability is distinct from its returned BOOL: an available getter returning false does not trigger another getter. Missing getters retain the existing requested-value fallback; queries use zero. Existing missing-manager and unavailable-setter errors remain exact. A successful setter dispatch or fallback response does not independently confirm hardware state. No framework loading, cache, retry, new provider policy or state verification is introduced.

The typed path removes full RAW request formatting/encoding, action/value string parsing, processTaskWithContext dispatch, compatibility CF stream and response-vector accumulation/copy. It uses the existing Reply formatter for bounded raw/parts, then the unchanged JS state helper. The result dictionary copy for enabledKey/value remains. Other radio/connectivity paths, including airplane, cellular and VPN, remain RAW.

Production TrollStore and TouchPOC execution sources are unchanged; both build workflows run the shared safety suites. No measured CPU, allocation, latency or RSS improvement is claimed.

## Authority, effects and lifetime

The numeric entry rejects tasks other than 55/56 before one ordinary task-specific license gate and provider access. Both query and set retain that gate; owner automation authorization does not bypass it. The child context inherits owner fields, deadline and output settings with response capture disabled. Check stop before/after the gate, after the opaque provider call and after bounded reply formatting. No C01-local timeout or cleanup exemption is added.

Singleton/setter/getter calls remain synchronous and cooperative. Accepted work can set a radio before caller cancellation/deadline, output rejection or an exception is reported. No new stop check is inserted inside the preserved provider body, and no automatic retry or rollback follows an uncertain effect. A false getter can report that the requested change did not take effect; the existing no-getter fallback can report the requested value without hardware confirmation. NS/C++ exceptions escaping the provider normalize to native_exception.

JS boolValue conversion remains before native-entry admission. Cancellation during that conversion is checked before the license gate/provider. Per-call pools retain the raw result outside the pool; metadata and NSError lifetime across provider/context/pool teardown are covered. Output caps bound wire admission rather than Foundation/provider temporary allocation. Existing thread/queue requirements of the private managers remain subject to device qualification.

## Verification

All 62 workflow runners (36 source-contract, 26 native), 521 direct workflow source-grep assertions, expanded standards-conforming assert preprocessing and git diff --check pass on Windows. The assert checker retains its rejecting negative control. Sixteen artifact-only checks require CI outputs. No warning or sanitizer checks were disabled. New Foundation/ARC/ASan/UBSan branches cannot execute on this Windows host.

New macOS coverage compiles actual parser/helpers/provider bodies, the bridge/state helper and numeric entry against controlled Objective-C singleton/managers. The production Connectivity header supplies numeric-core prototypes. Frozen bridge/task/helper/core fragments provide the old oracle. It compares complete responses, class/factory/set/get order, effects/state, boolValue read counts, gate counts and exact fallback RAW payloads. No real radios are changed.

Coverage includes 160 ordinary cases; class/instance/factory availability and precedence; setter/getter masks and false getters; applied/unapplied setters and no-getter fallback; query/BOOL normalization, custom value conversion and metadata key collisions; exact/short output; ordinary license/owner denial; pre-cancel/expiry, gate-time stop and conversion-time cancellation; stop/deadline during accepted provider work; NS/C++ faults before/after effects; permissive RAW action/value parsing and missing-value errors; NSError/result pool lifetime; invalid typed tasks; and other-task RAW fallback, including wide/negative task formatting. Existing app/device/list/frontmost/path fixtures retain shared formatter regression coverage.

## Acceptance and remaining work

The user reported this checkpoint built successfully before C02b39; the combined C02b37/C02b38 source is committed as `4c7e249`. The next source checkpoint is IMPLEMENTATION-C02B39.md; the build report does not replace manager/radio/device/performance qualification.

The user reported C02b37 build success before this checkpoint; that report does not qualify the new task-55/56 paths. Build rootfull/roothide variants and compare typed/helper Wi-Fi/Bluetooth query/set with RAW tasks 55/56 across available singleton/set/get selector layouts, denied/unchanged state and missing managers. Check exact replies and enabledKey/value metadata, license denial/revocation, output caps and caller stop/deadline. Qualify actual manager thread requirements and observed hardware state without automatically retrying uncertain changes. Recheck other connectivity RAW routes. Measure bridge overhead separately from private-manager work. Continue remaining P0-13 adapters, metadata copies/codecs, P1-40 invalidation and P0-12 qualification/unknown-start cases; C02 remains partial.
