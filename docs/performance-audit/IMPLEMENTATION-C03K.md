# C03k — coordinate pending history recovery on the held lock inode

Date: 2026-10-29 (Asia/Bangkok). Baseline: `0c5de74d` (C03j), build passed according to the user.
Status: **build passed according to the user before C03l; independent device qualification pending**.
The passed C03k working-tree source was not separately committed: normalized complete `shared/TLinkRunHistory.mm` SHA-256 is `b9f1354a2fa793ae8bf56f68907621c3309c8973941fa8d33ec3da55e67b5129`.
Finding: **P1-53 process-crash and cross-owner retained-metadata coherence**. Power-loss/index/orphan/event recovery remains open.

## Protocol

The existing held history.lock inode is also an intent marker: length 0 clean, length 1 pending. Under the same monitor/flock, read and validate it after the checked index read. Pending resets the local completion gate even in an already-warm owner. Before cold/local repair of a clean inode, set pending so failed partial recovery remains visible to another owner. Reuse C03i's unchanged bounded repair implementation. Before new mutation artifact writes set pending; only a positive required index write permits clearing it. No new file, JSON journal, counter rollover, timer or notification is introduced.

A writer can exit before or after index replacement without running its error handler; the next owner sees pending and uses the index actually present as authority. A reported NO/NS/C++ writer error also leaves pending. The failed operation/event is not replayed. A failed repair leaves pending and blocks the new mutation. A successful repair alone does not clear pending: its enclosing mutation must commit successfully first.

Marker probe/dirty-write failure returns empty with no new mutation artifact writes or event. After index ACK, marker-clear failure preserves committed success and its event, invalidates the local gate and records a diagnostic. If pending remains, the next owner rechecks; if clear actually occurred before its error, all required metadata/index writes were already acknowledged. Post-commit pruning remains best effort and follows marker cleanup. Partial repairs before a later failure remain authoritative, not rolled back.

## Scope and bounds

Use fstat/ftruncate on the held descriptor; retry EINTR for idempotent length changes. Require a regular singly-linked inode of length 0/1 and a direct root directory before truncation. Acquire rejects leaf symlinks and uses nonblocking file open to avoid special-file stalls; flock itself retains its existing blocking policy. Cooperating writers/maintenance must never unlink or replace the inode. No guarantee against arbitrary filesystem races outside this protocol is added.

All writers must use the new protocol. An older writer that ignores pending cannot provide this coordination guarantee. Existing empty lock files remain compatible; unknown lengths fail closed without reset. Clean normal mutations add constant root/lock metadata checks and two length changes on the existing descriptor, retaining the no-full-scan fast path. Cold/error paths may also mark before repair. Device first/steady-state latency and RSS remain unmeasured.

Diagnostics preserve their shape and fixed labels: recovery_marker/intent/commit_marker stages with history_marker_read_failed/history_marker_invalid/history_marker_write_failed codes. No path/content/exception text is added. Snapshot does not repair or clear pending. JSON schemas, API/event payloads, index authority, SDK types, caller best-effort script lifecycle and C03g-j logical ACK rules remain. Shared rootfull/roothide and production TrollStore source is covered; TouchPOC is excluded.

## Verification

The source guard removes only marker helpers/calls and the hardened lock-open flags, then hashes the complete source against C03j at 0c5de74d. Earlier complete frozen/hash comparisons remain. Guards require intent before artifact writes and clear after index ACK. Actual production source is compiled in the macOS fixture, with controlled marker syscalls and real temporary files/flock/processes.

Six coordinated cases keep a peer executable warm over a socket barrier while another owner fails: NO before index replacement, NO/NS/C++ after replacement, and real writer exit before/after replacement. The warm peer must notice pending without a local flag reset, restore retained JSON from old/new index authority, publish only its own events, clear pending without replacing the inode and skip recovery on its subsequent clean update. Parent and worker descriptor/lock ownership is balanced; no timing sleeps are used.

Marker tests cover pre/post-effect dirty/clear EIO, committed ACK on clear failure, EINTR retry, failed probe, unknown size, hardlink/symlink/FIFO rejection, no payload writes on admission failure and retry. Existing writer/recovery tests remain. The preflight preservation comparison now excludes only the intentionally modified lock marker and separately requires pending; indexed JSON/artifacts remain unchanged. New Foundation/POSIX/ARC/ASan/UBSan execution remains pending CI.

All 65 workflow runners (36 source-contract, 29 native), 521 direct source-grep assertions, expanded standards-conforming assert preprocessing, focused history guards/contracts and git diff --check pass on Windows. Sixteen artifact-only checks require CI outputs. New Foundation/POSIX/ARC/ASan/UBSan execution of the process/marker cases is not available on Windows and remains pending macOS CI; device qualification is separate. No SDK or unrelated TypeScript changes were made.

## Remaining work

No fsync or power-loss ordering/durability is claimed. Qualify the protocol with all device writers upgraded, real stop/restart/disk-full/permissions and latency/RSS measurements on rootfull/roothide and TrollStore. Missing/corrupt index reconstruction, arbitrary external artifact damage, orphan ownership/retention, screenshot availability, event-journal delivery/replay and other C03/outstanding C02 work remain open. Full P1-53 closure is not claimed.
