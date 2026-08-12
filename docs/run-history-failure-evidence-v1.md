# Run History & Failure Evidence v1

Status: implemented for rootfull and TrollStore; device promotion pending.

Every accepted script run receives a UUID `run_id` and is written under
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
