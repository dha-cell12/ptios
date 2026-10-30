# Run History & Failure Evidence v1

Status: implemented for rootfull and TrollStore; device promotion pending.

Every successfully persisted history begin receives a UUID `run_id` under
`/var/mobile/Library/TLinkauto/run-history`. Task `60` includes the newest 20
runs in `run_history`; task `97` publishes the capability contract. Existing
task `19/20/60` response shapes remain compatible.

## Contract

History records use `run_history_v1` and include runtime, script bundle/entry,
state, start/end/duration, playback settings, error and evidence references.
Terminal states are `finished`, `failed`, `cancelled`, and `license_revoked`.

Failed and license-revoked runs receive `failure_evidence_v1`:

- the final 50 bounded console/session log lines;
- the primary script error;
- a best-effort PNG screenshot;
- screenshot error details when capture is unavailable;
- paths to the durable run and evidence JSON files.

Screenshot failure never replaces the original script failure. Successful and
manually cancelled runs retain history metadata but do not collect failure
evidence.

## Retention and privacy

- Maximum 50 runs, pruned oldest first with owned metadata/screenshots.
- Rootfull and TrollStore serialize index updates with a shared `flock` file.
- Task `60` returns at most the newest 20 records.
- Task `60` includes at most 3 evidence lines of 240 characters and 500 error
  characters per run; the durable evidence JSON retains the final 50 lines of
  up to 1,000 characters and 4,000 error characters.
- Each evidence log line is capped at 1,000 characters.
- Rootfull reads no more than 256 KiB from the end of its console log.
- Directories are mode `0750`; files are mode `0640` and owned by mobile.
- Common license, pairing, VPN, private-key, admin-token, and bearer-token
  values are redacted from errors and log tails. Scripts should still avoid
  logging credentials because screenshot evidence can contain sensitive UI.

## Runtime behavior

Rootfull records raw and JavaScript runs in `ScriptPlayer`. JavaScript failures
use the existing per-run console file and SpringBoard screenshot backend.

TrollStore records its streamd JavaScript session log. On failure it asks
`CaptureCore` for a screen image; inability to capture is explicitly recorded
as `screenshot_error` while history remains valid.

The StreamControl Logs view displays recent run IDs, states, durations and
evidence paths. WebTango exposes `device.getRunHistory()`.

## Index encoding

New index writes use compact JSON, removing indentation and formatting line
breaks while retaining the same `run_history_v1` envelope, records and embedded
evidence. Record and evidence artifact JSON keeps its existing pretty format.
Consumers must parse JSON; whitespace and key ordering are not a file contract.
Both existing pretty indexes and compact indexes are accepted by the current
readers. Snapshot does not rewrite either format. A successful normal mutation
writes the index in compact form through the same checked atomic-write path;
there is no separate migration job or additional file.

This changes neither the logical index commit point nor pending-marker,
recovery, retention, event or status behavior. All cooperating writers must
still use the pending-marker protocol below. Removing whitespace reduces the
encoded index bytes; CPU time, filesystem write amplification, latency and RSS
improvements need measurement on devices. The index still embeds evidence and
is still fully encoded/rewritten on each mutation.

## Persistence failures

Begin/finish read the index under the file lock before writing evidence/record/index files.
Only a Cocoa file-not-found result starts an empty index. Unreadable files,
empty/truncated JSON, unsupported/missing schema, a non-array `runs`, non-record
entries, or missing/empty/non-string/duplicate run IDs stop the mutation. The
existing index and artifacts are preserved; no success event is published.
Valid `run_history_v1` empty indexes and extra envelope keys remain accepted.
The status reader retains its existing permissive fallback policy; this is a
mutation guard, not a complete validator for every stored record field.

Begin/finish check required evidence, record and index writes. A reported write
failure returns an empty history result and suppresses its `script.run` event;
the existing script lifecycle continues. The atomic index write is the history
commit point. Old artifacts are removed only after index-write success, while
the same file lock is still held. Cleanup is best effort.

Task `60` adds optional `run_history.persistence_diagnostics` with `scope: process`,
a saturating `failure_count`, and bounded `last_failure` fields `operation`,
`stage`, `code`, `at_ms`. Codes include `write_failed`, `exception` and
`history_lock_failed`, `read_failed` and `invalid_index`. The last two use stage
`read`; exceptions still use `exception`. No script error, log tail or credentials are copied into
these diagnostics. Counts are local to the responding process and reset on
process restart; successful operations do not clear the last failure.

