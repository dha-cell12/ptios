# C02b33 — direct killApp task

Date: 2026-10-28 (Asia/Bangkok). Baseline: `1e5c795` (C02b32 source); the user reported C02b32 built successfully.
Status: **user reported build success before C02b34; independent device/performance qualification pending**.
Finding: **P0-13, task-31 application-termination adapter**. Other adapters and performance qualification remain open.

## Result and compatibility

The rootfull/roothide killApp bridge calls TLinkExecuteNativeKillApp after existing bundle-ID validation. It shares the ordinary app entry with tasks 32/33/50/52, retaining immutable input snapshots, prefix-inclusive UTF-16/UTF-8 limits, encoding/NUL rejection and non-ASCII %s compatibility. The private entry is named for app calls rather than queries because task 31 has an effect. openApp retains its RAW adapter.

Process exposes killAppForBundleIdentifier. The RAW parser delegates after its original %s decoding. The termination helper is unchanged and checked against frozen source: missing application fails, kill takes precedence, terminate is used only when kill is unavailable, and neither selector produces the existing unable-to-terminate error. A thrown selector does not cause fallback or retry. Missing-bundle and termination error strings remain unchanged.

The typed path removes full RAW request formatting/encoding, processTaskWithContext dispatch, compatibility CF stream and response-vector accumulation/copy. Success retains exactly ok/raw/parts with `0\r\n` and no query metadata; errors use the existing bounded compatibility reply parser. The RAW task-31 body is unchanged and checked against frozen source.

Production TrollStore and TouchPOC execution sources are unchanged; both build workflows run the shared safety suites. No measured CPU, allocation, latency or RSS improvement is claimed.

## Authority, effects and lifetime

Invalid ingress is rejected before one ordinary task-31 license gate and application lookup. The shared child context inherits caller owner fields, deadline and output settings with response capture disabled. Check stop before/after the gate and after the opaque Process call; reply admission checks output and stop. Owner automation authorization does not bypass the gate. Task 31 is not cleanup-exempt.

The successful ACK confirms invocation of the existing void selector, not verified process exit. Accepted lookup/selector work remains synchronous and cannot be preempted by this adapter. Cancellation, deadline expiry, an exception after dispatch or output rejection can produce an error after the effect has committed. Preserve that behavior without retries, rollback, a new stop check between lookup and dispatch, or a process-exit wait. NS/C++ exceptions normalize to native_exception.

Per-call pools drain temporaries while retaining the returned dictionary outside the pool. Input is copied before backend work. Error/result lifetime and mutation of the original mutable input are covered. Output limits do not bound private-provider or Foundation temporary allocation.

## Verification

All 62 workflow runners (36 source-contract, 26 native), 521 direct workflow source-grep assertions, expanded standards-conforming assert preprocessing and git diff --check pass on Windows. The full sweep passed 61 runners; helper-transport completed its assertions but hit Windows EPERM deleting its temporary executable, then passed on a focused rerun including cleanup. The assert checker retains its rejecting negative control. Sixteen artifact-only checks require CI outputs. No warning or sanitizer checks were disabled. New Foundation/ARC/ASan/UBSan branches cannot execute on this Windows host.

New macOS coverage compiles the actual selector helper, Process parser/core, bridge and shared entry against fake application objects. It compares frozen bridge/task/core/helper oracles, complete replies, normalized bundle IDs, license/lookup counts, selector-query order and recorded fake effects. It never terminates real applications on the test host.

Coverage includes 160 ordinary cases; both/kill-only/terminate-only/neither/missing applications; exact and short output; exact/over-limit ASCII/CJK/emoji ingress; malformed/NUL/encoding inputs; ordinary license denial including owner authorization; cancellation/expiry before the gate and during the gate, lookup or committed selector; NS/C++ faults before/after the fake effect; RAW parser behavior; immutable snapshots; and NSError/result lifetime across pool teardown. Existing appPid/appState/appInfo/appPaths/frontmost/path fixtures cover the expanded shared classifier and entry.

## Acceptance and remaining work

The user reported this checkpoint built successfully before C02b34. The working source is based on HEAD `1e5c795` with C02b33 changes; no C02b33 commit was present when C02b34 began. The next source checkpoint is IMPLEMENTATION-C02B34.md; the build report does not replace SpringBoard/device/performance qualification.

The user reported C02b32 build success at baseline `1e5c795`; that report does not qualify the new task-31 path. Build rootfull/roothide variants and compare typed/helper killApp with RAW task 31 using disposable test applications, including missing and unsupported applications. Check selector availability, exact replies, license denial/revocation, input/output limits and caller stop/deadline. Treat uncertain results as potentially committed; do not retry automatically. Recheck shared app-query replies. Measure bridge overhead separately from SpringBoard lookup and application lifecycle work. Continue other P0-13 adapters, P1-40 invalidation and P0-12 qualification/unknown-start cases; C02 remains partial.
