# C03i — recover retained history metadata on the first mutation per process

Date: 2026-10-29 (Asia/Bangkok). Baseline: `c8d2d085` (C03h), build passed according to the user.
Status: **build passed according to the user (`7f212b05`); device qualification pending**.
Follow-up: C03j re-enables the same recovery pass after required mutation write failures in a running process. The behavior/verification below records C03i's original scope.
Finding: **P1-53 retained record/evidence coherence after restart**. Full crash/durability/orphan/event recovery remains open.

## Result and trigger

The first begin/finish mutation in a process now reconciles metadata retained by the authoritative index before writing the new mutation. It uses C03h's checked index reader and the existing local monitor/flock. Validate the whole bounded repair set before touching any artifact. For each run, repair embedded evidence JSON first when present, then the record JSON, from the complete dictionaries already stored in the index. No index write, timestamp/state change, console/screenshot read, artifact deletion or event publication occurs in the recovery pass itself.

An interrupted/failed finish can leave evidence and a terminal record ahead of an unchanged running index entry; recovery restores that indexed running record. If an index replacement committed before a reported failure, recovery uses the new indexed record instead. It does not invent a terminal state or infer authority from a loose record/evidence file. Missing metadata is recreated; malformed/mismatching metadata is replaced. Existing equal JSON is retained. Separate atomic writes remain individually atomic, with no fsync or multi-file atomicity claim.

Only after the complete pass succeeds set the process-local completion flag. Later begin/finish calls skip the artifact scan, avoiding a 50-run scan on every script update. A recovery read/write/exception failure leaves the flag unset, blocks the new mutation and permits the next call to recheck/retry. Repairs already completed before a later failure remain valid indexed metadata and are not rolled back. Ordinary mutation failures after a successful pass do not reset this flag; continuous repair in a running process is separate work. This is a lazy first-mutation trigger, not eager daemon startup or status-triggered maintenance.

## Bounds, ownership and errors

Preflight at most 50 entries, each with the existing run schema, its exact sanitized per-ID record path and a dictionary failure_evidence. Nonempty evidence must match the evidence schema, run identity and exact per-ID metadata path. Reject distinct IDs that sanitize to the same filename. Reject a direct root/runs/evidence directory that is a symlink or not a directory. Open existing leaves with O_RDONLY/O_NONBLOCK/O_NOFOLLOW, require a regular file via fstat and close in finally on all paths. This coordinates cooperating history writers under flock; it is not a new guarantee against arbitrary concurrent filesystem mutation outside that protocol.

Serialize the authoritative object to determine the comparison bound. If the existing file size differs, rewrite without reading its full length. Otherwise read no more than that encoded length in chunks up to 64 KiB, handle partial reads/EINTR, decode and compare JSON. A mismatching large file therefore cannot force an arbitrary full-file read/parse. Per-record autorelease pools release comparison scratch before the next run; index/authoritative payload sizes retain their existing bounds/limitations. The existing writer handles atomic JSON replacement and permissions.

Diagnostics retain the C03g shape: operation begin/finish, stage recovery, fixed codes recovery_invalid_index/recovery_read_failed/recovery_write_failed or the existing exception label. No path/content/exception text is added. Failed recovery emits no mutation event and returns empty; existing script callers remain best effort. Successful API/status/record/evidence/event fields and the SDK type remain unchanged. Shared rootfull/roothide and production TrollStore source is covered; TouchPOC is excluded.

## Verification

The source guard projects out only the recovery helpers/flag/two gates and errno include, then hashes the complete result against C03h at c8d2d085. Earlier complete frozen inverse comparisons remain. The macOS fixture compiles the actual production source; syscall adapters record bounds/descriptor ownership and inject faults, while real temporary JSON files, flock and process creation remain in use.

New coverage launches a fresh executable process through the public begin entry. Setup uses actual failed finish/index writes and uncertain post-replacement failure, missing/corrupt committed evidence/records, an unreferenced metadata file and a screenshot outside the history root. The child must make exactly four repairs plus its own record/index writes, publish only its own mutation event and skip recovery on its next public finish. The parent verifies indexed records/evidence restored, old/new index authority respected, and orphan/screenshot bytes unchanged.

Further cases cover both public entries with NO/NS/C++/post-write failures in record/evidence repairs and retry; read EIO/EOF/NS/C++ faults, open/stat failures, EINTR/short reads, equal-JSON no-rewrite, 8-MiB mismatching and same-size malformed files, leaf symlink/directory/FIFO rejection, parent directory symlink rejection, invalid schema/destination/evidence identity and sanitized aliases/51-entry sets. Preflight failures must precede artifact opens/writes, even with a damaged first file. All failures require unchanged index/no mutation event, bounded diagnostics and no retained descriptor/flock. Existing successful frozen comparisons and C03g/h faults remain.

All 65 workflow runners (36 source-contract, 29 native), 521 direct source-grep assertions, expanded standards-conforming assert preprocessing, focused history guards/contracts and git diff --check pass on Windows. Sixteen artifact-only checks require CI outputs. Windows does not execute the new Foundation/POSIX/ARC/ASan/UBSan branches; their process/fault matrix and real device qualification remain pending macOS CI. No SDK or unrelated TypeScript changes were made.

## Remaining work

Qualify on rootfull/roothide and TrollStore devices, including real disk-full/permissions/stop/restart/power-loss behavior and first-mutation latency/RSS. Missing/corrupt index reconstruction, continuous repair after later write failures, orphan ownership/retention, screenshot availability, event-journal delivery and remaining C03/outstanding C02 work remain open. No complete P1-53 closure or device improvement percentage is claimed.
