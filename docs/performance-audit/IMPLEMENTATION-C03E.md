# C03e — prepare history error/log evidence before the file lock

Date: 2026-10-29 (Asia/Bangkok). Baseline: `10a952a5` (C03d); user reported that build passed.
Status: **source implemented; new Foundation/POSIX/ARC/sanitizer CI and device qualification pending**.
Finding: **P1-49 error/log-tail preparation slice**. C03 remains partial.

## Result and scope

Shared TLinkRunHistoryFinish now prepares terminal state, redacted/bounded error and the failure log tail before acquiring history.lock. It still holds the existing process-local synchronized monitor. Supplied tail normalization/redaction and the console-file fallback no longer hold the cross-process flock. Nonfailure states continue to skip tail preparation.

Compile the same two fixed redaction patterns once with dispatch_once and reuse an immutable regex array. Keep exact pattern/replacement order, Unicode/string handling and error/line/tail limits. There is no cache keyed by user content and no unredacted fallback on initialization failure. The macOS fixture requires two cold constructions across eight callers; its frozen implementation constructs two per redaction call. These are operation-count expectations awaiting macOS execution, not device CPU measurements.

This shared implementation is compiled by rootfull/roothide and production TrollStore streamd. TouchPOC is excluded. Both production workflows include the new history safety runner.

## Ordering and compatibility

After preparation, acquire the same lock and read the current index; no index snapshot is taken before locking. Preserve the original merge/insert, screenshot metadata/permissions, evidence/record/index writes, prune, lock release, event publication and status code. The new source check reconstructs the complete frozen implementation by reversing only the two intended changes.

Tail/error content now represents preparation before lock acquisition. External console edits while waiting for the lock are not added to that prepared tail. ended_at_ms is still sampled after acquiring the lock and reading the index, so elapsed preparation time can now precede that timestamp. Preparations still serialize callers in the same process; this change shortens only the cross-process critical section. A later lock-acquisition failure returns the same empty result, after the read-only preparation has run.

If an input description raises an NS/C++ exception during preparation, it now does so before opening/acquiring the history lock. The local synchronized monitor unwinds as before, without leaving that preparation's file lock behind. This is not a general exception-safety refactor of the remaining transaction.

JSON schemas, task60/status fields, return/event payloads, 50-run retention, failure state selection, 50 x 1000-character tail, 4000-character error, 256-KiB console read policy and screenshot fallback stay unchanged. Existing ignored-write-result/multi-file commit behavior (P1-53), screenshot work under flock, full index/evidence rewrite (P1-48), local monitor duration, status persistence reads and log retention remain open. No new durability, commit/recovery or device latency/RSS guarantee is introduced.

## Verification

Focused Windows source/equivalence and history-v1 contract checks pass. The frozen fixture contains the complete baseline shared implementation. The new source guard verifies exact redaction patterns/order and reverses the cache/preparation changes to require every other implementation byte to remain unchanged.

The macOS fixture includes actual/frozen full implementations with real private temporary JSON/log/evidence files and real flock. It controls clock/UUID for exact comparisons and intercepts chmod/chown and event publication; it never accesses the installed history directory or changes real ownership. Cases include eight cold regex callers, 1000 redaction comparisons, 75 begin/finish transactions for each implementation (both runtime labels, known/unknown runs, success/failure/cancel/revocation/default states), file fallback, placeholder screenshot presence/failure, retention/pruned record files, exact record/evidence/index/events and bounded status snapshots.

A POSIX-only child probes the real lock while description executes: the frozen function must keep it locked, while the new preparation permits the child to acquire it. NS/C++ preparation faults must leave the prior running record/events intact, no held file locks and a successful retry. All 65 workflow runners (36 source-contract, 29 native), 521 direct source-grep assertions, expanded standards-conforming assert preprocessing and git diff --check pass on Windows. Sixteen artifact-only checks require CI outputs. New Foundation/POSIX/ARC/ASan/UBSan execution remains pending on macOS; warnings and sanitizer policy remain enabled.

## Remaining work

Qualify cross-process status/finish contention and failure evidence on rootfull/roothide and TrollStore devices. Measure lock hold/wait separately from process-local serialization, tail I/O and persistence. P1-48/P1-53 history layout/commit work, the rest of P1-49, other C03 and outstanding C02 work remain open.
