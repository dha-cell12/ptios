# C02b45 — direct alert adapter and CF notification ownership

Date: 2026-10-28 (Asia/Bangkok). Baseline: `78359d2`, containing C02b44; the user reported that build passed.
Status: **source implemented; new macOS/Foundation/ARC/sanitizer CI and device qualification pending**.
Finding: **P0-13, alert task 12**. Other adapters, metadata codecs/copies and performance qualification remain open.

## Result and compatibility

The rootfull/roothide alert JS adapter now calls TLinkExecuteNativeAlert and the existing showAlertBox backend directly. Ordinary title/message calls avoid the full RAW task string, full request split/intValue parser, processTaskWithContext, compatibility CF stream and response-vector accumulation/copy. Individual description/decimal formatting, input snapshots, validation and bounded reply formatting remain. Generic RAW task 12 and its task handler stay available. Production TrollStore and TouchPOC execution sources are unchanged; both workflows run the shared safety suites. No CPU, allocation, latency or RSS improvement has been measured.

Keep title/message defaults, duration intValue/default-three normalization and the original handling of nil, descriptions, Unicode and newlines. A duration object that lacks intValue still raises at the unchanged JS normalization boundary; this is tested separately from normalized native errors. Full admission retains the task/separator/duration-inclusive 8192 UTF-16 limit, UTF-8 byte bound and embedded-NUL/encoding rejection before the ordinary gate.

The old delimiter parser can shift fields when text contains semicolons, including a single trailing semicolon overlapping an inserted ;; separator. Such inputs take a bounded compatibility branch that formats and splits the title/message/duration fields together, without RAW dispatch. Preserve the first three parsed fields, integer conversion, exact zero-duration error and historically accepted negative parsed durations. Ordinary text bypasses this split. Success remains 0 followed by CRLF; existing non-null notification create/receive error logging still returns that ACK.

The shared CF owner now checks a failed CFUserNotificationCreate before use/release and releases a non-null notification in @finally, including when receive/log raises an NS/C++ exception. Null creation safely returns through the existing void backend and therefore produces the existing outer success ACK; this prevents the former null CFRelease crash, but does not report a new display-success guarantee. Non-null successful and error paths keep the same dictionary keys, Ok button, create timeout/flags, receive timeout and logging order.

## Authority, effects and lifetime

Every ordinary alert call retains one task-12 license gate; owner automation authorization does not bypass it. The child context retains owner fields, inherited deadline, cancellation and output settings with response capture disabled. Task 12 adds no C01-local deadline. Stop is checked after conversion, before/after the gate and after backend work. Scoped budgets and per-call pools restore TLS and preserve snapshots/results.

CFUserNotificationReceiveResponse remains opaque synchronous work using the existing duration. It is not interrupted or moved to a queue. Accepted work may display/wait before caller cancellation/deadline, output rejection or an escaping exception is reported. No retry or rollback is added. Escaping backend NS/C++ exceptions normalize to native_exception at the direct entry; the shared CF release still runs. Real SpringBoard notification behavior, blocking/thread policy and user interactions require device qualification.

## Verification

All 62 workflow runners (36 source-contract, 26 native), 521 direct workflow source-grep assertions and git diff --check pass on Windows. Expanded standards-conforming assert preprocessing retains its rejecting negative control. New macOS/Foundation/ARC/sanitizer branches cannot execute on this host; sixteen artifact-only workflow checks require CI outputs. No warning or sanitizer checks are disabled.

The macOS fixture compiles the actual parser, CF owner, direct task entry and complete alert JS branch against the 78359d2 frozen core/task/bridge oracles. Controlled create/receive/log boundaries use real owned CFString tokens to check release balance without displaying alerts. Source guards compare the unchanged RAW handler and reconstruct the frozen backend after removing only the new null check and ownership wrapper; forward declarations precede actual and renamed legacy core inclusion.

Coverage includes 160 ordinary cases, defaults/description/intValue behavior, Unicode/newlines, semicolon overlaps and shifted negative/zero durations, exact/over-limit input, NUL/encoding, output boundaries, non-null create/receive errors, one task-12/owner-denial gate, initial/gate/provider stop/deadline, opaque accepted effects, NS/C++ provider/log faults, null creation, mutable input snapshots, retained result/dictionary lifetime, malformed standalone RAW parser parity and 1000 balanced real CF lifecycles. Unsafe null-creation/escaping-fault paths are tested against the corrected owner, rather than executing the leaking/crashing frozen implementation.

## Acceptance and remaining work

The user reported C02b44 build success at 78359d2; that does not qualify the new alert path. Build rootfull/roothide, then compare typed/helper alerts with RAW task 12 for normal and delimiter/Unicode text, duration normalization, exact replies and license denial. Verify actual display/dismissal/timeout behavior and repeated CF lifecycles, including caller stop/output failure after an accepted alert. Measure bridge overhead separately from user-response wait. Continue other P0-13 adapters and metadata codecs/copies, P1-40 invalidation and P0-12 qualification/unknown-start cases; C02 remains partial.
