# C03c — coalesced console disk writes with line-boundary rotation

Date: 2026-10-29 (Asia/Bangkok). Baseline: `cf7ed56d` (C03b); user reported that build passed.
Status: **user reported build `be66e2cf` passed before C03d; independent device/performance qualification pending**.
Finding: **P1-42 disk-write batching slice**. C03 remains partial.

## Result and scope

The rootfull/roothide in-process logger publishes admitted entries into a state-lock-protected queue. One serial GCD drain takes all available entries, writes that batch, then takes any newly available entries. There is no coalescing timer or added wait to fill a batch. The same lock handles publication, closing admission and retiring the scheduled drain, so finish's existing synchronous queue barrier still follows every accepted write. Run-generation rejection and closed-admission behavior remain from C03b.

The shared runtime-lifetime admission budget still covers at most 64 formatting, pending and executing entries, with at most 1 MiB of admitted encoded payload. Both files share each immutable encoded line. The writer concatenates only one rotation-safe group for one path at a time: up to an additional 1 MiB of logical scratch payload, released before the next group/path. This extra allocation is outside pendingBytesReserved. Foundation capacities, object metadata, input/formatter memory and system logging are not process RSS guarantees. Retire each batch entry before releasing its admission slot.

For a held 64-line burst below the rotation limit, the new macOS fixture requires two open/write/close sequences total (one per file), versus 128 for the frozen writer, and four explicit metadata reads versus 128. These are deterministic fixture operation counts awaiting macOS execution, not device performance measurements. Sparse entries can form one-line batches; no reduction ratio is promised for arbitrary workloads. Production helper/TrollStore loggers and TouchPOC are unchanged. Both workflows already run the extended shared console-log check.

## Rotation, ordering and failures

Keep the existing single-group file writer unchanged. Plan groups independently for runId.log and latest.log using each file's current size. Include the complete line that makes a file exceed 512 KiB; rotate before the following line, as in the frozen per-line implementation. A file already above the limit takes the original one-line rotation path before replanning. This also retains the old behavior when removal fails. Missing files use the original atomic-write path. Ordinary formatted bytes, CR/Unicode handling, per-file entry order, threshold equality and final file contents match the frozen writer when I/O succeeds.

Readers may now observe several complete lines together. All groups for the run path are attempted before the latest path; no cross-file per-line interleaving or atomic two-file acknowledgment is promised. Files remain runtime-owned outputs: concurrent external edits/replacement during a group are not synchronized. Group planning and the retained writer each sample metadata; no descriptor is cached between groups/runs.

An NS/C++ exception or false write result marks every entry in that affected group as a write failure. The two paths are attempted independently and their failure masks are combined so each entry increments writeFailures at most once. This count is conservative when a write/close reports failure after some or all bytes reached the file. Never retry the failed group; advance to later groups, retaining best-effort logs without replaying possibly committed bytes. Existing summary-footer writes remain best effort outside accepted-entry accounting. Reservations are retired in finally on success and failure.

Synchronous per-call NSLog, JavaScript formatting, retention, fsync/durability and potentially blocking disk I/O/drain behavior remain unchanged. No license/task/protocol/history schema or script result changes are introduced.

## Verification

Focused portable/source checks pass on Windows. The rotation planner matches 100,000 independent per-line oracle cases, including exact thresholds, multiple rotations, 64-bit failure masks and saturation arithmetic. Existing 100,000 budget/prefix cases, 8 x 10,000 concurrent admissions and zero-charge assertions remain enabled.

The extended macOS fixture uses the actual queue/planner/formatter/file writer, real private temporary files and frozen legacy methods. It checks exact bytes, held-burst operation counts, independent path sizes, multibyte multi-rotation bursts, either/both files missing, failed removal, post-write close errors, before-write C++ faults and latest-only NS faults. It retains pressure caps, old formatter/next-run isolation, concurrent producers, snapshots and handle/charge balance. Warnings, ARC, ASan and UBSan remain enabled. Foundation/GCD/macOS execution and device qualification are pending.

All 64 workflow runners (36 source-contract, 28 native) have passed on Windows: the full sweep passed 63 and H264's assertions passed but its cleanup hit a transient Windows exe-unlink EPERM; the focused H264 rerun passed including cleanup. Focused console-log and history checks, all 521 direct workflow source-grep assertions, expanded standards-conforming assert preprocessing and git diff --check pass. Sixteen artifact-only checks require CI outputs. macOS-only branches are not executed on this Windows host.

## Remaining work

Qualify burst/sparse/slow-storage logging on rootfull/roothide devices, check partial-write/rotation recovery and compare CPU, I/O, retained payload and RSS separately. P1-42 still includes synchronous NSLog; other C03 persistence/history/retention/status/commit/recovery work and outstanding C02 qualification remain open. No device CPU/latency/RSS improvement is claimed.
