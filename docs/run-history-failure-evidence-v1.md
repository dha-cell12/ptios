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
skip the artifact scan. Ordinary later write failures do not reset that gate;
continuous repair after such failures remains future work. Status does not run
recovery, and missing/corrupt index reconstruction, screenshot restoration,
orphan retention, event replay and power-loss durability remain outside this pass.

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