Record/evidence/index files are separate atomic writes. A failed or interrupted
operation may leave partial/orphan artifacts, or an uncertain outcome after an
index replacement; this is not a crash-atomic multi-file transaction. Failed
mutations and events are not automatically replayed. The retained metadata
repair below does not replay those operations; orphan retention and event-journal
delivery remain separate work.
An invalid/unreadable index is not automatically replaced or rebuilt from loose
files. Mutations can resume after the underlying read problem is resolved or a
valid index is explicitly restored. A missing index still bootstraps empty;
orphan files do not provide an automatic reconstruction source.

## Retained metadata recovery

At the first begin/finish mutation in each process, while holding the existing
monitor and flock, validate at most 50 retained record/evidence destinations and
repair their JSON from the committed index. A failed index write can leave a
record ahead of the old index; recovery restores the old indexed record. If the
index replacement actually committed before a reported failure, recovery uses
that new index. The recovery pass itself never changes index bytes or run state.

All destinations must be exact per-ID record/evidence paths, with matching
schemas/identities and no filename aliases. Direct history directories and
artifact leaves must not be symlinks; non-regular artifact files are rejected.
For matching file sizes, read at most the authoritative JSON's encoded length
in chunks of at most 64 KiB and compare decoded JSON. Other sizes are replaced
without reading their full contents. Missing/mismatching files are atomically
rewritten with the existing JSON/permission policy. Recovery does not access
screenshot contents, remove orphans or publish events.

Recovery failure returns an empty mutation result, leaves the completion gate
unset and records stage `recovery` with `recovery_invalid_index`,
`recovery_read_failed`, `recovery_write_failed`, or `exception`. Repaired files
may already have been written before a later repair fails; the next mutation
rechecks them. After one successful pass, later mutations in the same process
skip the artifact scan. A later begin/finish failure at the evidence/record/index
write stage unsets that process's gate, even for a reported NO/NS/C++ exception
after replacement. The next mutation re-reads the current index under flock and
repairs retained metadata before doing its own work. The failed mutation/event
is not replayed. Serialization failures at those stages conservatively re-enable
recovery even when no file was written. The gate is invalidated independently of
the saturating diagnostic counter.

Lock/read/preparation failures and post-commit pruning diagnostics preserve the
local gate's current state. Status does not run recovery or clear the gate.

## Pending marker between cooperating writers

While holding `flock`, mutations inspect the same `history.lock` inode: length
0 means clean, length 1 means a pending update. A pending marker forces even an
already-warm owner to reconcile retained metadata from the latest index before
its own work. Set pending before any repair writes and before mutation writes;
clear it only after the required index write succeeds. Failed operations or a
process exiting between writes leave pending for the next owner. Repair itself
does not replay the failed operation/event, and marker cleanup waits for a
successful mutation commit.

Marker read/admission errors stop new mutation artifact writes, reporting
`recovery_marker` or `intent` with `history_marker_read_failed`,
`history_marker_invalid` or `history_marker_write_failed`. An index already
acknowledged stays successful if marker clearing reports failure: emit its
normal event, invalidate the local gate and report `commit_marker`. A remaining
pending marker causes another owner's next mutation to check metadata again.
If clearing actually completed before its error, the committed metadata is
already coherent. EINTR retries are safe for the idempotent length changes.

The lock must be regular, have one link and an understood length; opens reject
symlinks and do not block on special files. Direct-root validation precedes
truncation. Cooperating writers/maintenance must never replace or unlink this
inode, and all writers must be upgraded to this protocol. Older binaries ignore
the marker and cannot provide its failure guarantees. Clean updates add constant
marker metadata/length operations on the existing descriptor, without a new
file or normal full metadata scan. Snapshot remains read-only and does not
consume or clear pending state.

No fsync/write-ordering guarantee for power loss is added. Missing/corrupt index
reconstruction, detection of arbitrary external artifact damage, screenshot
restoration, orphan retention and event replay remain separate work.

## Retired artifact ownership and cleanup

After index acknowledgment, under the same lock, retirement may unlink only
`runs/<sanitized-run-id>.json`, `evidence/<sanitized-run-id>.json` and
`evidence/<sanitized-run-id>.png` when that exact standardized path is present
in the retired record. A path referenced by any retained record/evidence field
is protected, including aliases caused by run-ID sanitization. Empty/non-string
claims and outside-history paths are ignored. In-root claims to other leaves,
control files or directories report `prune` / `artifacts` / `path_not_owned`.
Root and immediate artifact parents must be real directories, not symlinks.

Deletion uses nonrecursive `unlink`: an owned leaf symlink itself can be removed
without following its target; directories are preserved. Missing files are
benign, EINTR is retried, other syscall failures report `remove_failed` and
continue with other artifacts. NS/C++ cleanup exceptions report `exception`
and are contained; the rest of that victim is skipped. Committed return values,
index/event state and the local recovery gate remain successful after cleanup
errors. Diagnostics contain fixed labels only, with no paths or exception text.
No retirement work is done when no records were evicted.

