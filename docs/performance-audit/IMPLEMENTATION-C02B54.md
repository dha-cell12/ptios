# C02b54 — direct compatibility batch adapter

Date: 2026-10-28 (Asia/Bangkok). Baseline: `64a6458`, containing C02b53; the user reported that build passed.
Status: **source implemented; new macOS/Foundation/ARC/sanitizer CI and device qualification pending**.
Finding: **P0-13, mixed/RAW-compatible batch, task 65**. C02 remains partial.

## Result and compatibility

Rootfull/roothide JS batches containing RAW command strings or nonstandard tap/swipe durations now call TLinkExecuteNativeCompatibilityBatch with the validated command array. Ordinary compatibility calls avoid whole-task encoding, processTaskWithContext, CF stream creation and response-vector accumulation/copy. Per-command legacy formatting, UTF8 conversion and parsers remain. The existing numeric batch path is unchanged. No CPU, latency, allocation or RSS improvement has been measured. Production TrollStore and TouchPOC adapters remain unchanged; both workflows retain the shared checks.

JS still validates every item before authorization or effects, with the same object/string grammar, numeric formatting, duration rules, aliases, delimiter rejection and 256-command limit. The native entry snapshots strings and admits the original combined input size, including the task prefix and separators: 8192 UTF16 units, followed by UTF8/NUL/encoding checks and the 32-KiB byte limit. Whole-input unit overflow still takes precedence over earlier embedded NULs. The entry also rejects nonstring items and arrays above 256; those direct-API checks do not change the external RAW handler.

The existing batch execution body is shared verbatim with RAW task 65. A source guard reconstructs the frozen wrapper and executor, and separately requires the RAW task handler to remain unchanged. RAW still decodes the whole request and splits on ||. The direct entry bypasses that join/split for arrays without pipes. Any pipe retains bounded join/split compatibility because a trailing single pipe can overlap the next || separator, and gesture points use pipes. This preserves command boundaries and historical malformed-input behavior.

The old empty-body error and the distinction between one empty command and multiple empty commands remain. Per-command order, skipped short commands, first error, NSError-over-BOOL reporting, exact replies/parts and already committed earlier effects remain. RAW-owned task-10 contacts and native gesture contacts retain the existing finally cleanup; successful RAW DOWN ownership behavior is unchanged.

## Authority and budgets

Retain one ordinary task-65 gate, without per-child gates or automation-owner bypass. This is not a cleanup entry. Child contexts inherit owner callbacks, cancellation, non-extending deadlines and output limits with response capture disabled. Task 65 adds no local C01 timeout. Pre-admission, gate-time and execution-time stop checks remain, and output accounting precedes final stop conversion just as on the existing touch reply path.

The direct entry normalizes escaping NS/C++ exceptions to native_exception. The frozen RAW bridge only catches NS exceptions, so C++ unwind is tested on the new entry separately instead of invoking an unsafe frozen oracle. Touch/HID primitives, injection scheduling, RAW socket handling and external task-65 limits are unchanged. No retry or rollback of completed commands is introduced.

## Verification

All 62 workflow runners (36 source-contract, 26 native), 521 direct source-grep assertions, expanded standards-conforming assert preprocessing and git diff --check pass on Windows. Focused native-budget/extraction passes. Sixteen artifact-only checks require CI outputs. New macOS/Foundation/ARC/sanitizer compilation/runtime cannot run on this host and remain pending CI; warnings, assertions and sanitizers stay enabled.

The Foundation fixture compares the actual shared executor, direct entry and complete JS branch with frozen `64a6458` JS/RAW implementations. Controlled clocks and injection record exact frames, timestamps, waits, replies, effects and task gates; no real HID events are submitted. Coverage includes 160 ordinary mixed batches, string/negative/extreme durations, gesture pipes and separator overlap, malformed/unsupported commands and full JS prevalidation, 256/257 commands, exact 8192/8193-unit admission, Unicode/NUL/invalid UTF16 and size-error precedence, empty direct arrays, raw-owned UP after failure, one gate, denial, cancellation/expiry, NS/C++ faults, output bounds, result pool lifetime and 128 repeated lifecycles. Additional new-entry checks retain ordinary authority even when owner automation is allowed, and reject expiry during a delayed gate.

## Acceptance and remaining work

Build rootfull/roothide with C02b54 and compare numeric/mixed/RAW batches on controlled devices. Qualify real HID ordering, contact retirement and deadlines across task 10/62/63/64 combinations, cancellation and malformed later commands. Measure bridge overhead separately from touch delivery and waiting.

The explicit rawTask API, resource-release RAW compatibility calls and generic unknown connectivity-task fallback remain deliberate RAW paths. Metadata codecs/copies, P1-40 invalidation and P0-12 device/performance qualification remain open. This checkpoint does not close C02 or claim device performance gains.
