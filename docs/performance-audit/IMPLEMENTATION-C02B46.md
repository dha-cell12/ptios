# C02b46 — direct dialog and clear-dialog adapters

Date: 2026-10-28 (Asia/Bangkok). Baseline: `03f7454`, containing C02b45; the user reported that build passed.
Status: **source implemented; new macOS/Foundation/ARC/sanitizer CI and device qualification pending**.
Finding: **P0-13, dialog task 42 and clearDialogValues task 43**. Other adapters, metadata codecs/copies and performance qualification remain open.

## Result and compatibility

The rootfull/roothide dialog JS branch calls TLinkExecuteNativeDialog directly; clearDialogValues calls TLinkExecuteNativeClearDialog. RAW task 42 and the direct dialog share TLinkShowDialog, extracted from the original RuntimeUtils backend. The RAW parser keeps its missing-field defaults; clearDialogValues keeps its original state reset. Both RAW task handlers remain unchanged. Production TrollStore and TouchPOC execution sources are unchanged; both workflows run shared safety suites.

Ordinary dialog input avoids the full RAW task string, full request split, processTaskWithContext, compatibility CF stream and response-vector accumulation/copy. Individual description snapshots, bounded input/reply formatting, four-field storage and the existing JS response metadata copy remain. Clear no longer constructs even its two-character RAW task. No CPU, allocation, latency or RSS improvement has been measured.

Keep title/message/OK/Cancel defaults, description conversion, empty fields, Unicode and newlines. Admission counts all four rendered fields plus task/separators against 8192 UTF-16 units before checking UTF-8 bytes/NUL/encoding, retaining full-input error precedence. Semicolon-containing text uses bounded join/split compatibility to preserve field shifts and overlapping delimiters at separator boundaries, including single trailing semicolons. Other text passes four fields directly. Extra JS dialog arguments and all clear arguments remain ignored.

The shared backend retains zero CF display timeout, note-alert flags, button fields, null optional URLs/other button, initially zero response flags and ignored CFUserNotificationDisplayAlert return status. It stores/returns response flags using the old signed-long decimal conversion. The task reply remains 0;;response followed by CRLF, and JS response metadata still uses intValue. Thus wide flag/state conversion and metadata truncation remain compatible. Clear resets lastDialogValue to an empty string and replies 0 followed by CRLF. The NSError outputs remain untouched; production explicitly marks these unused parameters, and only the frozen compile adapter adds equivalent void uses without altering its oracle file.

## Authority, effects and lifetime

Dialog and clear each use one ordinary task-42/task-43 license gate. Clear is an ordinary operation; owner automation authorization does not bypass either gate. The child context retains owner fields, inherited deadline, cancellation and output settings with response capture disabled. Neither task adds a C01-local deadline. Stop is checked after input conversion, before/after the gate and after backend work; replies pass the existing bounded formatter. Per-call pools preserve input/results and restore scoped TLS.

CFUserNotificationDisplayAlert remains opaque synchronous work and may block for user input beyond the caller deadline. Accepted display/state updates, or a clear, can commit before reported caller stop/output failure. No retry, rollback, early output floor, main-queue move, new timeout or concurrent-state synchronization is added. Escaping NS/C++ faults at the direct entry become native_exception. This API returns no owned CF notification handle to release. Real SpringBoard display/user response, threading and concurrent state behavior require qualification.

## Verification

All 62 workflow runners (36 source-contract, 26 native), 521 direct workflow source-grep assertions, expanded standards-conforming assert preprocessing and git diff --check pass on Windows. The assert checker retains its rejecting negative control. The new macOS/Foundation/ARC/sanitizer branches cannot run on this host. Sixteen artifact-only checks require CI outputs; warning and sanitizer checks remain enabled.

The new macOS fixture compiles the actual RuntimeUtils parser, shared CF display core, state reset, direct task entry and complete dialog/clear JS branches. The 03f7454 frozen core/task/bridge fragments supply the compatibility oracle. Source guards reconstruct the old core by removing only extraction glue and explicit void uses; both RAW handlers and JS normalization/metadata are compared exactly after replacing the two call sites. CF display is controlled; these tests show no real dialogs.

Coverage includes 160 ordinary calls, defaults/ignored arguments/descriptions, all four field positions, Unicode/newlines/semicolon overlaps, missing RAW fields, signed/wide response flags and metadata, ignored CF errors/untouched response output, exact/over-limit UTF-16 and encoding/NUL precedence, exact/short output, ordinary license and owner-denial policy, initial/gate/provider cancellation/deadline, opaque committed state, NS/C++ faults, mutable snapshots, retained results/fields, unchanged NSError outputs and 1000 repeated dialog/clear cycles. Clear output rejection is checked after state reset, independently of the display path.

## Acceptance and remaining work

The user reported C02b45 build success at 03f7454; that does not qualify the new dialog path. Build rootfull/roothide, then compare typed/helper dialog and clear calls with RAW tasks 42/43 for defaults, delimiter/Unicode text, button labels, response/metadata, ignored CF errors and license denial. Verify actual user response/dismissal and blocking/thread behavior, including caller stop/output rejection after accepted work. Check repeated and concurrent calls separately from ACKs. Measure bridge overhead separately from user wait. Continue other P0-13 adapters and metadata codecs/copies, P1-40 invalidation and P0-12 qualification/unknown-start cases; C02 remains partial.
