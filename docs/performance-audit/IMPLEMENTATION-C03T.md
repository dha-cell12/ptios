# C03t — checked Run History status and SDK error handling

Date: 2026-10-29 (Asia/Bangkok). Baseline: `c20c70d9`, C03s build passed according to the user. Complete normalized `shared/TLinkRunHistory.mm` SHA-256 before this stage: `34b6f42b08b699ff32aa49b6dd9120db2f546e6ea4c00907589b3d6769701e58`.
Status: **build passed according to the user before C03u; committed at `232ebbe7`; independent device qualification pending**.
Finding: **P1-51/P1-53 status persistence authority**, before a separate caching/read-cadence optimization.

## Change

The previous snapshot reader treated missing, unreadable or malformed indexes as empty history and read even after file-lock admission failed. Remove that permissive reader. Rename the existing mutation reader to a common checked reader and use it for status under the same monitor/flock. Keep mutation validation and missing-file policy unchanged: only its existing confirmed Cocoa missing-file classification bootstraps empty; validate JSON envelope/schema/runs and nonempty unique string run IDs.

Refuse index IO on lock failure. Read failures or invalid indexes return a fixed error snapshot after releasing any acquired lock. Catch NS/C++ setup/read/format faults and report a fixed exception label with a process diagnostic. Successful snapshot fields, limit selection/truncation, fresh decoded graph ownership and release-before-format behavior are unchanged. A formatting failure returns no partial run list.

Failure envelopes retain schema/root/limits/diagnostics with state=error and one of history_snapshot_lock_failed/read_failed/invalid_index/exception; runs/counts are unknown empty/zero placeholders. Diagnostics use snapshot operation, fixed stage/code/time and the existing saturating counter. They do not invalidate mutation recovery. Status does not repair/write/prune index/record/evidence, change the pending marker, recover or emit events. Existing directory/lock setup and permissions remain.

WebTango getRunHistory rejects the error snapshot, using a nonempty string code or a fixed fallback. Keep task-60/schema/transport and ordinary returns; widen status types with error state/optional error and snapshot diagnostics. Raw callers must inspect run_history.state. Shared rootfull/roothide and production TrollStore are covered; TouchPOC is excluded.

## Verification

The source guard removes the failure builder, restores the frozen C03s snapshot and permissive reader and reverses only common-reader naming/comments, then hashes the complete history source against c20c70d9. Successful formatting is additionally compared literally after indentation normalization. Prior compact-index/retirement/marker/recovery/commit/preparation full-source checks remain. Require no status mutation/recovery/event calls and fixed error/lock-before-read/finally behavior.

The actual SDK method runs on Windows with only its two TypeScript annotations erased: four fixed backend errors, four malformed error fields, malformed runs shape and an unchanged healthy extension graph. Every case uses the actual method's wait/open and task-60/5000-ms request path. Type checking compares strict diagnostics with HEAD.

The Foundation fixture retains successful frozen status, field limits, captured-index freshness/caller isolation and writer/recovery tests. Update only the intentional old failure expectations: read/format exceptions become contained errors; lock denial performs zero reads; malformed status differs from the frozen successful-empty result. Save/restore these new process diagnostics in the fixture so the original writer suite retains its zero-state oracle.

New private-root cases cover missing and valid-empty history, sixteen malformed schema/shape/identity cases, permission/domain/nil-NSError failures, NS/C++ read/format faults, lock denial, a real directory and malformed state formatting. Require exact fixed error/diagnostics, unchanged JSON/marker bytes, no JSON write/prune/event/recovery work, unchanged recovery gate, released locks/descriptors and explicit fixture restoration followed by healthy status. Foundation/POSIX/ARC/sanitizer execution requires macOS CI.

Windows validation passed: all 65 workflow runners, 521 source checks, focused history guards/contracts, ten actual SDK-method cases, expanded assert preprocessing and `git diff --check`; 16 artifact-only checks were skipped. Targeted strict SDK comparison adds no diagnostics; existing TS7023 errors in getNativeScale/getNativeScaleForSize remain. New Foundation/POSIX/ARC/sanitizer execution requires macOS CI; device qualification remains separate.

## Remaining work

No cache, new persistence format, repair/replay or durability guarantee is added. Status still loads/decodes the index for each call, and file/JSON size, arbitrary malformed record fields, blocking lock/IO time and total RSS are not newly bounded. P1-51 cadence/cache, P1-48 compact evidence layout, P1-50 log retention and the broader C03 recovery/device work remain open. No measured performance improvement or complete P1-53 closure is claimed.
