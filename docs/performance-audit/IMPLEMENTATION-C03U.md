# C03u — bounded Run History index IO and encoded output

Date: 2026-10-30 (Asia/Bangkok). Baseline: `232ebbe7`, C03t build passed according to the user. Complete normalized `shared/TLinkRunHistory.mm` SHA-256: `0a26786c6524c793502bf585c3c87583fe34676e446a9579439395500f76312e`.
Status: **build passed according to the user before C03v; committed at `d4f8fa95`; independent device qualification pending**.
Finding: **P1-48/P1-51/P1-53 index byte admission**.

## Change

The checked reader previously loaded an arbitrary-size NSData before validating JSON. Add a 32-MiB regular-file admission limit before buffer allocation/parse. Open read-only with NOFOLLOW/NONBLOCK under the same monitor/flock. Only actual open ENOENT means absence; other open/stat/nonregular/negative-size errors report read_failed. Direct symlinks, dangling links, FIFO and directories are refused without payload IO.

Read admitted bytes in at most 64-KiB calls with EINTR/short-read handling. Early EOF/read failure is read_failed; probe at most one additional byte for observed growth (index_too_large at the cap, read_failed below it). Close in finally, including NS/C++ faults. Valid exact-cap files remain readable; empty regular files remain invalid indexes. Begin/finish and snapshot validation share this helper; no schema/retention changes.

Oversize reads preserve files/markers/recovery flags/events and report read/index_too_large for mutation, history_snapshot_too_large for status. Existing SDK error handling rejects that new fixed string. Replace the old Cocoa/NSError absence classification with the checked POSIX boundary. Existing semantic read-fault tests retain their error expectations; actual open/stat/read faults are covered separately.

Only encoded index output gains the same cap before atomic write. Record/evidence encoding is unchanged. An oversized index follows existing index-stage write_failed/pending recovery policy: no index replacement, ACK or event; earlier record/evidence writes can remain ahead/orphaned, marker stays pending and the next mutation repairs retained metadata from the authoritative index. No rollback/replay, fsync or multi-file atomicity is added.

32 MiB leaves room above roughly 17.4 MB for fifty runs containing the existing worst escaped bounded error/log-tail fields. Arbitrary extensions/settings remain unbounded producers and can be refused. Existing files exceeding the cap need explicit maintenance; the reader does not truncate or repair them. Shared rootfull/roothide and production TrollStore are covered; TouchPOC is excluded.

## Verification

The guard reverses only the helper/constant, previous NSData reader prefix, index-writer cap and status too-large mapping, then hashes the complete C03t source. Earlier full-source mutation/recovery/status guards remain. Require regular nonfollowing/nonblocking admission, size-before-allocation, bounded chunks/EINTR/EOF probe/finally and an index-only writer cap before atomic write.

The actual-source Foundation fixture records private index descriptors, allocations, syscall counts and bytes. Real sparse 32-MiB-plus-one input must reject status/begin/finish before any buffer/payload read; exact-cap padded valid JSON must read in bounded calls and remain writable. Cover open/stat/negative-size/EOF/EIO/EINTR/short/NS/C++/growth faults, direct symlink/dangling/FIFO/directory refusal, unchanged bytes/target modes and balanced descriptors/flock. Original semantic read/exception/SDK/status tests remain.

A controlled encoded NSData boundary tests exact-cap output and oversized public begin/finish output without enormous ahead artifacts. Require no index write attempt, old index bytes/events preserved, one earlier record write, pending marker/local invalidation and subsequent ordinary recovery/ACK without replay. Real JSON encoding of fifty worst-escaped bounded error/log-tail records must exceed 16 MiB but fit below 32 MiB and return healthy fifty-run status. This is fixture byte evidence, not device RSS/latency evidence.

Windows validation: all 65 workflow runners pass after a focused console-log rerun cleared an exe-unlink EPERM during temporary cleanup; its assertions also passed in the initial sweep. All 521 source checks, focused full-source/history contracts, eleven actual SDK-method cases, expanded assert preprocessing and `git diff --check` pass; sixteen artifact-only checks skipped. New Foundation/POSIX/ARC/sanitizer execution requires macOS CI; device qualification is separate.

## Remaining work

The cap bounds raw file/buffer and encoded-index bytes, not JSON graph/RSS, producer serialization, record/evidence output or IO/lock time. Every mutation still rewrites the full index; every status reads it. This stage adds no cache, root/ancestor/lock-inode hardening, orphan discovery/replay or power-loss guarantee. Full P1-48/P1-51/P1-53, log retention and other C03/device work remain open.
