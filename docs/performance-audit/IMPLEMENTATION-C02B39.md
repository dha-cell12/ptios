# C02b39 — direct airplane and cellular state adapters

Date: 2026-10-28 (Asia/Bangkok). Baseline: `4c7e249`, containing C02b38; the user reported C02b38 built successfully.
Status: **user reported build success before C02b40 at source baseline `86c0974`; independent device/performance qualification pending**.
Finding: **P0-13, task-57/58 connectivity adapters**. Other adapters and performance qualification remain open.

## Result and compatibility

The rootfull/roothide connectivity bridge now routes Airplane Mode and Cellular Data through the shared direct radio entry alongside Wi-Fi/Bluetooth. The entry accepts exactly tasks 55/56/57/58 and retains ordinary query/set normalization, one task-specific license gate and the existing bounded Reply formatter. JS boolValue conversion, enabledKey/value augmentation and metadata-key behavior remain unchanged. Other connectivity tasks, including VPN, retain RAW formatting/dispatch.

Connectivity exposes airplaneTaskWithAction and cellularDataTaskWithAction. Their RAW wrappers keep the existing action/value parser before delegating to the numeric cores. Provider bodies and task-57/58 RAW handlers are checked against frozen source. No selector, framework, entitlement, cache or new state-verification policy is introduced.

Airplane Mode retains RadiosPreferences first, followed by SBAirplaneModeController only if the first lookup/singleton produces no instance. An existing controller with unavailable setters/getters does not trigger controller fallback. Preserve sharedInstance/sharedManager availability precedence, setter/getter spelling order, false getter results and requested-value fallback when getters are absent. Cellular Data retains its single RadiosPreferences path, setCellularDataEnabled:/cellularDataEnabled selectors and existing unavailable-control/setter errors. It does not gain the alternate Airplane controller.

The typed path removes full RAW request formatting/encoding, action/value string parsing, processTaskWithContext dispatch, compatibility CF stream and response-vector accumulation/copy for tasks 57/58. Result metadata copying remains. Query fallback remains zero; set fallback remains the requested value when no getter is available. A fallback reply is not independent confirmation that hardware state changed.

Production TrollStore and TouchPOC execution sources are unchanged; both build workflows run the shared safety suites. No measured CPU, allocation, latency or RSS improvement is claimed.

## Authority, effects and lifetime

Query and set each retain one ordinary license gate for their task number. Owner automation authorization does not bypass it. The shared child context inherits owner fields, deadline and output settings with response capture disabled. Check stop before/after the gate, after opaque provider work and after bounded reply formatting. Unsupported native task numbers fail before the gate. No C01-local timeout, cleanup exemption or compute admission is added.

Private class/singleton/setter/getter operations remain synchronous and cooperative. Accepted setter work can commit before caller cancellation/deadline, output rejection or an exception is reported. No stop check is inserted inside the unchanged provider bodies, and no automatic retry or rollback follows an uncertain effect. NS/C++ exceptions escaping the backend normalize to native_exception. Per-call pools retain results outside the pool; NSError/metadata lifetime across provider/context teardown is covered. Existing manager thread/queue requirements and hardware effects require device qualification.

## Verification

All 62 workflow runners (36 source-contract, 26 native), 521 direct workflow source-grep assertions, expanded standards-conforming assert preprocessing and git diff --check pass on Windows. The assert checker retains its rejecting negative control. Sixteen artifact-only checks require CI outputs. No warning or sanitizer checks were disabled. New Foundation/ARC/ASan/UBSan branches cannot execute on this Windows host.

New macOS coverage compiles actual Airplane/Cellular parsers and numeric cores using the actual/frozen radio helpers from C02b38, plus the real bridge/shared entry. Controlled Objective-C managers and independent primary/alternate availability/factory/selector configurations provide the provider boundary. Frozen core/task fragments and the existing frozen connectivity bridge supply the old oracle. It compares complete replies, primary/alternate lookup and selector order, fake state/effects, boolValue reads and license counts. No real radio state is changed.

Coverage includes 160 ordinary cases; primary and alternate class/singleton availability; nil sharedInstance without same-class fallback; Airplane controller fallback versus unavailable selector behavior; Cellular absence of alternate lookup; setter/getter masks and false getters; applied/unapplied setters; query/BOOL normalization and metadata key collisions; exact/short output; ordinary license/owner denial; pre-cancel/expiry, gate-time stop and conversion-time cancellation; stop/deadline during accepted provider work; NS/C++ faults before/after effects and during alternate lookup; permissive RAW parsing/errors; and NSError/result pool lifetime. Wi-Fi/Bluetooth fixtures retain their shared-entry regression coverage; invalid-task and non-radio RAW fallback cases now use task numbers outside 55..58.

## Acceptance and remaining work

The user reported this checkpoint built successfully before C02b40; source baseline is `86c0974`. The next source checkpoint is IMPLEMENTATION-C02B40.md. The build report does not replace controller/radio/device/performance qualification.

The user reported C02b38 build success at baseline `4c7e249`; that report does not qualify the new task-57/58 paths. Build rootfull/roothide variants and compare typed/helper Airplane/Cellular query/set with RAW tasks 57/58 across available controller layouts, unsupported selectors and denied/unchanged state. Verify controller fallback order, exact replies/metadata, license denial/revocation, output limits and caller stop/deadline. Qualify manager thread requirements and actual hardware state without automatically retrying uncertain changes. Recheck Wi-Fi/Bluetooth and VPN/non-radio RAW routes. Measure bridge overhead separately from private-controller work. Continue remaining P0-13 adapters, metadata copies/codecs, P1-40 invalidation and P0-12 qualification/unknown-start cases; C02 remains partial.
