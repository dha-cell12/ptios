# C03p — validate event root and held lock inode

Date: 2026-10-29 (Asia/Bangkok). Baseline: `7569c26d`, including C03o, build passed according to the user. Complete normalized event source SHA-256 before this stage: `8a16c9ec819f44bad5cdfaa9e2dabd313d3e370f8493612f9003a3115c7917c3`.
Status: **build passed according to the user before C03q (source `a39ec7b7`); independent device qualification pending**.
Finding: **C03/P1-58 persistence lock admission and identity**, a prerequisite to preserving journal authority across cooperating actors.

## Change

The existing event lock open followed leaf symlinks and could block on a special file. It changed pathname permissions before taking flock, with no regular-file/link-count or post-wait pathname identity validation. Replaced lock paths could split cooperating actors across different inodes.

Check the direct event root with lstat before permission changes or lock open. A missing root may be created, then checked; a non-directory/symlink root is refused. Existing ancestors remain as the platform filesystem arranges them; this is not descriptor-relative validation of every ancestor.

Open the lock with O_CREAT|O_RDWR|O_NOFOLLOW|O_NONBLOCK. Require fstat regular type and one link before flock. Keep shared readers, exclusive writers and each caller's existing LOCK_NB choice. After acquisition, lstat must still show a singly-linked regular pathname with the opened device/inode; the direct root must still be a real directory. Failure unlocks/closes before journal access. Permission calls target the validated descriptor via fchmod/fchown after admission, without changing a replacement pathname. Preserve the old best-effort handling of permission syscall failure.

Use existing error contracts: publisher event_journal_lock_failed; loader/status/poll event_journal_unavailable. Read/write/notification/cache/admission/authorization/wire success behavior is unchanged. Never remove or rewrite rejected lock files. O_NONBLOCK prevents the open from parking on special files; ordinary publisher/status flock can still wait, and the poll owner remains nonblocking. Shared rootfull/roothide and production TrollStore are in scope; TouchPOC is excluded.

All cooperating writers/readers/maintenance must retain the same lock inode, with no replacement/unlink/alias while operations may be active. The final checks detect observed path changes during admission, not every race from arbitrary noncooperating actors. No event schema, SDK type, epoch, replay or power-loss guarantee is added.

## Verification

The source guard reverses only the directory/lock admission block and hashes the entire file against `7569c26d`; earlier C03o/n full-file reversals remain. Require root type checking, nonfollowing/nonblocking open, regular single-link descriptor, post-flock device/inode validation, unlock/close on mismatch and descriptor permission calls after validation. This keeps journal validation, event success fields, poll/status/cache and transport logic frozen.

The actual-source macOS fixture tracks every opened lock descriptor and permission call, with real open/fstat/flock/close and a private root override. Cases cover normal shared/exclusive and blocking/nonblocking admissions on the same inode; initial fstat failure; symlink/FIFO/directory/hardlink lock refusal; known symlink/file roots; unchanged target data/modes; and missing-root bootstrap. Refusals must produce existing publisher/status/loader errors without journal reads/writes/hints or lock permission calls, with zero live descriptors.

A post-flock hook performs real pathname replacement, removal-by-rename, added hardlink and root rename/symlink changes. Admission must reject, release the old inode and preserve the replacement mode. Restoration must retain the original inode and allow publishing again. The full event runtime must finish with no live lock descriptors. The runner instruments every unlock occurrence, including the new rejection branch; other B06/C03n/o integration cases remain. No real device/system paths are touched.

All 65 workflow runners (36 source-contract, 29 native), 521 direct source-grep assertions, expanded standards-conforming assert preprocessing including the updated event fixture, focused event source/core/contracts and git diff --check pass on Windows. Sixteen artifact-only checks require CI outputs. New Foundation/POSIX/ARC/ASan/UBSan execution requires macOS CI. Device filesystem, stop/restart, maintenance and contention/latency/RSS qualification remain separate.

## Remaining work

Measure added metadata checks and actual lock hold/admission costs; no device performance improvement is claimed. Full-journal read/parse/rewrite cost, predecode byte limits, missing-file epoch/reconstruction, failed-event replay, fsync/power-loss durability and other C03/outstanding work remain open. Cooperating maintenance must follow the same inode protocol, and older actors accepting unsafe path states cannot provide this admission guarantee. Full P1-58 closure is not claimed.
