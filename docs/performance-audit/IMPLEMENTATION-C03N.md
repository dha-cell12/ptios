# C03n — preserve event journal authority during publication

Date: 2026-10-29 (Asia/Bangkok). Baseline: `87aae836`, including C03m, build passed according to the user. Complete normalized event source SHA-256: `254bf7e79bcf76974ae95a8a0f585e452686f934c7c82ecf7cefa1811be59a16`.
Status: **build passed according to the user before C03o; independent device qualification pending**.
C03n remains working-tree source at this checkpoint (HEAD `87aae836`); normalized complete event source SHA-256 before C03o is `840748c9e52d871581b492b604225d32a1e3c767c67102c95951b3b3ab81fffa`.
Finding: **P1-58 publication preservation and exception-safe commit**. Read-only error reporting, missing-file epoch recovery and P1-54 full-journal cost remain open.

## Change

The shared publisher previously used the permissive reader: unreadable, empty or malformed journals became an empty next_sequence=1 journal and could overwrite retained events/reuse cursors. It also released flock only on the normal path; exceptions during read/event construction/serialization/write could retain its descriptor and lock.

A separate publication reader performs a checked NSData read under the existing process monitor/exclusive flock. Only Cocoa file-not-found errors bootstrap the existing v1 empty envelope. Permission/IO/unknown-domain/nil-NSError failures return event_journal_read_failed; empty/invalid JSON or invalid schema/shape/cursor return event_journal_invalid. Both stop before any write/hint and preserve disk state. Existing valid journal extension fields and events are copied as before; no repair, deletion or cached cursor is introduced.

Validate the v1 envelope and at most 256 events. Cursor/timestamp values must be non-boolean NSNumber values with nonnegative integral uint64 decimal values; next and event sequences must be positive. Events must have the existing schema, string ID/runtime/topic/type fields and dictionary payload. Retained sequences must be contiguous, below next and end at next-1. An empty journal may retain a nonzero next cursor; next=UINT64_MAX returns event_journal_sequence_exhausted before allocation/write, rather than allowing wrap. This is shape/cursor validation, not UUID uniqueness or cryptographic integrity checking.

Wrap the locked read/build/write transaction with NS/C++ containment and finally unlock. Exceptions return fixed state/error event_journal_exception without exception text/paths. Keep existing lock/write error labels. Successful events, payload normalization, timestamp/UUID construction, retention, compact atomic write/permissions and post-unlock Darwin hint are unchanged. A reported NO/exception after replacement is an uncertain outcome: no success hint, no rollback/replay; a later publication re-reads the actual disk cursor. Best-effort history/script lifecycle policy is unchanged.

The permissive poll/status reader and all async owner/cache/timer/admission/wire/license logic are unchanged in this stage. Shared rootfull/roothide and production TrollStore are in scope; TouchPOC remains excluded. No exported schema or SDK type changes.

## Verification

The event safety runner reverses only the publication reader, admission/overflow checks and transaction unwind, then hashes the entire file against the baseline above. This preserves successful event field/codec/notification and complete poll/status source. Guards also require missing-file classification, boolean rejection, contiguous/latest cursor checks, no writes in the reader, sequence exhaustion and finally unlock.

The existing actual-source Foundation/dispatch/notify/socket fixture gains controlled publication NSData read/write boundaries and tracked real flock/close calls. Before async owner initialization, cases cover genuine bootstrap, valid retained events/extensions/normalization, malformed JSON/schema/field types/cursors, oversized event count, ordering/duplicates/tail mismatch, non-number/fraction/boolean/negative/uint64-overflow values, read errors with Cocoa/POSIX/nil NSError, NS/C++ exceptions, a real directory at the journal path, empty nonzero cursor, UINT64 terminal state and explicit repair. A POSIX-only forked process must acquire the real lock after each rejection. No notification or write may occur on admission failure.

Writer false/NS/C++ faults before and after real atomic replacement must release the lock and suppress hints. The next explicit publication follows old/new disk authority without replay. Notification instrumentation requires that its thread holds no journal lock. The original B06 cross-process/missed-hint/read-counter/cancellation/authorization/deadline/pagination/wire/retention cases then run from a genuine missing journal. All files remain in the runner's private temporary directory.

All 65 workflow runners (36 source-contract, 29 native), 521 direct source-grep assertions, expanded standards-conforming assert preprocessing including the event runtime fixture, focused event source/portable/contract checks and git diff --check pass on Windows. Sixteen artifact-only checks require CI outputs. New Foundation/POSIX/ARC/ASan/UBSan branches cannot execute on this Windows host and await macOS CI.

## Remaining work

Fail-closed poll/status reporting and stale snapshot policy need their own coherent change. A genuinely missing journal still starts at 1; this does not solve lost-file cursor reuse or introduce epochs. Corrupt data needs explicit external repair/restoration; no automatic reconstruction or failed-event replay is added. Read/JSON parse size is not capped before decode, and every publish still reads/validates/rewrites the whole bounded event set. Measure added validation/lock hold cost, IO, latency and RSS on devices. Lock-inode hardening, noncooperating filesystem actors, fsync/power-loss ordering, exact delivery across uncertain writes and other C03/outstanding work remain open. Full P1-58 closure is not claimed.
