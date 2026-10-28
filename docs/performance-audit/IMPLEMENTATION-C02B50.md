# C02b50 — direct template match adapter

Date: 2026-10-28 (Asia/Bangkok). Baseline: `6aa9104`, containing C02b49 and the duplicate schedulerError fixture correction; the user reported that build passed.
Status: **source implemented; new macOS/Foundation/ARC/sanitizer CI and device qualification pending**.
Finding: **P0-13, matchTemplate, task 21**. C02 remains partial.

## Result and compatibility

The rootfull/roothide JS branch now calls TLinkExecuteNativeTemplateMatch and the existing ScreenMatch method directly. Ordinary typed calls avoid full RAW request assembly/UTF-8 encoding/splitting, processTaskWithContext, CF stream creation and response-vector accumulation/copy. Preserve JS option defaults, intValue, path validation and result metadata. The existing result formatter, C-string/error compatibility and JS coordinate decoding remain; this checkpoint does not eliminate every numeric codec or copy. No CPU, allocation, latency or RSS improvement has been measured. Production TrollStore and TouchPOC adapters are unchanged; their workflows retain shared checks.

The direct entry snapshots the path, counts the complete original task prefix and suffix against 8192 UTF-16 units, and checks UTF-8 length/encoding/NUL before any gate or backend work. It retains the %.4f -> Foundation floatValue round trip for acceptable/scale, including signed zero, nonfinite values and rounding across validation boundaries. It does not replace this behavior with a direct double-to-float conversion. A semicolon-containing path uses bounded field assembly/splitting to preserve overlapping separators, including a trailing single semicolon. Ordinary paths do not assemble/split the complete request.

The RAW parser and task-21 handler remain unchanged. ScreenMatch retains parameter validation before file lookup/capture, matcher setter order, file/screenshot errors, matching and CGRect output. The shared screenshot owner now releases its CGImage in @finally, including escaping NS/C++ matcher exceptions. This corrects an exception-path resource leak for both typed and RAW callers; ordinary behavior is unchanged. It does not change capture, OpenCV interpolation/cache/work budgets or the daemon task-21 route.

## Authority, budgets and effects

Retain one ordinary task-21 license gate, including owner-authorization denial. The child context inherits cancellation/deadline/output with response capture disabled. A C01 child applies the existing eight-second non-extending deadline before the gate. Stop checks bracket authority and caller-budget checks follow backend work. Captures, file checks and matching retain their existing execution thread and cooperation boundaries; no retry, queue move or timeout extension is added.

As on the RAW route, an opaque accepted backend may return after only the local C01 deadline expires. Its response is retained when the caller budget remains live; parent cancellation/deadline and output rejection still determine the final reply. The actual template engine continues its own cooperative stop/error policy. NS/C++ exceptions escaping the direct entry normalize to native_exception. Screenshot ownership is released on unwind; no broader guarantee about device capture or OpenCV exceptions is inferred.

## Verification

Always-host source guards compare the unchanged RAW handler and JS behavior with frozen `6aa9104` fragments, reconstruct the pre-change ScreenMatch source after removing only the @finally ownership change, require one gate/C01 scope and verify the public declaration and fixture ordering. Warnings and sanitizers remain enabled.

The new macOS fixture compiles the actual ScreenMatch adapter/parser, direct entry and JS branch alongside frozen adapter/parser/task/JS oracles. It uses a private generated PNG and real ImageIO/CGImage ownership, with controlled screenshot and matcher boundaries. It does not run the new bridge tests against real iOS capture or OpenCV. The separate template suite retains actual loader/cache/planning/SAD tests with its existing controlled CV boundary and pending real OpenCV/device qualification.

Coverage includes 160 ordinary calls; int/default/string/scalar normalization and %.4f boundaries; nonfinite and large values; hit/miss/nonfinite/large CGRect formatting; missing paths, directories and screenshot failures; semicolon boundaries; exact 8192/8193 UTF-16 ingress, Unicode/NUL/invalid UTF16; exact output/error encoding and empty-sink compatibility; one ordinary gate and owner denial; pre/gate/backend cancellation/deadline, accepted local C01 overruns and pre-expiry; output failures; escaping NS/C++ matcher exceptions; mutable input/result/error lifetime; RAW one/four-field defaults and malformed shapes; and 128 balanced lifecycles. Local-overrun probes offset only the admission timestamp through the production C01 duration/factory. They do not measure eight-second wall-clock timing accuracy.

All 62 workflow runners (36 source-contract, 26 native), 521 direct source-grep assertions, expanded standards-conforming assert preprocessing and git diff --check pass on Windows. Focused native-budget/extraction and template-core checks pass. Sixteen artifact-only checks require CI outputs. New Foundation/ARC/sanitizer compilation/runtime cannot run on this host and remain pending macOS CI.

## Acceptance and remaining work

Build rootfull/roothide with C02b50 and compare typed/helper matchTemplate with RAW task 21 on controlled image fixtures. Qualify real capture, OpenCV interpolation/results, pressure and cancellation/deadline behavior; verify exact ACK/error/coordinate metadata and license denial. Measure bridge costs separately from capture/matching. Other P0-13 adapters and metadata codecs/copies, P1-40 invalidation and P0-12 qualification/unknown-start cases remain open.
