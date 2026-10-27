# C02b36 — direct openUrl task and main-thread admission

Date: 2026-10-28 (Asia/Bangkok). Baseline: `5d4c67a`, containing C02b35; the user reported C02b35 built successfully.
Status: **source implemented; new macOS/Foundation/ARC/sanitizer CI and device qualification pending**.
Finding: **P0-13, task-54 URL-opening adapter**. Other adapters and performance qualification remain open.

## Result and compatibility

The rootfull/roothide openUrl bridge calls TLinkExecuteNativeOpenUrl after its existing protocol-string validation and error message. Task 54 joins the shared ordinary app/string entry, retaining immutable input snapshots, prefix-inclusive UTF-16/UTF-8 limits, encoding/NUL rejection and non-ASCII %s compatibility. It calls openUrlString without a full RAW request, processTaskWithContext dispatch, compatibility CF stream or response-vector accumulation/copy.

The RAW parser retains its original null-input fallback and %s decoding before delegating to openUrlString. The RAW task-54 body is unchanged and checked against frozen source. The URL core's parse, fallback and reply logic is checked against frozen source apart from the extracted main-owner call. Keep missing/invalid URL errors, real NSURL parsing, case-insensitive prefs: detection and App-Prefs: fallback construction. No URL encoding, scheme validation or new retry policy is added.

When the modern UIKit selector is available, started is set before invocation and ACK does not wait for or inspect completion success. A late failed completion does not trigger fallback. The legacy selector uses its BOOL result; only a failed primary prefs: call attempts the existing fallback. Retain Unable to open URL when neither legacy attempt starts and exactly ok/raw/parts with `0\r\n` on normal success. No query metadata is added. Error/denial replies use the existing bounded parser.

The new synchronous main-owner wrapper runs inline if already on the main thread and otherwise uses the existing dispatch_sync to main. This is an explicit safety correction for main-to-main synchronous dispatch. It also applies to the RAW parser's shared core. It does not turn the operation asynchronous, wait for completion or add a cancellation check inside an already accepted owner operation.

Production TrollStore and TouchPOC execution sources are unchanged; both build workflows run the shared safety suites. No measured CPU, allocation, latency or RSS improvement is claimed.

## Authority, effects and lifetime

Invalid ingress is rejected before one ordinary task-54 license gate and URL/provider work. The child context inherits caller owner fields, deadline and output settings with response capture disabled. Check stop before/after the gate and after the opaque Process call; reply admission checks output and stop. Owner automation authorization does not bypass the gate. Task 54 is not cleanup-exempt and receives no C01-local timeout.

The background caller still waits for the main queue and accepted UIKit work. A caller cancellation/deadline while waiting does not preempt that opaque operation; the typed entry observes stop afterward. An opening request may already have committed before cancellation, output rejection or a boundary exception is reported. No automatic retry or rollback is added. The main-owner wrapper preserves existing UIKit dispatch behavior without propagating a new TLS budget/check into the owner block. Real queue residence, completion scheduling and UIKit authorization require device qualification.

NS/C++ exceptions escaping the core normalize to native_exception. Per-call pools retain the result outside the pool. The input is copied before backend work. Completion blocks keep the existing empty bodies and do not retain the caller context. NSError/result lifetime and mutable caller input are covered. Output caps do not bound URL/Foundation temporary allocation or private provider work.

## Verification

All 62 workflow runners (36 source-contract, 26 native), 521 direct workflow source-grep assertions, expanded standards-conforming assert preprocessing and git diff --check pass on Windows. The assert checker retains its rejecting negative control. Sixteen artifact-only checks require CI outputs. No warning or sanitizer checks were disabled. New Foundation/ARC/ASan/UBSan branches cannot execute on this Windows host.

New macOS coverage compiles the actual Process parser/core/main-owner wrapper, bridge and shared entry against real NSURL and controlled thread/dispatch/UIKit boundaries. Frozen bridge/task/core fragments provide the background-path oracle. It compares complete replies, URL invocation order, selector/owner call counts, completion retention and license counts. Inline-main cases exercise the actual wrapper under a controlled main-thread predicate without invoking the unsafe legacy main-to-main path. No real URLs are opened.

Coverage includes 160 ordinary cases; modern/legacy selectors; primary/fallback BOOL combinations and settings scheme casing; real URL parsing; exact/short output; exact/over-limit ASCII/CJK/emoji ingress; malformed/NUL/encoding inputs; ordinary license/owner denial; pre-cancel/expiry, gate-time stop and stop/deadline during accepted owner work; NS/C++ faults before/after fake effects; inline-main dispatch avoidance; late false/true completions; RAW null/%s parsing; input snapshots; and NSError/result/completion lifetime across caller/pool teardown. Existing app/list/frontmost/path fixtures cover shared-entry/formatter regression.

## Acceptance and remaining work

The user reported C02b35 build success at baseline `5d4c67a`; that report does not qualify the new task-54 path. Build rootfull/roothide variants and compare typed/helper openUrl with RAW task 54 on disposable URL handlers and settings schemes. Verify modern ACK versus later completion, legacy fallback order/errors, main-thread inline behavior and background main-queue dispatch, license denial/revocation, input/output caps and caller stop/deadline. Treat uncertain results as potentially committed; do not retry automatically. Recheck other shared app/string calls. Measure bridge overhead separately from queue residence, URL parsing and UIKit work. Continue other P0-13 adapters, listBundles metadata codecs, P1-40 invalidation and P0-12 qualification/unknown-start cases; C02 remains partial.
