# C06u — one hello snapshot per supervisor probe

Date: 2026-11-02 (Asia/Bangkok). Baseline: `a2743730`; user reported C06t build passed and requested continued implementation. Production StreamControl only; TouchPOC excluded.

## Probe-local reuse

After task 97, the supervisor reads PID through task 60. If `proc_pidpath` fails for a positive PID, it then sends task 60 again and decodes a second JSON response for `launch_executable_path`. This adds another bounded socket transaction and can combine one process's PID with a replacement process's reported path.

Extract the common hello decoder and keep its result local to one probe. Read PID and the fallback path from that same dictionary. With a positive PID and failed `proc_pidpath`, one probe now uses two task transactions and one JSON decode instead of three transactions and two decodes. Successful `proc_pidpath` and missing-status paths do not add or remove reads. These are source/fixture operation counts, not device latency measurements.

Retain the independent PID/path selector names and their fresh-read behavior for separate callers. No process-wide cache, timer, property or cross-probe reuse is added. Every later probe reads task 97 and a fresh hello. Root-dictionary validation, PID `intValue`, path string checks, base64/JSON/error handling and ordinary result ownership remain.

Probe decisions, path canonicalization, current/stale service markers, `proc_pidpath` precedence, state changes, logs, delegate events and replacement policy retain their preceding source. Under a changing daemon, using a coherent PID/path pair intentionally replaces the old mixed-response behavior. Status task 97 and task 60 are still separate transactions; this does not make their data atomic or attest process identity. Existing nonpositive-PID policy remains. C06t per-call budgets, helper ownership and all lifecycle/fallback/watchdog code remain.

Queue residence, multiple sequential probes, active cancellation, coalescing and overall ensure/restart deadlines remain open. C06/P0-23 are partial.

## Verification

Freeze the complete preceding PID/path/probe methods. A staged restoration verifies the entire prior supervisor SHA256 and feeds the existing C06t/C06e/C06c chain. An additional exact comparison preserves the full probe decision/effect body except the snapshot read and fallback field access. Add the safety runner to root and production TrollStore workflows; fixture extraction also runs on Windows.

The macOS Foundation/ARC/ASan/UBSan fixture compiles complete current/frozen methods with controlled socket/process providers and real Foundation base64/JSON/path operations. It compares 240 PID/path/process-path combinations, malformed/empty hello and outdated/missing status, full state/log/event output, independent selector freshness, one-versus-two decode/read counts and 1000 repeated probe lifecycles. A scripted daemon change verifies the first probe uses the first PID/path pair and the next probe reads the new pair, while the frozen code combines the first PID with the second path. There is no installed daemon, real process lookup, service launch/stop or privileged effect.

Windows validation: all **80 workflow runners** (36 source, 44 safety), **521 existing workflow source checks**, staged full-supervisor/earlier checkpoint hashes, fixture extraction, JavaScript syntax, expanded assert preprocessing and `git diff --check` pass. Sixteen artifact-only checks skipped. New Apple compilation/native execution/iOS builds require macOS CI. Device latency, real process-boundary fallback and private platform qualification remain pending.
