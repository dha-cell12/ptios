# C03h — preserve history when mutation index reads fail

Date: 2026-10-29 (Asia/Bangkok). Baseline: `c2a3bec5` (C03g), build passed according to the user.
Status: **build passed according to the user (`c8d2d085`); device qualification pending**.
Follow-up: C03i adds lazy first-mutation recovery of retained metadata; the verification/limits below describe C03h when implemented.
Finding: **P1-53 read-failure/data-preservation prerequisite for recovery**. Multi-file recovery remains open.

## Result

Previously begin/finish used the permissive status reader: missing, unreadable, empty or malformed indexes could become an empty array. A subsequent successful write could replace the index and discard references to older runs. Mutations now use a separate checked reader under the existing process monitor and file lock, before any evidence/record/index write or retirement.

Only NSData's Cocoa file-not-found errors bootstrap an empty index. A failed read with another error, another domain or no NSError stops the mutation with read_failed. An existing empty file, malformed JSON, missing/unsupported/non-string schema, non-array runs, non-dictionary entries, missing/empty/non-string run IDs or duplicate IDs stop with invalid_index. Valid v1 empty arrays and extra envelope keys remain accepted. Required shape checks cover the envelope and run identities, not every optional record field.

These failures return an empty history result, preserve all existing history bytes/artifacts, skip mutation events and increment C03g's bounded process diagnostics with operation begin/finish, stage read and a fixed code. NS/C++ reader exceptions retain C03g's exception diagnostic and finally-based lock release. No exception text or file contents enter diagnostics. Existing script callers remain best effort; the script lifecycle continues when these persistence failures are contained.

Successful mutations retain their record/evidence/index fields, JSON formatting, events, retention, atomic writes and post-index cleanup order. The permissive status reader, its lock window and existing fallback behavior are unchanged. No schema/capability or SDK type change is required. Shared rootfull/roothide and production TrollStore source is covered; TouchPOC is excluded.

## Recovery boundary

This prevents a damaged/unreadable index from being silently replaced by a new mutation. It does not reconstruct an index, repair record/evidence files, remove orphans, replay events or add a retry. After an explicit valid-index restoration or resolution of the read problem, the next normal mutation can succeed. A missing index still bootstraps empty even if loose artifacts exist; those files are not treated as authoritative recovery input.

C03g's separate atomic writes and uncertain post-write outcomes remain. No new fsync/power-loss guarantee, multi-file crash atomicity or complete P1-53 closure is claimed. Status retains its earlier permissive behavior and is not a complete malformed-record validator. Real device disk-full/permissions/stop/restart and recovery policy remain to qualify.

## Verification

The source guard removes only the new checked mutation reader and its two guarded call sites, then retains the full C03g-to-C03f and C03e/f-to-frozen-baseline inverse comparisons. Runtime fixtures still compile the actual changed source, while the frozen oracle stays unchanged. Existing successful transaction/record/evidence/event/status comparisons and write-fault tests remain.

New macOS cases use a private real history tree: genuine missing-index begin and finish; 16 invalid index variants for both mutations; controlled permission, unexpected error-domain and missing-NSError read failures; a real directory at the index path; accepted empty v1/extension envelopes. Rejections require no write attempts/events, exact unchanged file bytes, one diagnostic, released flock and a child-process lock probe. Explicit fixture restoration is followed by a successful normal mutation; no automatic production repair is assumed. Existing tests cover NS/C++ read exceptions. Foundation/ARC/ASan/UBSan execution of these new cases remains pending CI.

All 65 workflow runners (36 source-contract, 29 native) pass on Windows, including focused history source/contract checks. All 521 direct source-grep assertions, expanded standards-conforming assert preprocessing and git diff --check pass. Sixteen artifact-only checks require CI build outputs. Windows does not execute the Foundation/POSIX/ARC/sanitizer branches; new macOS cases and real device qualification remain pending. No SDK or unrelated TypeScript changes were made.
