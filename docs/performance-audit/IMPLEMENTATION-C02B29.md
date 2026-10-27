# C02b29 — direct appPid bundle query

Date: 2026-10-27 (Asia/Bangkok). Baseline: `b2ac272`; the user reported C02b28 built successfully.
Status: **build reported passed by the user before C02b30 (`dfde59c`); independent device/performance qualification pending**.
Finding: **P0-13, task-50 app PID adapter**. Other adapters and performance qualification remain open.

## Result and compatibility

The rootfull/roothide appPid bridge calls TLinkExecuteNativeAppPid after its existing bundle-ID validation. Process exposes appPidForBundleIdentifier with the existing missing-identifier error, zx_pidForBundleId lookup and signed decimal formatting; the RAW parser delegates to that core. Other methods in the shared app bridge retain their RAW path.

The typed path removes full task request formatting/encoding, processTaskWithContext dispatch, compatibility CF stream and response-vector accumulation/copy. Ordinary successful replies reuse the scalar formatter to build ok/raw/parts and numeric pid without splitting/reparsing the response. Preserve ignored extra arguments, backend error strings, nil-to-0 fallback and signed integer conversion.

Preserve legacy ingress: the two task-prefix units count toward the 8192-UTF-16-unit request limit, so bundle IDs allow at most 8190 units. Retain the 32-KiB UTF-8 request cap less two prefix bytes, encoding failure/NUL rejection and protocol delimiter validation. The entry copies the accepted string to an immutable snapshot before authority/backend work. ASCII input uses that string directly; non-ASCII input retains the old %s conversion of its UTF-8 body, without rebuilding a full task request. UTF-8 validation/storage and this compatibility conversion remain; no allocation-free claim is made.

The RAW task-50 body is unchanged and checked against frozen source. Its parser still performs the historical %s conversion before calling the shared core, including its own empty-identifier NSError behavior. Production TrollStore and TouchPOC execution sources are unchanged; both build workflows run the shared safety suites.

## Authority and lifetime

The entry creates the existing child context with response capture disabled, inheriting owner fields, caller deadline and output settings. Input failures return before the ordinary task-50 license gate and PID lookup. Check stop before one gate, after the gate, after the backend and after result formatting/output admission. Owner automation authorization does not bypass the gate. No C01-local timeout or compute admission is added.

PID discovery remains synchronous and cooperative through the unchanged backend. It is not preempted by cancellation/deadline; the entry observes those after return. NS/C++ exceptions normalize to native_exception. A per-query autorelease pool drains temporaries while a strong result outside the pool retains reply metadata. The immutable input snapshot preserves the bundle value across synchronous backend work. No measured CPU, allocation, latency or RSS improvement is claimed.

## Verification

All 62 workflow runners (36 source-contract, 26 native), 521 direct workflow source-grep assertions, expanded standards-conforming assert preprocessing and git diff --check pass on Windows. The assert checker retains its rejecting negative control. Sixteen artifact-only checks require CI outputs. No warning or sanitizer checks were disabled. New Foundation/ARC/ASan/UBSan fixture branches cannot execute on this Windows host.

New macOS coverage compiles the actual shared app bridge, task entry, Process parser/core and scalar formatter against a controlled PID lookup. Frozen bridge/task/backend fragments provide the old adapter oracle. It compares replies, normalized lookup identifiers and gate/read counts for 160 ordinary cases, signed PID/exact output limits, invalid/missing argument types, ignored extra arguments, Unicode, embedded NUL, encoding failure and exact/over-limit ASCII/multibyte/surrogate-pair input.

Coverage checks one task-50 gate, denied owner exemption, pre/gate/read cancellation and deadline, NS/C++ lookup faults, RAW parser/error parity, immutable mutable-string input and NSError/reply lifetime after pool teardown. The actual protocol-string helper is extracted into the fixture, with dependency checks on every host. Typed appPid must issue zero RAW dispatches and reserve no response-vector capacity. SpringBoard/PID behavior and device/performance acceptance remain pending.

## Acceptance and remaining work

The user reported this checkpoint built successfully before C02b30. That report does not establish device or measured performance acceptance. The next checkpoint is documented in IMPLEMENTATION-C02B30.md.

Build rootfull/roothide variants and compare typed/helper appPid with RAW task 50 for running/missing apps, valid/invalid identifiers and boundary inputs. Verify authority, stop/deadline/output behavior and PID transitions on device. Measure bridge overhead separately from the unchanged lookup. Continue other P0-13 adapters, P1-40 invalidation and P0-12 qualification/unknown-start cases; C02 remains partial.
