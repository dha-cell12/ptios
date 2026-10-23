# C01d3 — bounded recovery of abandoned screenshot leases

Date: 2026-10-23 (Asia/Bangkok). Baseline: `9396ef2`; the user reported the C01d2c build passed before this slice.
Status: **source implemented; new macOS/iOS CI and device qualification pending**.

## Problem and scope

C01d2a cleaned temporary screenshots on normal completion, timeout and stack unwinding, but process termination could leave its marker/PNG behind. A zero-byte marker alone did not prove that the daemon or a late SpringBoard callback was inactive. Deleting all UUID-shaped filenames or relying on a PID/age test would not protect a still-running capture or matcher.

This slice adds a versioned ownership sidecar and held descriptor locks to rootfull/roothide task-21 captures, plus a bounded recovery pass. Production TrollStore capture and TouchPOC are unchanged. The existing private CF channel, task replies, deadlines, engine limits and 2/14 daemon admission limits remain in place.

## Ownership record and active holders

For `/tmp/tlinkautod_capture_<UUID>.png`, the existing zero-byte `.lease` marker remains the cancellation signal. New clients also exclusively create `.lease.owner.v1` and acquire a nonblocking shared `flock` before publishing a usable lease. The sidecar records exactly 24 bytes:

```text
TLCP0001 | marker device, uint64 big endian | marker inode, uint64 big endian
```

The sidecar is mode 0644 with no group/world write access. Its bytes are inode metadata, not image content or a secret. Read access lets SpringBoard validate and lock a daemon-owned sidecar across the root/mobile UID boundary. The marker and PNG remain mode 0600. Newly opened descriptors use close-on-exec and no-follow flags; path/device/inode are rechecked after lock acquisition.

The daemon holds its shared descriptor through capture and matching. A new receiver independently acquires a shared descriptor before capture and holds it through actual receiver work/finish. The owner lock therefore survives daemon death when a SpringBoard callback is still running. An old marker with no versioned sidecar remains accepted as a legacy lease, but has no recovery eligibility; the sweeper never guesses whether those legacy files are active.

Every new PNG receives `com.tlinkauto.capture-owner.v1` xattr containing the same 24-byte proof before payload writing starts. Task 21 checks that proof before invoking the matcher. Missing proof returns `owned_capture_proof_missing`; xattr setup failure aborts owned writing and removes that newly created output. Filesystem xattr/flock support and the cross-process permissions are now part of device qualification. Deploy matching daemon and tweak components; an older writer may create an untagged output, which the new daemon rejects and the recovery pass conservatively retains.

## Normal cancellation and final release

Cancellation still removes the matching marker first so late writes fail the existing liveness checkpoints. It removes only a proof-matching regular output, then explicitly drops its finished shared lock and attempts a nonblocking exclusive lock on its owner descriptor. If another daemon/receiver holder remains, the sidecar is retained and the caller closes only its own descriptor. An actual receiver cannot lose its ownership lock merely because its sender timed out or crashed.

The last holder can acquire exclusive ownership and retire the marker/output/sidecar after revalidating their identities. A committed output is retained while the daemon's matcher still holds its shared lock. Receiver finish becomes idempotent and cannot accept more writes after releasing its descriptor. Foreign replacements and directories are retained rather than recursively removed.

The sidecar is removed last, only after the marker and known output are gone. Thus a cleanup-process crash between unlinks leaves the proof for a subsequent pass. If a receiver UID cannot remove a daemon-owned marker, it closes its descriptor and leaves recovery evidence for the daemon rather than broadening permissions or deleting unknown objects.

## Bounded recovery pass

A background pass is requested at daemon startup and before an admitted, live task-21 capture. One atomic pending flag coalesces triggers within a process; subsequent requests are throttled for five seconds after a pass finishes. There is no periodic timer, idle scan or waiting cleanup lock. Two daemon/helper processes may request cleanup independently; exclusive flock and inode revalidation coordinate their actual file retirement.

| Per-pass policy | Limit |
|---|---|
| Directory | Flat `/tmp` only |
| Directory entries considered | At most 4,096 |
| Versioned owner candidates | At most 64 |
| Cooperative scan budget | 25 ms, checked between iterations |
| Lock operation | `LOCK_EX|LOCK_NB` |
| Owner UID | Current sweeper effective UID |
| Image data | No PNG decode or payload read; fixed-size proof/xattr only |
| Removal | Checked `unlinkat`, no recursion |

A candidate must have the exact UUID filename plus `.lease.owner.v1`, be a regular single-link file with safe permissions, and still name the descriptor that was opened. Busy shared locks are skipped. Under exclusive ownership, recovery verifies the marker's recorded inode if present, and verifies the output's type, single link, private permissions, size ceiling and matching xattr before removal. Symlinks, directories, FIFOs, hard links, changed marker generations and unknown/mismatched proof are retained.

