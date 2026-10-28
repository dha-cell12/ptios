# C02b42 — direct toast adapter and RAW error lifetime

Date: 2026-10-28 (Asia/Bangkok). Baseline: `df1283d`, containing C02b41; the user reported C02b41 built successfully.
Status: **user reported build success before C02b43 at source baseline `023e926`; independent device/performance qualification pending**.
Finding: **P0-13, toast task-22 adapter**. Other adapters, metadata codecs/copies and performance qualification remain open.

## Result and compatibility

The rootfull/roothide JS toast adapter calls TLinkExecuteNativeToast directly. RAW and direct paths share TLinkShowToast with numeric type/duration/position/fontSize and a retained content string. This removes full task-string formatting/encoding, RAW split/intValue parsing, processTaskWithContext, compatibility CF stream and response-vector accumulation/copy from the typed toast path. The queued block retains the content instead of the RAW parser's entire field array.

Keep the JS normalization prefix unchanged: non-string description; ;; to ; space, CR/LF to spaces; 180 UTF-16-unit truncation; empty-message rejection; respondsToSelector/intValue option defaults; invalid type fallback to 3; nonpositive duration fallback to 2 except hide. Preserve type 0 hide, types 1..4, signed position/fontSize and int-to-float duration conversion at the existing UI method boundary. UTF-8/NUL admission and prefix-inclusive input limits remain; a small numeric-column count replaces full request formatting. Keep the old %s conversion for non-ASCII message content. The shared backend keeps exact RAW format/type/duration errors, optional columns and permissive integer parsing. The task-22 RAW handler is unchanged.

The same global asynchronous queue still calls Toast hide/show; their UIKit/main-queue rendering and delayed close code are unchanged. The success reply remains 0 followed by CRLF after enqueue, before UI application. No cancellation test, retry, rollback or new ordering guarantee is added inside accepted asynchronous work.

The RAW backend also fixes NSError lifetime: a private parser writes a local strong error inside the pool; the public wrapper retains it across pool drain and publishes it afterward. Success leaves an existing caller error untouched. This avoids an autoreleasing out-parameter escaping the parser's former inner pool while preserving error values and effects.

Production TrollStore and TouchPOC execution sources are unchanged; both workflows run the shared safety suites. No CPU, allocation, latency or RSS improvement has been measured.

## Authority, effects and lifetime

Show and hide retain one ordinary task-22 license gate; owner automation authorization does not bypass it. The child context inherits owner fields, deadline, cancellation and output settings with response capture disabled. Task 22 adds no C01-local deadline. Check input before the gate, stop before/after the gate and after enqueue; reply output remains bounded. Escaping NS/C++ exceptions at the synchronous entry normalize to native_exception.

Accepted enqueue can survive caller cancellation/deadline, output rejection or a subsequent synchronous exception. Retained message/block ownership permits later delivery after caller/pool teardown; such delivery is not a second operation or retry. Asynchronous UI failures remain outside the entry's synchronous exception guard. Scoped budgets restore TLS, and no request budget is newly propagated into delayed UI work. Actual UIKit timing, overlap, global-queue ordering and visibility require device qualification.

## Verification

CI correction during C02b43: the reported macOS abort was the toastEnqueue assertion requiring a non-cleanup budget. The NSError lifetime probe called the successful RAW hide path outside any native budget scope, although the enqueue test double requires one. Install TLinkNativeBudgetScope inside both caller-pool probes, matching the other RAW cases. Keep the enqueue assertion and cross-pool error/success-writeback checks. An always-host source guard rejects a missing probe scope. Focused native-budget/extraction, expanded assert preprocessing and diff checks pass on Windows; corrected macOS runtime remains pending CI. This correction changes the fixture and its guard, not production toast behavior.

CI correction during C02b43: the reported macOS abort was the toastEnqueue assertion requiring a non-cleanup budget. The NSError lifetime probe called the successful RAW hide path outside any native budget scope, although the enqueue test double requires one. Install TLinkNativeBudgetScope inside both caller-pool probes, matching the other RAW cases. Keep the enqueue assertion and cross-pool error/success-writeback checks. An always-host source guard rejects a missing probe scope. Focused native-budget/extraction, expanded assert preprocessing and diff checks pass on Windows; corrected macOS runtime remains pending CI. This correction changes the fixture and its guard, not production toast behavior.

All 62 workflow runners (36 source-contract, 26 native), 521 direct workflow source-grep assertions, expanded standards-conforming assert preprocessing and git diff --check pass on Windows. Focused native-budget/extraction and assert checks also pass after the final fixture guards. The assert checker retains its rejecting negative control. Sixteen artifact-only checks require CI outputs. No warning or sanitizer checks were disabled. Windows cannot execute the new macOS/Foundation/ARC/sanitizer branches.

New macOS coverage compiles actual normalization, RAW parser/error wrapper, numeric enqueue, direct entry and bridge. Frozen JS/task/backend fragments from df1283d provide the value/effect oracle. The frozen source remains intact; its generated runtime include omits only the unsafe old inner autorelease pool so ARC can safely return its error values to the oracle caller. Production retains a real pool and is separately tested across nested pool/writeback boundaries. ARC and sanitizer checks remain enabled.

A controlled enqueue queue records accepted blocks; a controlled Toast class records hide/show arguments without displaying UI. Coverage includes 160 ordinary cases; type/duration/default/signed option behavior; description and intValue conversions; sanitization, empty messages and 180/181-unit boundaries; Unicode, split surrogate and NUL admission, including ignored suffixes beyond truncation; exact/short output and native-field exact/over-limit ingress; ordinary task-22 show/hide authority, caller/gate stop and queued cancellation/deadline; NS/C++ faults before/after enqueue; late mutable-input snapshots and retained results; complete RAW errors/optional columns and retained NSError/preserved success writeback. A final block is delivered through real global dispatch with a bounded group join. No real toast is displayed.

## Acceptance and remaining work

The user reported this checkpoint built successfully before C02b43; source baseline is `023e926`. The next source checkpoint is IMPLEMENTATION-C02B43.md. This build report does not replace queue/UIKit/device/performance qualification.

The user reported C02b41 build success at df1283d; that does not qualify the new toast path or error wrapper. Build rootfull/roothide and compare typed/helper toast with RAW task 22 for sanitized Unicode text, hide/show types, signed positions/fonts, default/long durations, exact ACK/errors, license denial/revocation and caller/output failures after accepted enqueue. Verify UI overlap/close timing and message lifetime after caller teardown; qualify RAW NSError/writeback under ARC/sanitizers. Measure bridge overhead separately from queue/UI work. Continue other P0-13 adapters and metadata codecs/copies, P1-40 invalidation and P0-12 qualification/unknown-start cases; C02 remains partial.
