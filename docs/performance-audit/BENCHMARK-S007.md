# S007 Benchmark Plan — Scheduler / Run History / Persistence

## Probe A — Timer lifecycle race / ghost timers

Stress one timer name from 8 concurrent clients with:
- set -> remove,
- set A -> set B,
- set -> remove -> set,
- remove while timer callback is firing.

Add profiling-build aggregate counters:
- timer_create_count
- timer_cancel_count
- timer_fire_count
- stale_generation_fire_count
- active_timer_count
- timer_registry_mutation_count

Tag each set with a generation. After remove acknowledgment, assert zero later fires from that generation. After replacement, assert only the newest generation fires.

Compare:
A. current caller-thread dictionary + async main creation,
B. one serialized owner queue/main lifecycle,
C. serialized dispatch-source timer implementation.

---

## Probe B — Repeating interval CPU/wakeup floor

Use intervals:
- 1 ms
- 10 ms
- 100 ms
- 1 s

Run each for 60 seconds in two states:
1. no script running,
2. long script already running so timer launch attempts are rejected.

Measure:
- main-thread CPU
- process CPU
- wakeups/s
- timer fires/s
- license checks/s
- playScript calls/s
- script_play_settings.plist reads/s
- NSLog/logd activity
- UI hitch/frame duration if SpringBoard UI is active

Then test candidate minimum interval + timer leeway/coalescing.

Acceptance:
- configured low interval cannot create unbounded main-thread work,
- busy-session rejection happens before disk/config parsing,
- no polling/busy wait is introduced.

---

## Probe C — Run-history index amplification

Seed history with:
- 0 runs
- 10 successful runs
- 50 successful runs
- 50 failed runs with 50 × 1000-character log-tail lines

For begin and finish separately record:
- index.json bytes read
- JSON parse time
- record JSON bytes written
- evidence JSON bytes written
- index JSON bytes written
- total atomic-write bytes
- allocations
- total latency p50/p95/p99

A/B:
A. current full evidence embedded in index,
B. compact metadata-only index + per-run evidence file.

Also compare pretty JSON vs compact JSON for machine-only state.

---

## Probe D — History lock hold time

For a failed run with a 256 KiB console log:
- timestamp history flock acquire/release,
- timestamp console-tail read,
- regex redaction,
- evidence JSON generation,
- record/index writes.

Count regex compilation instances.

Compare:
A. current evidence preprocessing under flock,
B. static compiled regex + bounded log preprocessing before acquiring history lock.

Acceptance:
- history flock covers only transaction-critical read/modify/write work,
- no console-log file I/O occurs while history flock is held.

---

## Probe E — Concurrent history writers/readers

Run rootfull and another test process against the shared history files:
- 10 begin/finish operations/s,
- TASK_HELLO_STATUS snapshots at 1/5/10 Hz,
- injected failed runs with evidence.

Measure:
- flock wait p50/p95/p99/max
- snapshot latency
- begin/finish latency
- transaction failure count
- orphan record/evidence files
- index consistency

Verify persistence write failures are surfaced and event publication occurs only after committed history mutation.

---

## Probe F — Status polling persistence cost

Call TASK_HELLO_STATUS at:
- 1 Hz
- 5 Hz
- 10 Hz

With empty and worst-case retained history/event journal.

Measure:
- index.json opens/reads/s
- journal.json opens/reads/s
- JSON parse CPU
- bytes read/s
- task latency p50/p95/p99
- CPU and wakeups

Compare with immutable in-memory diagnostic snapshots updated by history/event mutations.

Acceptance: steady-state status polling should not require synchronous persistence reads when generation has not changed.

---

## Probe G — Event publication cost from run history

Seed event-channel journal at:
- 0
- 64
- 256 events

Measure one run-history start and finish:
- journal read bytes
- payload serialization bytes/time
- journal serialization/write bytes/time
- total TLinkEventChannelPublish latency

This probe is limited to the run-history publish edge. Full event-channel long-poll audit is deferred to S008.

---

## Probe H — JS run-log retention

For one script bundle, execute:
- 100 runs
- 1,000 runs
- 10,000 short runs

Generate small and near-rotation-size logs.

Capture:
- _logs file count
- total bytes
- directory enumeration latency
- cleanup latency
- history records retained
- whether any active/current log is deleted incorrectly

Compare retention policies:
- max N completed run logs,
- max total bytes,
- combined N + byte budget.

Keep latest.log/latest-helper.log separate from immutable completed-run logs.

---

## Probe I — Auto-launch transaction race

From 2/8/32 concurrent clients, write distinct auto-launch names using the current read-modify-write API.

After each batch verify:
- all acknowledged keys exist,
- values match the latest acknowledged write,
- plist remains parseable.

A/B current unlocked plist transaction vs serialized + cross-process lock/generation.

---

## Probe J — Restart semantics

On a test device:
1. create repeating and one-shot timers,
2. create enabled auto-launch entries,
3. restart SpringBoard/tweak,
4. observe restored timers and startup script launches.

Current source expectation:
- in-memory timers disappear,
- no pccontrol autolaunch consumer was found.

Do not label missing restore as a bug until product contract confirms persistence is required.

---

## Probe K — Wall-clock adjustment

Start a long script, then in controlled test conditions simulate/perform:
- forward clock jump,
- backward clock jump.

Compare history:
- started_at_ms
- ended_at_ms
- duration_ms

Prototype monotonic duration with wall timestamps retained for display.

### Suggested aggregate diagnostics

- scheduler_timer_count
- scheduler_timer_fire_count
- scheduler_stale_generation_fire_count
- scheduler_busy_launch_reject_count
- scheduler_min_interval_reject_count
- history_index_read_bytes
- history_index_write_bytes
- history_lock_wait_us / hold_us
- history_write_failure_count
- history_orphan_cleanup_count
- status_snapshot_cache_hit_count
- run_log_file_count / bytes
- autolaunch_revision
- autolaunch_write_conflict_count

Do not emit per-fire production logs.
