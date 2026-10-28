# C03g — check history write results before acknowledging mutations

Date: 2026-10-29 (Asia/Bangkok). Baseline: `2eb7deaa` (C03f); user reported that build passed.
Status: **build passed according to the user (`c2a3bec5`); device qualification pending**.
Follow-up: user reported the C03g build at `c2a3bec5` passed before C03h. Device qualification and the recovery limitations below remain open; the verification section records checks available when C03g was implemented.
Finding: **P1-53 checked-write/acknowledgment slice**. Multi-file recovery remains open.

## Result and commit policy

Shared history begin/finish now check every required record/evidence/index write. A false result stops the mutation, returns an empty history dictionary and suppresses that mutation's script.run event. NS/C++ exceptions inside the locked transaction are contained in the same way. Lock acquisition failure also returns empty. The existing callers tolerate a missing history run ID/ignore the finish result, preserving the actual script lifecycle for these persistence failures.

The positive result of the atomic index write is the logical acknowledgment point. Prepare the bounded index in memory, write evidence when required, write the record and then write the index. Only after index-write success remove artifacts of records retired from the index. Cleanup stays under the same flock so a cooperating finisher cannot recreate a retired ID between commit and deletion. Both mutation functions release the file lock in finally on success, early return and transaction exception; event publication follows release.

Retirement now has two steps: trim the pending index without file I/O, then best-effort artifact removal after successful index acknowledgment. A cleanup exception increments diagnostics but does not turn an already committed mutation into failure or suppress its event. Removal BOOL behavior remains best effort; this is not a new orphan-recovery policy.

This shared source is compiled by rootfull/roothide and production TrollStore streamd. TouchPOC is excluded. No license/task/script-result changes or new retry are introduced. Pre-lock error/tail preparation and snapshot behavior from C03e/f remain, including their existing failure semantics outside this locked mutation.

## Bounded diagnostics and compatibility

Task60 run_history adds optional persistence_diagnostics with scope=process, a saturating uint64 failure_count and an immutable last_failure dictionary. That dictionary holds only fixed operation/stage/code labels and at_ms; it never copies exception text, paths, script errors or log bodies. Failures include required writes, transaction exceptions, denied begin/finish locks and cleanup exceptions. Generic exception labels avoid depending on Objective-C++ unified exception dispatch. The existing local history monitor protects these values; successful operations do not reset them. Other processes may have different counters and restart resets them.

WebTango's SDK adds an optional type for the field, compatible with older devices. Existing record/evidence/status fields, schema/capability versions, successful return/event payloads, JSON formatting, redaction and retention limit remain. Exact golden comparisons exclude only the new diagnostic key and separately verify its scope, failure count, labels, privacy/size and saturation.

## Limits and recovery

This is a sequence of individually atomic file writes, not an atomic multi-file transaction. A failure after evidence/record writes may leave those files ahead of the unchanged index or create orphans. A reported error after an index replacement has an uncertain outcome: suppress success/event, retain old artifacts and avoid automatic rollback/replay. Crash recovery, coherent restoration of record/evidence/index files, orphan retention and event-journal delivery are still separate work. No fsync/power-loss durability or exactly-once event guarantee is added. P1-53 is not marked fully qualified/complete.

## Verification

The source guard reverses C03g's checked writes, retirement order, transaction wrappers and diagnostic field to reproduce the complete frozen C03f implementation. The existing C03e/f inverse guards then compare against the earlier baseline. The macOS fixture retains full successful-path record/evidence/index/event/status/retention comparisons.

New fault cases cover begin record/index and finish evidence/record/index, each returning NO or throwing NS/C++ exceptions. They require empty acknowledgment, no event, unchanged old index, retained artifacts referenced by that index, one failure count, correct bounded labels, no credentials in diagnostics, released flock and a successful subsequent operation. Additional cases cover denied locks, index-read exceptions, non-JSON settings, cleanup exceptions after commit, counter saturation and a post-write false result without rollback/replay. Only private temporary files are used; write/removal faults and event/permission effects are controlled. New macOS Foundation/POSIX/ARC/ASan/UBSan execution and device qualification remain pending.

All 65 workflow runners (36 source-contract, 29 native) have passed on Windows: the initial sweep passed 63; console/OCR assertions passed but temporary exe cleanup hit Windows EPERM, and their focused rerun passed including cleanup. All 521 direct source-grep assertions, expanded standards-conforming assert preprocessing, focused source/history contract checks, git diff --check and the SDK non-strict targeted compile pass. Sixteen artifact-only checks require CI outputs. Strict SDK comparison against HEAD shows no added diagnostics and accepts the optional empty last_failure shape; both versions retain existing TS7023 errors in getNativeScale/getNativeScaleForSize. Full WebTango type checking is also blocked by existing syntax errors in scratch_ios_stream.ts:701 and test-track.ts:1. Those files/functions are unchanged. New macOS-only fault cases still await CI execution.

## Remaining work

Qualify disk-full/permissions/interrupted-write/stop/restart behavior and inspect process-local diagnostics on rootfull/roothide and TrollStore. Complete multi-file recovery/orphan retention and commit-to-event recovery before claiming full P1-53 closure. Other history layout/cache/lock/retention, event recovery and C03/outstanding C02 work remain open.
