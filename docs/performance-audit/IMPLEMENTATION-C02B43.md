# C02b43 — direct keyboard notification adapters

Date: 2026-10-28 (Asia/Bangkok). Baseline: `023e926`, containing C02b42; the user reported C02b42 built successfully.
Status: **source implemented; new macOS/Foundation/ARC/sanitizer CI and device qualification pending**.
Finding: **P0-13, keyboard task-24 notification kinds**. Clipboard image kind 8, other adapters, metadata codecs/copies and performance qualification remain open.

## Result and compatibility

The rootfull/roothide keyboard JS adapter routes notification kinds through TLinkExecuteNativeKeyboardNotification. Clipboard text kinds 6/7 retain their existing direct adapter; clipboard image kind 8 retains RAW. The notification adapter accepts other int-normalized kinds, including negative and unknown values, as the existing backend did. The new direct entry rejects 6/7/8 before its gate so it cannot accidentally notify for clipboard operations.

RAW and direct paths share TLinkNotifyKeyboardCommand. It posts the same com.tlinkauto.tlinkauto.keyboardcontrol distributed notification with object NULL, task_id/task_content keys and deliverImmediately true, then returns the exact existing ACK string. Preserve nil/NSNull/default content, non-string %@ descriptions, Unicode and newlines. Keep the exactly-two-fields rule: content containing an additional ;; is dropped completely, rather than taking the first field. RAW keeps its original task_id spelling, including leading zeros or nonnumeric strings; typed kinds keep the original JS intValue/%d normalization.

The direct path removes full task-string formatting/encoding, full RAW split/intValue parsing, processTaskWithContext, compatibility CF stream and response-vector accumulation/copy. Small kind/content string formatting and bounded reply formatting remain. Validate the entire rendered content before ignoring a delimiter suffix: prefix-inclusive 8192 UTF-16 units, UTF-8 byte limits and embedded-NUL/encoding rejection are unchanged. Oversized or NUL-containing ignored content still fails before authority/provider work. Immutable snapshots retain content through provider reentry and caller/pool teardown.

Production TrollStore and TouchPOC execution sources are unchanged; both workflows run the shared safety suites. No CPU, allocation, latency or RSS improvement has been measured.

## Authority, effects and lifetime

Keep one ordinary task-24 license gate. Owner automation authorization does not bypass it. The child call retains owner fields, inherited deadline, cancellation and output settings with response capture disabled. Task 24 adds no C01-local deadline. Check stop after input conversion, before/after the gate, after the synchronous notification post and after reply formatting.

Accepted notification posting may complete before caller stop/deadline, output rejection or a later exception is reported. No retry, rollback, new ordering rule or cancellation check inside the notification provider is added. The old ACK describes notification submission, not confirmed keyboard execution in appdelegate. Opaque notification delivery remains cooperative; no hard completion deadline is claimed. NS/C++ exceptions escaping the direct entry normalize to native_exception. Scoped budgets restore TLS and per-call pools retain results outside teardown.

## Verification

CI correction: the first reported macOS runtime abort occurred in the preceding toast fixture (toastEnqueue, missing native budget), before the keyboard notification cases. Both toast NSError lifetime probes now install a non-cleanup native scope inside their caller pools. A source guard checks that setup on every host; the original enqueue assertion remains enabled. Focused native-budget/extraction and expanded assert preprocessing pass on Windows after the correction; macOS runtime verification remains pending. Production keyboard/notification behavior is unaffected by this fixture correction.

CI correction: the first reported macOS runtime abort occurred in the preceding toast fixture (toastEnqueue, missing native budget), before the keyboard notification cases. Both toast NSError lifetime probes now install a non-cleanup native scope inside their caller pools. A source guard checks that setup on every host; the original enqueue assertion remains enabled. Focused native-budget/extraction and expanded assert preprocessing pass on Windows after the correction; macOS runtime verification remains pending. Production keyboard/notification behavior is unaffected by this fixture correction.

All 62 workflow runners (36 source-contract, 26 native), 521 direct workflow source-grep assertions, expanded standards-conforming assert preprocessing and git diff --check pass on Windows. The assert checker retains its rejecting negative control. Sixteen artifact-only checks require CI outputs. No warning or sanitizer checks were disabled. Windows cannot execute the new macOS/Foundation/ARC/sanitizer branches.

New macOS coverage compiles actual shared notification/backend functions, complete JS branch, direct entry and bounded formatter. The frozen 023e926 bridge supplies the old routing oracle. Existing frozen keyboard backend/task fragments from C02b41 remain valid because those notification statements and handlers were unchanged through this baseline; source guards reconstruct and compare that complete backend after helper extraction. The controlled notification center is shared with the clipboard fixture and records post stages, budget and payload. No actual distributed notification is sent.

Coverage compares complete ACK/payload/effect order across 160 ordinary cases; signed/unknown kinds and intValue aliases; missing/empty/NSNull/content descriptions; Unicode/newlines/delimiters/NUL/invalid encoding; exact/over-limit ASCII/Unicode inputs and exact/short output; full admission of ignored suffixes; ordinary task-24/owner denial; pre-cancel/expiry and gate-time stop; accepted notification cancellation/deadline, NSException parity and direct C++ guards before/after effects; conversion-time cancellation; mutable input snapshots and retained result/payload lifetime; direct rejection of clipboard kinds and RAW task_id spelling/field-count compatibility. Existing clipboard read/write fixtures remain, and their RAW fallback check now focuses on kind 8.

## Acceptance and remaining work

The user reported C02b42 build success at 023e926; that does not qualify the new notification adapter. Build rootfull/roothide and compare typed/helper keyboard notification calls with RAW task 24 for supported/unknown kinds, Unicode/newlines, missing/empty content, additional ;; fields, exact limits, license denial/revocation and caller/output failures after accepted delivery. Verify notification payloads and actual appdelegate keyboard behavior separately from ACKs, including reentry and late delivery. Recheck direct clipboard 6/7 and image 8 RAW paths. Measure bridge overhead separately from OS/receiver work. Continue other P0-13 adapters and metadata codecs/copies, P1-40 invalidation and P0-12 qualification/unknown-start cases; C02 remains partial.
