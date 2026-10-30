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
