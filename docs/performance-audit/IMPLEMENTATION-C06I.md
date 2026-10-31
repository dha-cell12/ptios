# C06i — narrow TrollStore VPN admission preflight

Date: 2026-10-31 (Asia/Bangkok). Baseline: `392a20bd`; user reported the build passed, including the C06h implementation and subsequent helper/background-task fixture corrections. This checkpoint addresses **P1-70** for production TrollStore brokers 6015/6016. TouchPOC excluded.

Status: Windows source/portable regression validation. New Foundation/GCD/ARC/ASan/UBSan assertions and iOS builds require macOS CI; device performance qualification remains independent.

## Admission work

Add shared `TLinkVPNControlPreflight()`, returning only the existing entitlement and framework dictionaries. Evaluate those providers in their preceding order. Successful immutable process entitlement probes already use the C04a/C04k memo; unresolved/error reads retain their retry behavior. The existing framework provider still probes manager-class availability on each call, with its preceding one-time framework-load behavior. No new readiness or connection-state cache is added.

Ordinary foreground and vpnagent commands use this view for their unchanged entitlement-ready predicates. They no longer construct a full diagnostic envelope, call the private compatibility diagnostic probe or collect its bundle/marker/timestamp evidence merely to decide admission. Foreground still requires allow_vpn and manager availability; vpnagent still additionally requires private_configuration_super and managed_vpn_keychain_access. License and foreground checks retain their original position and errors. Unknown ordinary commands retain their preceding authorization order; ping/diagnostics exemptions remain.

The full diagnostics branch still uses its original preflight and complete reply formatting. Preserve fresh marker evidence, generated timestamp, status read, private compatibility and other diagnostic fields. The actual VPN manager still reads mutable profile/connection/marker state and loads its private store bundle on its own backend path; it does not depend on a diagnostic probe to initialize that store. Removing incidental diagnostic work from ordinary admission does not remove backend validation. Diagnostic-only faults no longer occur on that admission path, while entitlement/framework/backend faults keep their existing boundaries.

Client/manager caps, pending mutation lanes, request/phase deadlines, output policy, agent identity/startup, fallback routing and signed/runtime authority remain unchanged. Rootfull/roothide callers are not switched to the new API. The shared helper adds no background task, timer, process-wide diagnostic snapshot or durable state.

## Verification

Extend the two existing VPN cache/broker runners; total workflow runner count stays unchanged. `vpn-control-preflight-baseline.mjs` reverses the additive shared API/header and one admission expression in each broker, then hashes their complete preceding sources. Existing C04a/C04k entitlement and C06h/C04 broker guards continue from that restored stage. Full diagnostic/private compatibility functions are byte-preserved. Runtime fixture extraction still compiles the actual current broker/API source.

New native cases extend the existing Foundation tests:

- Actual two-field API with the real extracted entitlement memo under controlled SecTask/CF providers. Check cold resolution, 10k warm reads and 8k concurrent reads reusing the immutable entitlement dictionary, while the framework provider is invoked every time. Hold an unavailable framework snapshot across readiness recovery and pool drainage. Verify task failure, unresolved entitlement retry and NS/C++ framework faults recover without a new memo or changed CF ownership.
- Both actual broker response functions compare frozen ordinary replies for success, denial, missing entitlement, unavailable framework, inactive foreground, manager failure and diagnostic/ping commands. Check that ordinary admission constructs zero full snapshots versus one in the frozen path; diagnostics still constructs one, with unchanged decoded metadata.
- Query reflects a changed connection result on the next request; framework availability can recover without restart. Denied/inactive callers do not reach preflight/manager. Retain deadline consumption, callback/operation/mutation ownership and socket/queue matrices from C06h.

The control helper is compiled from its actual extracted body in both native fixtures, rather than replacing it with a ready boolean. Entitlement-cache tests retain controlled framework providers; broker tests retain controlled entitlement/framework/manager providers. No real entitlement, VPN/profile/radio, bundle or installed marker is changed by these tests.

Windows validation: all **75 workflow runners** (36 source, 39 safety), **521 existing source checks**, fixture extraction, JavaScript syntax, expanded assert preprocessing and `git diff --check` pass. Sixteen artifact-only checks are skipped. New Foundation/ARC/sanitizer counts/assertions are pending macOS CI; source-level avoided probe/envelope work is not a measured CPU/IO/allocation/RSS/power/latency result.

## Remaining work

P1-70 has an admission-path source implementation, pending native/device qualification. Full diagnostics intentionally continues its dynamic work. Status coalescing, fully asynchronous broker waits, cross-process mutation/fallback deduplication, backend/private polling, shared HTTP cancellation and active supervisor cancellation remain open. The preflight still allocates a narrow dictionary and probes framework availability; it does not bound opaque provider work or add a new end-to-end deadline.
