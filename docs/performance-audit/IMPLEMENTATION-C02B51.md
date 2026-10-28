# C02b51 — direct VPN query/control adapter

Date: 2026-10-28 (Asia/Bangkok). Baseline: `2b06a1f`, containing C02b50 and its legacy Unicode conversion correction; the user reported that build passed.
Status: **source implemented; new macOS/Foundation/ARC/sanitizer CI and device qualification pending**.
Finding: **P0-13, connectivity VPN query/set, task 59**. C02 remains partial.

## Result and compatibility

The rootfull/roothide JS connectivity branch routes VPN through the existing TLinkExecuteNativeRadioState entry. Its allowlist and numeric dispatch now include task 59, calling vpnTaskWithAction. Ordinary VPN queries/sets avoid full RAW task/payload assembly, encoding/parsing, processTaskWithContext, CF stream creation and response-vector accumulation/copy. Existing state/error formatting and JS metadata decoding remain; this does not eliminate every codec or copy. No latency, CPU, allocation or RSS improvement has been measured. Production TrollStore and TouchPOC adapters are unchanged; shared safety checks remain in their workflows.

RAW task 59 still calls vpnTaskFromRawData. Its action/value parser and action-2 diagnostics branch remain in place; only the existing query/control tail becomes a shared numeric helper. Preserve query -> query, true -> connect, false -> disconnect, nonempty broker-result precedence over broker error, empty/nil-result errors and fallback messages. Keep intValue/boolValue normalization, query-versus-set selection for missing/NSNull values, enabledKey/value metadata and ignored extra JS arguments. Broker replies remain opaque text rather than being restricted to a new boolean schema.

The broker transport is unchanged, including loopback port, socket deadlines, request writes, response bound and parsing. Diagnostics retain their broker request and local fallback/error behavior; no new diagnostic method or entitlement policy is added. Source guards compare the broker and RAW task handler exactly against frozen 2b06a1f fragments, reconstruct the original VPN parser/core after removing only extraction glue, and compare the complete JS branch after removing its added VPN allowlist member.

## Authority, effects and lifetime

Query and set retain one ordinary task-59 gate. Owner authorization does not bypass it; disconnect is not a cleanup exemption. The shared entry inherits caller cancellation/deadline/output with response capture disabled. Task 59 adds no C01-local deadline. Stop checks bracket the gate and follow the opaque broker call. No socket scheduling, new cancellation propagation, timeout extension, retry or rollback is introduced.

The broker may accept a connect/disconnect before caller stop, output failure or a transport/provider fault is reported. Preserve that uncertainty rather than retrying automatically. Escaping NS/C++ faults normalize to native_exception in the direct entry. Broker error replies use the existing bounded C-string-compatible formatter, preserving embedded NUL/encoding and output accounting; other radio error routes stay unchanged. Successful replies reuse the existing query formatter and metadata helper. Per-call pools and retained results preserve input/provider/error lifetime.

## Verification

All 62 workflow runners (36 source-contract, 26 native), 521 direct source-grep assertions, expanded standards-conforming assert preprocessing and git diff --check pass on Windows. Focused native-budget/extraction and VPN P0/P1/P2 checks pass. Sixteen artifact-only checks require CI outputs. New macOS/Foundation/ARC/sanitizer compilation/runtime cannot run on this host and remain pending CI; warnings and sanitizers stay enabled.

The new Foundation fixture compiles the actual VPN RAW parser, diagnostics routing and extracted query/control helper with the actual shared task entry/JS branch. Frozen 2b06a1f core/task/JS fragments provide independent compatibility paths. Broker and diagnostics-provider boundaries are controlled; no socket is opened, no real VPN changes and no entitlement probe runs in this fixture. The existing VPN phase suites retain their contract coverage. The shared C-string formatter receives a forward declaration before the radio entry, with an always-host include-order guard.

Coverage includes 160 ordinary query/connect/disconnect cases; missing/NSNull/string/custom boolValue inputs; metadata-key collisions and ignored arguments; nonempty-result/error precedence, nil/empty result and default/error bodies; Unicode/delimiter/NUL/encoding and exact output limits; ordinary authority/owner denial; pre/gate/boolValue/provider cancellation/deadline; committed effects before stop/output failure; NS/C++ faults before/after controlled commits; all RAW action shapes and malformed arguments, diagnostics success/local fallback/encoding failure; error/result pool lifetime and immutable result snapshots; and 128 repeated lifecycles. Existing radio fallback/invalid-task probes move from newly supported task 59 to task 60; Wi-Fi/Bluetooth/Airplane/Cellular coverage remains.

## Acceptance and remaining work

Build rootfull/roothide with C02b51 and compare typed/helper VPN query/set with RAW task 59 against a controlled owned profile/broker. Qualify real socket timeout/disconnect/error behavior, broker effects after caller stop and response/metadata parity. Recheck RAW diagnostics and all other radio operations. Measure bridge overhead separately from broker waits and VPN state transitions. Other P0-13 adapters and metadata codecs/copies, P1-40 invalidation and P0-12 qualification/unknown-start cases remain open.
