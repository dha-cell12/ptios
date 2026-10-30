# C03v — validated history directories and stable lock inode

Date: 2026-10-30 (Asia/Bangkok). Baseline: `d4f8fa95`, C03u build passed according to the user. Complete normalized `shared/TLinkRunHistory.mm` SHA-256: `efd86cd685eb6b9179fc4f5c949e6836bd9cb070917aa3b5b58d183fc9db1f66`.
Status: **source implemented; new Foundation/POSIX/ARC/ASan/UBSan cases pending macOS CI; independent device qualification pending**.
Finding: **P1-53 cooperative lock/marker authority**.

## Change

The pending-marker protocol depended on a stable history.lock inode, but admission did not compare its pathname after flock and applied permissions by pathname. Directory preparation could also follow direct symlinks before later recovery checks. Validate root/runs/evidence with lstat in parent-first order, create only missing paths and recheck type. Apply existing directory permissions only after all three direct paths are real directories. A newly created private directory can remain if a later preflight fails.

Validate the directory set before opening the lock. Keep existing NOFOLLOW/NONBLOCK open and blocking LOCK_EX. Require a regular single-link descriptor before flock; afterward require a matching regular/single-link pathname device/inode and valid direct directories. On refusal release any acquired flock and close without index/marker/artifact/recovery work. Set lock permissions only afterward through fchmod/fchown on the descriptor, retaining the existing best-effort failure policy.

Use existing mutation lock/history_lock_failed and snapshot history_snapshot_lock_failed outcomes. Admission failure preserves the recovery gate and emits no event. Marker length checking remains later in mutation recovery, so read-only status still supports a regular single-link lock with invalid marker length. No schema, status field, commit, repair, pruning, index IO or SDK changes. Shared rootfull/roothide and production TrollStore are covered; TouchPOC excluded.

## Verification

Reverse only directory preparation/validation and lock admission, then hash the entire history source against the user-passed C03u baseline. Retain every earlier full-source bounded-index/status/commit/recovery comparison. Guards require regular/single-link preflight, post-flock pathname identity, refusal unlock/close and descriptor permissions after validation.

The actual-source Foundation/POSIX fixture tracks lock descriptors and permission calls. Cover 128 stable-inode admissions, open/stat failures, lock symlink/dangling/FIFO/directory/hardlink refusals, and root/runs/evidence replaced by file/symlink/FIFO. Require zero index reads/writes/events, no early descriptor permissions, no permission calls for invalid direct directories, unchanged target bytes/modes and recovery/marker state, and balanced handles.

Eighteen real filesystem cases replace/remove the lock, add a hardlink or replace each direct directory by a symlink immediately after flock across begin/finish/status. Require refusal before index IO, restored bytes/lock availability and subsequent bootstrap/normal ACK. Permission syscalls are controlled as in the existing fixture; real filesystem paths, descriptors and flock are used.

Update only intentional earlier failure-phase expectations: hardlinks and directory symlinks now report admission failure before marker/recovery checks. The existing retirement-parent-symlink test acquires a valid lock before replacing the parent, preserving its independent post-admission pruning guard. All other writer/recovery/status/byte-cap cases remain.

Windows validation passed: all 65 workflow runners, 521 source checks, focused full-source/history guards/contracts, existing eleven SDK-method cases, expanded assert preprocessing and `git diff --check`; sixteen artifact-only checks skipped. New Foundation/POSIX/ARC/sanitizer execution requires macOS CI; device qualification remains separate.

## Remaining work

All cooperating actors/maintenance must keep one stable lock inode; older binaries cannot supply these checks. This validates admission points, not arbitrary post-check races or ancestor directory pinning. It adds metadata operations and claims no measured performance improvement, fsync or power-loss guarantee. Index/orphan/event recovery, log retention, status caching and other C03/device work remain open.
