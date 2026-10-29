# C03o — checked event reads, explicit poll/status errors and cache invalidation

Date: 2026-10-29 (Asia/Bangkok). Baseline: user-passed C03n working source; HEAD remains `87aae836`. No separate C03n commit is inferred. Complete normalized event source SHA-256 before this stage: `840748c9e52d871581b492b604225d32a1e3c767c67102c95951b3b3ab81fffa`.
Status: **source implemented; new Foundation/POSIX/ARC/ASan/UBSan execution pending macOS CI; device qualification pending**.
Finding: **P1-58 read-only corruption/error reporting and stale snapshot policy**. Missing-file epochs and persistence reconstruction/durability remain open.

## Change

After C03n protected publication, poll/status still used the permissive reader. Invalid/read-failed journals could become ready empty history at cursor zero, malformed event fields could throw in batch formatting, and a failed refresh could leave an old snapshot usable on a later sweep.

Remove the permissive reader and share C03n's checked reader across all consumers. Its validation/missing-file policy is unchanged; the publisher only changes the private helper name. The snapshot loader captures fixed read/validation/NS/C++ errors, clears output fingerprint on failure and uses finally for descriptor/shared-flock release. Read-only failures never rewrite/delete journal data.

On every attempted snapshot-load failure, clear both the owner snapshot and fingerprint. Definite invalid/read/exception failures complete already-authorized polls with the error and no batch immediately. Transient lock acquisition failure retains the old wait-until-timeout/event_journal_unavailable policy, but cannot deliver the old snapshot. A remaining unauthorized waiter does not keep stale data alive. Authorization denial still occurs before data access; cancellation/admission/provider deadlines and owner reconciliation/timer policy stay unchanged.

Healthy status retains its existing implemented state and complete fields. Failed status uses state=error and a fixed error code; latest_cursor=0 is an unknown placeholder on that error path, not a reset acknowledgment. Consumers must inspect state. Existing legacy, root JSON, TrollStore and remote adapters already encode completion errors; no transport, schema, SDK type or success envelope change is needed.

Genuine missing-file reads still produce an empty journal without creating JSON; next=UINT64_MAX remains readable through the last cursor, while only publication rejects exhaustion. No epoch/reconstruction is introduced. Shared rootfull/roothide and production TrollStore use the implementation; TouchPOC is excluded.

## Verification

The event source guard reverses only checked-read reuse, loader error propagation/unwind, stale-cache clearing and status failure fields, then hashes the whole file against the user-passed C03n source above. C03n's full reversal to `87aae836` remains. Guards require the checked loader, exception/finally policy, no read-only journal writes, explicit cache clearing and error status, preserving all unrelated success/publication/owner/codec source.

The existing macOS actual-source fixture adds missing-file/terminal read compatibility; malformed schema/event/cursor reads; permission/POSIX/nil-NSError faults and NS/C++ exceptions through both public status and poll APIs; unchanged journal/write/hint counts and real external lock availability. A denied provider must run without a journal read. Two owner-barrier cases hold an authorization provider while a ready poll establishes cache, then induce corruption or controlled reader-lock denial. Both require snapshot/fingerprint invalidation while that unauthorized waiter remains; cancellation returns capacity, repair/publication precedes provider release, and the final poll reads fresh state. Wake hints are suppressed in these focused cases to keep late hints out of the existing quiet-read counter test; barriers and provider gates control progress.

A real held writer flock covers transient read timeout without blocking the owner. Additional cases require corruption errors through actual root legacy/JSON, TrollStore and remote adapters; then repair restores healthy status/ready polling, with no retained waiters/cache/leases. Original B06 cross-process/missed-hint/cancellation/deadline/pagination/wire/retention cases and C03n publication-preservation tests remain.

All 65 workflow runners (36 source-contract, 29 native), 521 direct source-grep assertions, expanded standards-conforming assert preprocessing including the updated event fixture, focused event source/core/contracts and git diff --check pass on Windows. Sixteen artifact-only checks require CI outputs. New Foundation/POSIX/ARC/ASan/UBSan execution cannot run on Windows and remains pending macOS CI. Device error recovery, contention, IO/latency/RSS and end-to-end reconnect behavior need qualification.

## Remaining work

A genuinely lost journal still permits bootstrap at 1; lost-file cursor reuse needs an explicit epoch/recovery protocol. No automatic corrupt-file reconstruction, failed publication replay, fsync or power-loss ordering is added. Snapshot validity still relies on the existing fingerprint/reconciliation/cooperating-writer protocol; arbitrary external file replacement is not instantly detected. Predecode byte limits, lock-inode hardening and full-journal publication cost remain open. Validation on read adds bounded event-field checks per load; no device performance percentage is claimed. Full P1-58 closure is not claimed.