This is one post-commit cleanup attempt, without an orphan discovery/retry
queue, crash-resumable pruning or a disk-byte bound. Console `_logs` and
external screenshots remain outside this ownership contract. All cooperating
writers/maintenance must honor the same lock and inode protocol; no protection
against arbitrary noncooperating filesystem races is claimed. Device I/O and
latency qualification remains pending.

## Checked history status (C03t)

Snapshot uses the same checked index reader as begin/finish under the existing
history file lock. Since C03u, only POSIX open ENOENT means a valid empty first
history. Read failures, empty/invalid JSON, wrong schema/runs shape,
invalid/empty/duplicate run IDs produce an error snapshot. Lock failure performs
no index read. NS/C++ read and formatting faults are contained, and an acquired
lock is released before formatting as before.

Successful status fields and limit behavior are unchanged. Failure retains the
schema/root/limit/diagnostics fields, with `state="error"`, an `error` label,
`runs=[]`, `total_count=0` and `failed_count=0`. These counts/runs are unknown
placeholders, not confirmation of an empty history. Fixed error labels are
`history_snapshot_lock_failed`, `history_snapshot_read_failed`,
`history_snapshot_invalid_index` and `history_snapshot_exception`.

Process diagnostics record operation `snapshot`, its prepare/lock/read/format
stage and a fixed code, without index content or exception messages. Status
does not reset the mutation recovery flag, repair metadata, update the pending
marker, rewrite/prune JSON or emit events. Existing directory/lock creation and
permission setup remain. Explicit restoration followed by another status call
reads the file anew; no stale snapshot fallback or new content cache is added.

WebTango `getRunHistory()` rejects an error snapshot using its nonempty string
code (or a fixed fallback for malformed error fields), preserving the existing
task-60 request/envelope. Raw clients must inspect nested `run_history.state`
before using its counts. Types include optional `error` and diagnostic operation
`snapshot`. Index file/buffer bytes are bounded by C03u below; JSON graph/RSS,
caching, lock wait latency, durability and device qualification remain separate.

## Bounded history index IO (C03u)

The common reader opens index.json with O_RDONLY|O_NOFOLLOW|O_NONBLOCK under the
existing history lock. Require a regular file and nonnegative size, then admit
at most 32 MiB before buffer allocation or JSON parsing. Direct symlinks,
dangling links, FIFO, directories and open/stat errors return read_failed;
only open ENOENT bootstraps empty. The former NSData/NSError bootstrap test is
removed. This does not harden all ancestor/root path races or the lock protocol.

Read the admitted size in chunks of at most 64 KiB, retry EINTR and accumulate
short reads. Early EOF/EIO fail; an extra one-byte probe rejects observed growth
(index_too_large at the cap, read_failed below it). Close the private descriptor
in finally, including NS/C++ faults. Cooperating atomic writers keep the opened
inode stable; no arbitrary in-place writer consistency guarantee is added.

Oversize input reports mutation diagnostic read/index_too_large and snapshot
error history_snapshot_too_large. SDK getRunHistory rejects that fixed code.
Refusal does not modify index/artifact bytes, pending marker or recovery gate,
or emit events. Empty regular files retain invalid-index behavior; no automatic
deletion, truncation or reconstruction occurs.

Encoded index writes share the 32-MiB cap before atomic write; record/evidence
writes retain their previous policy. An oversized output uses existing index
stage/write_failed semantics. Earlier record/evidence writes may already have
committed: preserve the old index and pending marker, invalidate local recovery,
return no mutation success/event, then repair from the authoritative index on
the next mutation. No rollback or operation replay is added.

32 MiB leaves space above the fixture's roughly 17.4-MB worst escaped bounded
error/log-tail fields for fifty runs. Unbounded extensions/play settings can
still exceed it; externally oversized indexes require explicit maintenance.
Files exactly at the limit are readable/writable. This bounds file/read-buffer
and encoded-index bytes, not JSON graph/RSS, producer encoding, record/evidence
sizes, elapsed IO/lock time or durability. New Foundation/POSIX cases await CI
macOS; device qualification remains separate.

## Capability markers

```text
runHistoryState=implemented
runHistoryVersion=1
runHistorySchema=run_history_v1
failureEvidenceSchema=failure_evidence_v1
runHistoryTransport=task60_status_json_v1
runHistoryRetentionMaxRuns=50
failureEvidenceScreenshot=best_effort_png_on_failure
runHistoryDeviceValidated=0
```

## Device test

The smoke script deliberately throws `intentional_failure_evidence_smoke_v1`.
The test succeeds only when task `60` contains a matching failed run, bounded
log tail, evidence metadata path, and either a PNG screenshot or an explicit
screenshot error.
