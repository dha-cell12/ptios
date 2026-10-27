# C02b34 — direct openApp task and launcher ownership

Date: 2026-10-28 (Asia/Bangkok). Baseline: C02b33 working source, based on HEAD `1e5c795`; the user reported C02b33 built successfully. Its existing uncommitted changes are retained.
Status: **user reported build success before C02b35 at source baseline `68cd857`; independent device/performance qualification pending**.
Finding: **P0-13, task-11 application-launch adapter**. Other adapters and performance qualification remain open.

## Result and compatibility

The rootfull/roothide openApp bridge calls TLinkExecuteNativeOpenApp after existing bundle-ID validation. All six methods in the shared app bridge now use direct entries. Task 11 joins the ordinary app entry, retaining immutable input snapshots, prefix-inclusive UTF-16/UTF-8 limits, encoding/NUL rejection and non-ASCII %s compatibility. It calls the existing bringAppForeground string core without a full RAW request, processTaskWithContext dispatch, compatibility CF stream or response-vector accumulation/copy.

The RAW parser still performs its original %s decoding and delegates to bringAppForeground; the RAW task-11 body is unchanged and checked against frozen source. Both task adapters deliberately ignore the launcher's integer return status and retain exactly ok/raw/parts with `0\r\n` after a normal return. The successful ACK does not verify that the application opened. No query metadata is added. Error/denial responses use the existing bounded parser.

The launcher retains its current calling thread, main-thread warning, CF string formatting, logging/timing, lazy SBSLaunchApplicationWithIdentifier lookup, cached function pointer and suspended=false call. It now releases the owned CF string in @finally on normal return, an unavailable symbol and NS/C++ unwind. Failed CF allocation or missing launch symbol returns -1 instead of dereferencing a null function pointer or passing a failed allocation to the launcher. The task adapters continue to acknowledge a normal return; the public core still returns the backend status. This is an explicit safety correction beyond adapter parity. No retries, asynchronous launch, process-exit verification or new resolver cache policy is introduced.

Production TrollStore and TouchPOC execution sources are unchanged; both build workflows run the shared safety suites. No measured CPU, allocation, latency or RSS improvement is claimed.

## Authority, effects and lifetime

Invalid ingress is rejected before one ordinary task-11 license gate and launcher work. The shared child context inherits caller owner fields, deadline and output settings with response capture disabled. Check stop before/after the gate and after the opaque launcher call; reply admission checks output and stop. Owner automation authorization does not bypass the gate. Task 11 is not cleanup-exempt.

Resolver/backend calls remain synchronous and cannot be preempted by this adapter. Accepted work may commit before caller cancellation, deadline expiry, output rejection or an exception after the effect. Preserve that behavior without a new stop check between symbol resolution and launch, retries or rollback. An error after entry can represent an uncertain or committed launch. NS/C++ exceptions normalize to native_exception. The cached function pointer's existing threading/serialization assumptions are unchanged.

Per-call pools retain the result outside the pool. Input is copied before backend work. The CF string lives through the backend call and is released exactly once afterward, including exceptions. Output caps do not bound private-provider or Foundation temporary allocation.

## Verification

All 62 workflow runners (36 source-contract, 26 native), 521 direct workflow source-grep assertions, expanded standards-conforming assert preprocessing and git diff --check pass on Windows. The assert checker retains its rejecting negative control. Sixteen artifact-only checks require CI outputs. No warning or sanitizer checks were disabled. New Foundation/ARC/ASan/UBSan branches cannot execute on this Windows host.

New macOS coverage compiles the actual Process launcher/parser, bridge and shared entry with a controlled resolver/backend and real CF strings. Frozen bridge/task/core fragments provide the old oracle for supported paths. The frozen core's known leaked string is reclaimed by the fixture after each oracle call, preserving the oracle's source and call behavior. The actual core must have zero outstanding strings on return. Missing-symbol/allocation and exception cleanup cases assert the new safety behavior separately; they do not execute the unsafe legacy path. No real applications are launched.

Coverage includes 160 ordinary cases; cached and lazy resolution; signed/nonzero launcher results with unchanged ACK; exact and short output; exact/over-limit ASCII/CJK/emoji ingress; malformed/NUL/encoding inputs; license denial including owner authorization; cancellation/expiry before/during the gate, resolver or backend; NS/C++ faults before/after a fake effect and during resolution; missing-symbol recovery on a later explicit call; allocation failure; RAW parser/core return compatibility; immutable snapshots/result lifetime; and 1000 repeated balanced real CF lifecycles. Existing PID/state/info/paths/kill fixtures cover the shared entry regression.

## Acceptance and remaining work

The user reported this checkpoint built successfully before C02b35; the combined C02b33/C02b34 source is committed as `68cd857`. The next source checkpoint is IMPLEMENTATION-C02B35.md; the build report does not replace SBS/device/performance qualification.

The user reported C02b33 build success before this checkpoint; that report does not qualify the new task-11 path. Build rootfull/roothide variants and compare typed/helper openApp with RAW task 11 on disposable test applications, including invalid/missing applications and supported SBS versions. Check unchanged ACK/status semantics, symbol availability, license denial/revocation, input/output limits and caller stop/deadline. Confirm CF ownership under Instruments/sanitizers and recheck existing callers of bringAppForeground. Do not automatically retry an uncertain launch. Measure bridge overhead separately from SpringBoardServices/application lifecycle work. Continue remaining P0-13 adapters such as listBundles, P1-40 invalidation and P0-12 qualification/unknown-start cases; C02 remains partial.
