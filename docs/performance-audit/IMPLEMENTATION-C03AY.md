# C03ay — Completed-log byte quota and bounded helper console payloads

Date: 2026-11-09 (Asia/Bangkok). Baseline: `1907f200`; user reported C03ax built successfully and requested a larger package. Scope: P1-42/P1-50 in the production root/roothide core/helper logging paths. TouchPOC is excluded. Production TrollStore keeps its separately implemented common debug-file policy.

## Retention by count and logical bytes

Extend the existing completion-proof cleaner with a 25-MiB logical-byte target as well as its 50-file target. Scan, proof, effective UID, permissions, link count, no-follow checks, nonblocking locks, metadata/path revalidation, incomplete4096-entry refusal and exact-leaf unlink remain unchanged. Existing C03ax completion proofs remain valid.

After sorting eligible completed files by the preceding mtime/nanosecond/name order, retain each newest candidate that fits both remaining budgets. Skip an oversized candidate and continue considering smaller older files; one outlier does not force all smaller logs to disappear. Selection uses checked subtraction and never adds a size that would overflow the remaining quota. Result plannedKeep/plannedBytes describe the selection, not a physical usage measurement after refused deletions.

An eligible completed file larger than25MiB can itself be retired, including a newly completed oversized log. Latest files and separately saved history evidence are outside this cleaner. History console paths remain advisory; history records/commit/recovery are unchanged. Sparse files count by their logical stat size, not allocated blocks.

Targets apply only to marked completed files of the same effective UID in one directory. Active/latest/unmarked/foreign/unsafe files are excluded; busy/changed/refused victims can leave actual usage higher until a later completion. Directories over the scan cap still preserve all entries. No global disk-byte, memory, IO-time, age, durability or arbitrary-filesystem-race guarantee is added. Legacy/orphan migration and unsupported/failed marking remain open.

## Helper JavaScript console path

The helper previously formatted arbitrary-length messages and encoded the same line separately for run and latest files. Route its actual `_tlinkautoLog` callback through one private ARC helper:

- Copy immutable prefixes of at most4096 UTF16 message units and64 units each for level/run metadata. Avoid splitting a surrogate pair. Preserve ordinary empty/Unicode/NUL/CR text and the preceding nil defaults; do not add carriage escaping or alter ordinary formats.
- Format the timestamped file line and encode UTF8 once. Accept only a nonempty payload of at most16KiB. Both file calls receive the same retained NSData. The existing helper rotation threshold, atomic missing-file creation, append/seek/finally-close behavior and per-path order remain for valid payloads.
- Attempt run and latest independently, then the bounded system log. NS/C++ exceptions in one sink cannot suppress the others or cause a prefix retry. A partial file write is not replayed. Nil/empty/oversized/throwing encoding produces no file IO; already prepared metadata can still reach the system sink. A metadata snapshot fault drops that auxiliary log call.
- Scope normal formatter/encoder temporaries inside owned pools and retain the prepared value across the inner pool. Keep the weak helper capture in the actual JSCore callback. A settled/deallocated helper receives no file calls; the system path retains its preceding weak-owner behavior with bounded text.

Oversized log text now uses a prefix without a suffix. This intentionally changes oversized output; ordinary complete strings retain their frozen output. Logger faults are best effort rather than script-fatal. Upstream JS argument conversion/description, Foundation internals, synchronous filesystem/system logging and exceptional deallocator behavior remain outside hard memory/time bounds. No asynchronous helper queue or dispatch deadline is introduced.

This change covers `_tlinkautoLog`. Structured terminal summaries, exception reporting, status/error fields and their original writer remain unchanged. They can still carry larger data, and latest/legacy files are outside the completed-byte target. No helper transport, session, license, storage API, public header, framework or build target is changed. The module explicitly requires ARC, matching the existing helper target/native fixture.

## Evidence and limits

Freeze the complete preceding helper callback and writer. A full-source reversal/hash guard removes only the new include/writer and restores that callback, reproducing the exact C03ax helper. Compose it before the C03ax and older storage guards. Root core/terminal hooks and existing ownership/proof logic remain unchanged.

Portable retention coverage now adds100000 independent newest-fit count/byte sequences, zero/exact quotas, zero-size records and UINT64_MAX/SIZE_MAX boundaries to the existing name/order/proof/identity cases. The existing macOS POSIX fixture gains real sparse8-MiB records,25-MiB selection,26-MiB outlier refusal with a smaller older file retained, exact512-KiB and zero-byte quotas. Existing lock/path/proof/process/lifetime cases remain.

Add a native Foundation/POSIX/JSCore/ARC/ASan/UBSan executable using the actual current module, prepared writer, actual old/new hooks and complete frozen old writer. Eighty full file/system/rotation comparisons cover missing/empty/exact/over-threshold files, four levels and five ASCII/Unicode/NUL/CR messages. Controlled expectations are two old encode calls versus one current call with identical NSData passed to both paths. Additional cases cover4095/4096/4097/100000-unit inputs, surrogate boundaries, mutable snapshots, cross-pool/weak-owner lifetime, metadata faults, nine open/partial/seek/write/close faults, nil/empty/oversized/NS/C++ encoding, date/system faults and recovery without replay. Files and sinks are private/controlled; no installed helper or real device syslog is exercised.

Windows validation passes all90 workflow runners (36 source,54 safety portable subsets),521 source assertions (16 artifact-only checks require CI outputs), source restoration/native extraction, JavaScript syntax, assertion macro preprocessing and diff whitespace. The existing console workflow invokes both retention and helper-console checks; runner count remains unchanged. New Apple compilation/native execution and device performance remain pending macOS CI/qualification. Operation counts are fixture expectations, not device allocation/latency measurements.
