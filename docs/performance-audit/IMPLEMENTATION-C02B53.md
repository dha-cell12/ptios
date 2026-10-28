# C02b53 — direct legacy shell adapter

Date: 2026-10-28 (Asia/Bangkok). Baseline: `965913e`, containing C02b52; the user reported that build passed.
Status: **source implemented; new macOS/Foundation/ARC/sanitizer CI and device qualification pending**.
Finding: **P0-13, runShell, task 13**. C02 remains partial.

## Result and compatibility

Rootfull/roothide JS runShell now calls TLinkExecuteNativeRunShell and the existing RunShellCore directly. Ordinary calls avoid full RAW task assembly/encoding, processTaskWithContext, CF stream creation and response-vector accumulation/copy. Command snapshots, legacy numeric/string normalization, bounded reply conversion and JS decoding remain. No CPU, allocation, latency or RSS improvement has been measured. Production TrollStore and TouchPOC adapters are unchanged; their workflows retain the shared checks.

RAW task 13 and the direct entry share the extracted legacy command scanner and reply formatter. Source guards compare these helpers with the frozen 965913e handler, ignoring only surrounding indentation/blank lines and converting notifyClient expressions into returns. They reconstruct the original RAW handler after removing helper calls. The complete JS branch is compared with its frozen version after restoring only the old RAW call site.

Preserve the full original input admission before authority: 8192 UTF-16 units and 32-KiB UTF-8 bytes/NUL/encoding, including any %.3f timeout prefix. A valid explicit positive prefix is scanned separately without rebuilding the complete payload. A positive timeout rounding to zero keeps the old literal prefix in the command and uses the default timeout; that rare branch retains bounded field assembly. Without an explicit prefix, the old first-;; NSScanner rule still interprets commands such as 12;;fixture as a timeout and command tail. Nonpositive/nonfinite optional timeouts retain the unprefixed path. Existing command validation, newline acceptance, defaults, owner fields and timeout/output settings remain.

The legacy reply retains stdout-then-stderr combination, CR/LF escaping, truncation suffix, timeout/cancel/status precedence and raw C-string behavior. Task 13 emits plain escaped text. The existing JS decoder adds exitCode/output metadata only when at least three ;; fields exist, interpreting its third field as base64. This historical mismatch is preserved explicitly rather than changing the API contract in a performance adapter. Ordinary plain output still lacks that added metadata; delimiter-containing output can trigger it.

## Authority, budgets and process behavior

Retain one ordinary task-13 gate, including owner-authorization denial. Child contexts inherit cancellation/deadline/output and owner callbacks with response capture disabled. Task 13 adds no C01-local timeout. Existing shell timeout selection in the request prelude and inherited non-extending deadlines remain; the native entry does not replace them with the rounded wire timeout.

The entire existing shell owner/core stays unchanged: privileged helper paths, spawn attributes, pipes, capture cap, drain queues, timeout clamps, process-group termination/grace, cancellation and drain cleanup. Task 71's JSON handler is also unchanged and guarded against its frozen source. No real subprocess behavior is newly qualified here, and no process scheduling, timeout, retry or rollback policy is added. An accepted command may have effects before caller stop, output rejection or a reported fault. Escaping NS/C++ exceptions normalize to native_exception in the direct entry; output goes through the existing bounded C-string formatter.

The final native response remains bounded, while legacy output combination/escaping/formatting can materialize larger upstream strings, just as before. This checkpoint does not establish a universal producer-memory limit.

## Verification

All 62 workflow runners (36 source-contract, 26 native), 521 direct source-grep assertions, expanded standards-conforming assert preprocessing and git diff --check pass on Windows. Focused native-budget/extraction passes; its first run completed native/extraction checks but encountered a transient EPERM deleting the temporary exe, and a repeat including cleanup passed without runtime-policy changes. Sixteen artifact-only checks require CI outputs. New macOS/Foundation/ARC/sanitizer compilation/runtime cannot run on this host and remain pending CI. Warnings and sanitizers remain enabled.

The Foundation fixture compiles the actual result model, extracted scanner/formatter, native entry and complete JS branch against frozen task/JS oracles. RunShellCore is a controlled runner recording the exact command, timeout, output limit, context and accepted-effect stages; no command is executed, no process is spawned and no privileged helper is invoked. Existing native-budget/context tests retain their separate deadline/cancellation coverage.

Coverage includes 160 ordinary calls; %.3f ties, zero-rounded/nonpositive/nonfinite/large timeouts; numeric command-prefix ambiguity; Unicode/newlines/delimiters/NUL/invalid UTF16 and exact 8192/8193-unit admission; success/failure/timeout/cancel/truncation/nil-result/output formatting and metadata oddities; large escaped output/final cap; ordinary authority/owner denial; pre/gate/provider cancellation/deadline; accepted effects before stop/output/NS/C++ faults; inherited deadline/context fidelity, mutable snapshots/cross-pool result lifetime; and 128 repeated lifecycles. Numeric-timeout parity cases install a fixed inherited budget to separate scanner fidelity from sub-millisecond admission races; they do not qualify wall-clock process timeout accuracy.

## Acceptance and remaining work

Build rootfull/roothide with C02b53 and compare typed/helper runShell with RAW task 13 using harmless controlled commands. Qualify actual stdout/stderr draining, limits, timeout/cancellation and process-group retirement; retain task-71 isolation. Check effects separately from reported stop/output failure and do not automatically retry uncertain commands. Measure bridge overhead separately from spawning, helper work and drain latency. Remaining P0-13 mixed/RAW compatibility paths and metadata codecs/copies, P1-40 invalidation and P0-12 qualification/unknown-start cases remain open.
