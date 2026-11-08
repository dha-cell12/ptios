# C03w — shared history snapshot locks

Date: 2026-10-30 (Asia/Bangkok). Baseline: `6be7edb0`, corrected C03v/C03u fixture build passed according to the user. Complete normalized `shared/TLinkRunHistory.mm` SHA-256: `c5be9dddc9420019a767030fe68a5374ab13bdd6f2b7fa362860f1608dd30410`.
Status: **user reported build `e6b1580a` passed before C03x; device contention and latency qualification pending**.
Finding: **P1-51 history status contention**, partial improvement.

## Change

History status previously took the same exclusive file lock as begin/finish while reading and decoding the index. Snapshot now requests blocking LOCK_SH through the existing validated lock helper. Independent cooperating reader processes can hold the lock together; a writer still requires LOCK_EX and waits for every reader. Default acquisition remains exclusive for begin/finish, recovery, pending-marker transactions and private mutation helpers.

The only production changes are the helper's optional shared selector, flock mode selection and snapshot's explicit shared call. Direct-directory/regular-single-link/inode validation, descriptor permissions, bounded checked reads, error envelopes, finally release, release-before-format, local serialization, index authority and mutation/recovery behavior stay unchanged. Shared readers retain the existing preparation and permission metadata operations. No status cache or polling change is introduced. Shared rootfull/roothide and production TrollStore are covered; TouchPOC remains excluded.

## Verification

Reverse only these three source changes and compare the entire source with the user-passed baseline. Keep all earlier full-source guards. The public contract guard checks explicit shared selection and default exclusive acquisition. The actual Foundation fixture now tracks shared ownership, injects lock failures for both acquisition modes and runs post-flock inode replacement tests for shared status as well as exclusive mutations.

New real POSIX cases acquire two independent shared descriptions for 32 lifecycles: a child reader succeeds, a child writer is refused, releasing the first reader still excludes a writer, and releasing the final reader admits it. Forked probes close inherited lock descriptions before opening their own and use only POSIX calls in the child. Eight actual public snapshots are probed during their checked read, followed by NS/C++ read exceptions; require peer-reader admission, writer exclusion, unchanged read-side marker/write/event counts and complete release on errors. Actual public begin/failed finish must exclude both peer modes and leave a clean marker with no live handles. Existing successful snapshot parity and read/refusal/recovery tests remain.

Windows validation passed: all 65 workflow runners (36 source, 29 native), 521 workflow source checks, focused full-source/history guards/contracts, expanded assert preprocessing including the new fixture and `git diff --check`. Sixteen artifact-only checks were skipped. New Foundation/POSIX/ARC/sanitizer execution requires macOS CI; no on-device throughput or latency measurement is claimed.

## Remaining work

The process-local monitor still serializes callers within one process. Every snapshot still reads and decodes the full bounded index. Blocking flock has no deadline or fairness guarantee; a stream of readers can affect writer wait time. Existing binaries using exclusive reads remain compatible but do not gain reader overlap until updated. Stable lock inode/cooperative actor requirements remain. Caching/cadence, JSON graph/RSS, IO duration, log retention, broader recovery and power-loss durability remain separate work.

## CI fixture correction — independent lock probe (2026-11-08)

The wait/exit assertion in the old fork-based peer failed without distinguishing a signal, open error or unexpected flock errno. Its child used the inherited Foundation/ASan process image and returned the same exit 2 for unrelated errors. The log does not establish the exact earlier syscall failure.

Compile a small separate POSIX helper with the existing strict warnings and ASan/UBSan. Parent probes launch it with posix_spawn and explicit close actions for every tracked inherited lock descriptor, then wait/reap it. The helper independently opens the path with nonblocking/no-follow flags, retries interrupted open/flock, and returns only 0 (acquired) or 1 (EWOULDBLOCK/EAGAIN contention) as valid outcomes. Other errors print the operation stage/errno; parent failures also print wait error, exit status, signal and path. No unexpected status is converted to a contention result and no admission assertion is removed.

Existing paired-reader, held-owner, actual snapshot/mutation, last-reader release and unwind tests remain. Native runner preflight checks idle SH/EX and captures a missing-file error, proving that open failure is not misclassified as a held lock. Production lock policy, permission handling and the runtime deadline are unchanged. The helper executable is resolved beside the fixture executable for every worker/recovery process.

Windows history source/portable checks, three-file assertion macro preprocessing, JavaScript syntax and diff whitespace pass. Native helper/ASan/UBSan and Foundation integration require macOS CI. This replaces the fixture's fork setup; it is not a claim of measured production contention or an identified production locking defect.
