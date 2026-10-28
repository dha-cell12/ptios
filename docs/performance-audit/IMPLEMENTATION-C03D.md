# C03d — bounded asynchronous console system logging

Date: 2026-10-29 (Asia/Bangkok). Baseline: `be66e2cf` (C03c); user reported that build passed.
Status: **user reported build `10a952a5` passed before C03e; independent device/performance qualification pending**.
Finding: **P1-42 per-console-call synchronous NSLog slice**. Other C03 work remains open.

## Result and scope

The rootfull/roothide in-process `_tlinkautoLog` callback now only submits to the existing bounded logger. The serial drain calls NSLog for each accepted entry, in commit order, before attempting that batch's two disk paths. There is one owner queue, with no new unbounded dispatch blocks or timer. A stalled system backend holds its admission slot and delays the worker, rather than blocking each console caller. Finish still closes admission and synchronously drains the queue; it can wait for a blocked sink. JavaScript argument/JSON formatting and bounded snapshot/file-line preparation remain on the caller.

Capture immutable, surrogate-safe system-message and level prefixes before publication. System messages keep raw CR/LF/NUL/Unicode; disk messages still escape CR. Preserve the ordinary `com.tlinkauto.jsruntime[runId][level]: message` format body. System text uses the same 4096-unit message prefix, truncation marker and 64-unit level prefix as admission; unsanitized level text is retained for the system format. Level/message cuts count once per accepted entry. The runtime UUID is captured with the entry, so old formatting cannot emit into a later run.

Under saturation, formatting/encoding faults, a closed run or a rejected stale generation, that attempt emits neither a disk entry nor a per-entry NSLog. This intentionally extends C03b's loss/truncation policy to system logs; the old synchronous callback emitted a system log even when disk admission rejected it. The drain footer still reports lifetime loss/failure totals. NSLog's backend timestamp/thread and ordering relative to unrelated diagnostics now reflect worker execution. Runtime exception/setup diagnostics outside this console callback remain unchanged.

## Memory, failures and shutdown

The same 64 lifetime reservations cover formatting, pending work and execution. Each now reserves up to 16 KiB disk data plus 16 KiB bounded system-text payload: 2 MiB total logical entry payload. The 4096+marker+64 UTF16 prefixes fit the system allowance; publication also checks their byte size. The original pendingBytesReserved/maxPendingBytes keys retain their disk-only meaning (up to 1 MiB). New pendingSystemBytesReserved, pendingTotalBytesReserved, maxPendingTotalBytes and maxSystemTextBytes keys expose system/combined reservations. C03c's one-path batch scratch still adds up to 1 MiB logical payload outside those entry reservations. Paths/UUIDs, object/capacity overhead, upstream inputs, Foundation temporaries and OS logging internals are not a process RSS ceiling.

NS/C++ exceptions from an accepted per-entry system sink increment systemFailures once and do not skip either disk path or later entries. Never retry a system emission, including a fault reported after the sink accepted its text. Disk writeFailures retain C03c's independent per-path/group accounting. The drain footer includes systemFailures; its own best-effort system failure is contained and does not recursively add another footer/counter. Normal backend success is not a durable-delivery acknowledgment.

The existing closing lock/generation, committed-work drain, old formatter rejection, charge retirement and path reset/retention rules remain. No license, task, JS function signature, history schema or script result changes. Disk formatting/rotation/writer and C03c batch policy remain. Production helper/TrollStore loggers and TouchPOC are unchanged; both workflows already run the extended console safety runner.

## Verification

Focused Windows console-budget/source/history checks pass. Portable tests retain 100k lifetime/prefix/rotation cases and 8 x 10k concurrent admissions, add disk+system reservation/prefix bounds and independent system-failure accounting, and finish with zero pending charges.

The extended macOS fixture extracts the actual console callback and compares it with a frozen `be66e2cf` hook using real JavaScriptCore contexts. A held queue proves new calls return before any NSLog, while the frozen hook emits synchronously; 32 ordinary/empty/Unicode/CR/LF/NUL/custom-level cases must retain exact format bodies and disk bytes. A controlled blocked system sink keeps one slot charged while JSCore continues submitting and returning values; finish drains ordered outputs. System NS/C++ faults after capture must not replay, skip disk writes, escape the worker or leak charges, and must recover on the next run. Existing held-64/drop-before-description, immutable mutable-input/level truncation, closed/stale generation, batch/rotation/missing-file/remove/I/O-fault and handle-balance cases remain, now also checking system output.

The fixture captures NSLog calls in place of using the device logging backend. It retains actual queue ownership and production format invocation, with warnings, ARC, ASan and UBSan enabled. All 64 workflow runners (36 source-contract, 28 native), 521 direct workflow source-grep assertions, expanded standards-conforming assert preprocessing and git diff --check pass on Windows. Sixteen artifact-only checks require CI outputs. New macOS-only execution and device syslog/latency/RSS qualification remain pending.

## Remaining work

P1-42's bounded admission, disk batching and per-console-call asynchronous system sink are implemented in source. Qualify sparse/burst/slow-sink/stop/restart workloads on rootfull/roothide, separately measuring caller latency, drain latency, CPU, disk operations, payload and RSS. No device improvement percentage is claimed. C03 history/persistence/retention/status/commit/recovery and outstanding C02 work remain open.