An interrupted empty initial reservation is reclaimable only if neither marker nor output exists. Partial proof records and untagged outputs are not sufficient evidence and are retained for inspection. In particular, a crash between creating a PNG inode and attaching its xattr can leave an untagged empty file; that case is intentionally not auto-deleted. Legacy unguarded files are also retained. This is recovery of proven abandoned resources, not a general filename-based garbage collector or a promise to erase every crash artifact.

Directory and candidate descriptors are scope-owned, including exceptions. Work is outside socket/task/IPC owner queues. The 25 ms budget does not preempt opaque filesystem syscalls; no hard startup/cleanup latency is claimed. A bounded pass may miss later entries, and retained unknown candidates or a crowded directory can delay progress. If no later startup/task trigger occurs, a previously busy artifact can remain; there is no wall-clock deletion SLA. Filesystem errors, reboot/power-loss recovery and deliberate privileged namespace replacement are outside the automatic-reclamation guarantee.

## Validation

- Windows: all 36 source-contract runners, 20 native runners and 528 TrollStore workflow grep assertions pass. Expanded portable ownership tests retain the 100k write/cancel lifecycles, descriptor balance, EINTR/partial/error/close handling, deadline/token checks and replacement safety. New tests cover candidate names, exact 4,096/64 admission boundaries, 25 ms policy expiry and output ownership.
- Existing macOS Foundation/PNG fixture now checks versioned sidecar lifetime through late callback cancellation and preserves unknown replacements/directories. Its janitor scheduling boundary is controlled; it does not sweep the host's real `/tmp` during orchestration tests.
- New POSIX C++ fixture uses an isolated mkdtemp directory, actual flock/xattrs/openat/unlinkat and child process exit/SIGKILL. It checks active-client exclusion, a receiver holding its lock after daemon death, last-holder cleanup, concurrent sweep processes, legacy files, wrong/missing xattrs, symlink/directory/FIFO/hard-link protection, changed marker generations, interrupted reservations, malformed/unsafe owner records and balanced descriptors/files. Functional filesystem cases use a fixed clock so host scheduling cannot hide candidates; exact cooperative time expiry is checked by the portable policy tests.
- Both workflows run the new fixture through `check-owned-capture-safety.mjs`; the existing `test/capture-lease-*.cpp` TrollStore trigger includes it. Strict warnings, ASan and UBSan remain enabled. No production directory is recursively removed by the test.
- **The new POSIX/macOS branches and final iOS builds were not run on this Windows host.** Actual root/mobile permissions, Darwin lock upgrade behavior, xattr support, native handler accuracy, RSS/latency/energy and restart/crash timing remain device-qualified work.

## Acceptance and next group

Build both root runtimes/binaries, then kill the daemon during preparation, matching and an opaque SpringBoard callback. Verify active holders are skipped, proven tagged orphans disappear after the next eligible trigger, unknown/legacy evidence survives, and the following capture succeeds. Exercise overlapping cleanup from both binaries, restricted filesystems, fork/exec descriptor lifetime, many unrelated `/tmp` entries and capture after acknowledged touch. Record metadata/lock/xattr overhead and idle wakeups against C01d2c; do not infer a performance gain from the build result.

C01 source slices now include bounded engine/ingress/IPC and proven crash-retention recovery. C01 is not marked fully accepted without macOS/iOS/device qualification. After the C01d3 build checkpoint, the next implementation group is C02 (typed native API/helper transport); remaining device benchmark probes and conservative retention cases stay documented here.

## Following checkpoint

The user reported the C01d3 build at `f8155bc` passed before C02a. This is a build checkpoint; root/mobile permission, crash/restart timing and performance qualification remain open. The next implemented slice is `IMPLEMENTATION-C02A.md`.

## CI correction — concurrent release (2026-10-24)

The user reported `capture-lease-runtime-test.mm` failing at `client.valid()` in its repeated same-path lifecycle test. The previous iteration checked only PNG/marker removal and could leave `.lease.owner.v1` behind. Two concurrent finishers could both fail their EX/NB upgrade while retaining SH, then both close without retiring the sidecar. XNU's nonblocking conflict path returns before its shared-lock removal path; see [Apple's lock implementation](https://github.com/apple-oss-distributions/xnu/blob/main/bsd/kern/kern_lockf.c).

`releaseMarker` now explicitly unlocks after all caller work is complete, then tries EX/NB. Existing readers still prevent cleanup; a winning sweeper or changed owner entry remains protected by proof/inode revalidation. Unlock failure closes the descriptor and defers recovery. No waiting, spin/retry, force unlink or relaxed ownership rule is added.

A new portable harness compiles the actual production release body against a deterministic retained-SH lock model. It checks concurrent finishers, one exclusive cleaner, a third active reader, proof mismatch, unlock failure and balanced closes. A negative probe of the previous production body deterministically leaves the sidecar; the corrected body passes. All 36 source-contract runners, the 100k lease runner, C01 ingress and socket transport runners also pass on Windows. The Foundation lifecycle now checks the sidecar before same-path reuse, and the isolated POSIX fixture adds 256 paired concurrent releases with all files gone after join. Those actual Darwin/Foundation branches were not run on this Windows host and await corrected CI.
