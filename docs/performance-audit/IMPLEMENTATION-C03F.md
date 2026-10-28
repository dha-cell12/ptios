# C03f — release the history file lock before status formatting

Date: 2026-10-29 (Asia/Bangkok). Baseline: `76fe52ec` (C03e); user reported that build passed.
Status: **user reported build `2eb7deaa` passed before C03g; independent device/performance qualification pending**.
Finding: **P1-49/P1-51 snapshot file-lock window slice**. Persistence-read caching and other C03 work remain open.

## Result and scope

Shared TLinkRunHistorySnapshot now holds history.lock only while reading/decoding the index. A finally block releases the file lock before limit selection, error/log-tail truncation, failed-count calculation and construction of the status dictionary. The same finally also runs when the index reader raises an NS/C++ exception. Status formatting exceptions occur after the file lock has already been released.

The decoded mutable JSON graph belongs to this call; formatting uses that captured graph without rereading the file. A cooperating process may commit a newer index while formatting runs. The current response represents the earlier decoded index; a later snapshot reads the new one. No cross-call cache or shared graph is introduced. The existing process-local synchronized monitor still covers the full operation, retaining local serialization and the previous per-process formatting concurrency.

This shared code is compiled by rootfull/roothide and production TrollStore streamd. TouchPOC is excluded. Both workflows already run the extended history safety runner.

## Compatibility and limits

Keep all snapshot fields, order/limit/default policies, 500-character error and 3 x 240-character tail summaries, full-history total/failed counts and JSON/type fallbacks unchanged. Begin/finish, evidence preparation, screenshot permissions, retention, writes and event publication are untouched. The source guard reverses the snapshot lock-window change along with C03e's existing changes and requires the complete frozen baseline implementation to match.

This shortens the cross-process critical section; it does not reduce the number of persistence reads, move JSON decoding outside flock, parallelize local status formatting or add a freshness/durability promise. Existing malformed/missing-index normalization and lock-acquisition-failure read fallback are deliberately retained; this slice does not correct those error-policy issues. Commit/recovery and broader transaction exception handling remain separate work.

## Verification

Focused Windows history source/equivalence and history-v1 contract checks pass. The macOS fixture retains the actual/frozen full implementation comparisons from C03e: redaction, 75 transactions per version, exact records/evidence/index/events/status/retention and failure preparation.

New cases probe the real flock from a POSIX-only child at the start of status formatting: the frozen snapshot still holds it, while the new one permits acquisition. A controlled writer takes the released flock and atomically replaces the private index after decode; the in-flight snapshot must remain identical to its earlier graph, use exactly one index read and expose the changed state/error on the next call. Mutating a returned status must not change another call or persistence.

Injected NS/C++ read and formatting faults must leave no held history lock, preserve the index/events and allow the next call to recover. Lock-denial and empty/malformed/non-array-index cases retain the frozen response policy. The fixture uses private temporary files, real flock and controlled clock/UUID/permissions/event publication. All 65 workflow runners (36 source-contract, 29 native), 521 direct source-grep assertions, expanded standards-conforming assert preprocessing and git diff --check pass on Windows. Sixteen artifact-only checks require CI outputs. Warnings, ARC, ASan and UBSan remain enabled. New macOS-only execution and device lock/latency/RSS qualification remain pending.

## Remaining work

Measure cross-process writer/status contention and local monitor wait separately from index I/O/parse and formatting. P1-51 still needs a qualified persistence/status strategy; P1-48/P1-53 history layout/commit work, the rest of P1-49, retention, event recovery and other C03/outstanding C02 work remain open. No device improvement percentage is claimed.
