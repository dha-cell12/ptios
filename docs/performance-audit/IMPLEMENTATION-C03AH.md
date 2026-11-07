# C03ah — Console vectored append and sink lifetime package

Date: 2026-11-07 (Asia/Bangkok). Baseline: `778aa518`; user reported C03ag build passed and requested larger implementation batches. Scope: the in-process JS runtime used by rootfull/roothide, P1-42. Production TrollStore/helper logging and TouchPOC are unchanged. Both workflows retain their existing console safety runner.

## Changes delivered together

- Multi-entry batches for an existing file now borrow the already-owned immutable NSData buffers and write their spans directly. The ordinary append path no longer constructs the previous joined NSMutableData buffer, conservatively bounded at 1 MiB. The batch continues to own every source NSData until the writes finish; no persistent descriptor, additional queue, delayed flush or format change is introduced.
- The actual portable cursor advances across both whole and partially written spans. Positive progress is never replayed; EINTR retries only the unacknowledged suffix. Zero progress, EIO/EAGAIN, other errors and impossible provider over-returns fail the current group. Provider NS/C++ exceptions retain the existing caught-failure policy; NSFileHandle closes in finally. An error after a committed prefix marks the group failed without retrying the whole group. Each file still receives an independent attempt.
- Probe the operating-system vector limit once, clamp to 1..64 and use one vector when the probe refuses/fails. Every syscall respects this capacity; the cursor handles additional chunks without resetting file position. The maximum input plan is 64 vectors/1 MiB, with checked aggregate arithmetic and no heap allocation in the cursor.
- Preserve the original second metadata/rotation check and single-entry writer. A missing-file multi-entry batch still builds one bounded buffer and uses the original atomic NSData writer. Oversize-file/failed-remove behavior, independent run/latest rotation, file permissions and no-replay masks remain. This package removes the joined copy on ordinary existing-file batches, not every logging allocation.
- Give each system-sink call a normal local autorelease pool. Existing NS/C++ catches execute inside that pool, allowing normal retirement on both successful and handled-failure returns. The existing outer batch still owns the entry text; public logging stats, ordering and finish drain remain unchanged.

The cursor follows Apple's documented ordered vectors and byte-count progress contract for [writev](https://developer.apple.com/library/archive/documentation/System/Conceptual/ManPages_iPhoneOS/man2/writev.2.html), using the limit exposed by [sysconf](https://developer.apple.com/library/archive/documentation/System/Conceptual/ManPages_iPhoneOS/man3/sysconf.3.html). The existing NSFileHandle still owns and closes the descriptor; POSIX writing borrows it only within the append scope. A failing low-level write does not promise the same opaque Foundation exception timing as the former writeData call.

## Verification

Windows passes all **90 workflow runners** (36 source,54 safety), **521 source assertions** (16 artifact-only checks skipped), JavaScript syntax, nine-file assertion macro preprocessing and git diff --check. Apple native branches are not executed on Windows. The focused console runner also checks every new native extraction seam on this host.

The actual portable vector cursor executes **100,000 independent concatenation/partial/EINTR oracles**, covering 0..64 input spans, 1..64 vector capacities, empty spans and cross-span short writes. Additional cases exercise exact 1-MiB input, null/count/aggregate-overflow refusal before calling the provider, zero/EIO/EAGAIN after a committed prefix, missing errno, over-return and provider unwind. Existing console admission/concurrency/UTF16/rotation/failure-mask suites remain active.

Freeze the entire preceding batch-writer/system-emitter region. Reverse the new include, capacity helper, private method and two changed methods to the exact complete HEAD runtime before running all historical console guards. The original budget, batch planner, public runtime header, FileHandle/history/event implementations and helper/TrollStore source remain unchanged.

Extend the existing Foundation/POSIX/GCD/JSCore/ARC/ASan/UBSan executable rather than adding another workflow or executable. Native expectations include:

- Complete frozen batch file-byte parity under four requested capacities clamped to the real host limit, exact pointers into the retained source buffers, one former join versus zero ordinary-path joins, and atomic missing-file fallback.
- Real writev delivery with controlled seven-byte progress/EINTR, EIO after a committed prefix, zero/over-return, NS/C++ provider faults, invalid descriptor refusal and subsequent recovery. Assert exact file prefixes and failed masks, one close per handle, no registered descriptors left and no pending admission charges after drain.
- The existing full formatter/legacy per-line/rotation/missing-file/failed-remove/one-path/post-close/JSCore/concurrent-producer suite runs against the new writer. Healthy burst syscall counts follow host vector capacity; open/close and metadata counts remain two pairs/four checks instead of 128 each for the frozen per-line burst.
- Explicit MRC sink witnesses on successful and caught NS/C++ calls: peak one pending owner versus 64 for the preceding emitter, with all owners retired and captured text retained. These count controlled witnesses, not Foundation allocations or RSS.

Extraction adapts one writev call, the missing-file join factory, the old join factory and the vector-capacity return; frozen writer/emitter selectors receive separate names. Ordinary adapters still invoke real POSIX/Foundation providers. Current/frozen batch extraction and all six seams are checked before the host-specific native branch.

**New Apple compilation and Foundation/ARC/sanitizer execution require macOS CI.** No real device throughput, syscall timing, RSS, storage or syslog gain is measured. Blocking IO/opaque Foundation work, cross-process file writers, durability and device qualification remain open. This preserves the existing 64-slot/2-MiB disk+system admission policy; the atomic fallback can still allocate a bounded joined group. C03/P1-42 remains partial pending qualification. One checkpoint covers the complete package.
