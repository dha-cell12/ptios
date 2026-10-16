# S002 Benchmark Probes

Goal: validate P0-01 (recording callback cost/timing) and P0-02 (per-line license overhead) without committing to a large refactor.

## Rule: do not signpost every production event by default

Per-event `os_signpost` can itself perturb a high-rate touch path. Prefer cheap aggregate counters for the baseline build, and only enable sampled/per-event signposts in a dedicated profiling build.

---

## Probe A — Recording callback aggregate counters

Target: `pccontrol/Record.xm::recordIOHIDEventCallback`

Collect per recording session:

- digitizer parent callback count
- child event count
- accepted recorded event count (down/move/up)
- total bytes submitted to `writeData:`
- write call count
- callback total/max nanoseconds
- formatting+encoding total/max nanoseconds
- writeData total/max nanoseconds
- gap between event timestamp/callback start and write completion if event timestamp conversion is validated

Recommended measurement clock: `mach_continuous_time()` or `mach_absolute_time()` with one cached `mach_timebase_info`.

Use atomics only where snapshotting crosses threads. The callback itself is single-owner today, so avoid unnecessary contention inside the callback.

### Minimal profiling-only structure

```objc
typedef struct {
    _Atomic uint64_t parentCallbacks;
    _Atomic uint64_t childEvents;
    _Atomic uint64_t recordedEvents;
    _Atomic uint64_t writeCalls;
    _Atomic uint64_t bytesWritten;
    _Atomic uint64_t callbackTotalNs;
    _Atomic uint64_t callbackMaxNs;
    _Atomic uint64_t writeTotalNs;
    _Atomic uint64_t writeMaxNs;
} TLinkRecordPerf;
```

Do not allocate NSDictionary/NSNumber objects per event. Convert counters to Objective-C only when exporting a session summary.

### Required tests

1. 1 minute normal touch
2. 10 minutes
3. 100k synthetic/injected events
4. repeat on slow-storage / device-under-load condition

Report p50/p95/p99 callback latency using sampled signposts or an offline histogram if needed. Aggregate total/max alone is not enough for final tuning.

---

## Probe B — Recording timing fidelity

Current source computes delay before write but advances the baseline after write. Test the timing error directly.

For each recorded event in a profiling build capture:

- HID event timestamp (if confirmed monotonic/mach units)
- callback-start timestamp
- write-start timestamp
- write-end timestamp
- stored delay

Compare:

`stored_delay` vs `event_timestamp[n] - event_timestamp[n-1]`

and separately:

`write_end - write_start`

If HID timestamp units/behavior are uncertain on the target iOS build, mark that comparison **INSUFFICIENT DATA** and first compare against callback-start deltas.

Expected signature of current bug: as write duration increases, stored inter-event delay is biased downward because the previous baseline is moved after the write.

---

## Probe C — RAW playback license overhead using existing diagnostics

No new instrumentation is required for the first measurement.

Existing `TLinkLicensePerformanceDictionary()` exports:

- `feature_check_count`
- `cache_hit_count`
- `cache_miss_count`
- `generation_poll_count`
- `feature_check_average_us`
- `feature_check_max_us`
- `status_refresh_average_ms`
- `status_refresh_max_ms`

SpringBoard status task `TASK_HELLO_STATUS = 60` already embeds this dictionary as `verifier_performance`.

### Measurement procedure

1. Query task 60 immediately before playback and save `verifier_performance`.
2. Play a known RAW trace.
3. Query task 60 immediately after.
4. Diff all counters.
5. Repeat for:
   - 10k recorded events, 1x
   - 100k recorded events, 1x
   - 10k events, accelerated
   - 100k events, accelerated
6. Run the same trace after introducing a trusted-session fast path.

For a trace produced by current recorder, expect approximately two task dispatches per recorded event (sleep + touch), so feature-check growth should be of the same order. Exact count may include heartbeat/other runtime activity; use before/after deltas.

---

## Probe D — Playback timing/jitter

Instrument the RAW playback worker, not the external socket path.

For each recorded sleep/touch pair in a profiling build:

- accumulate requested sleep microseconds
- capture actual monotonic injection timestamp
- compute deadline error relative to an absolute session timeline

Report:

- total requested duration
- actual total duration
- drift at 1 min / 10 min / 1 hour
- per-event error p50/p95/p99/max
- CPU time
- wakeups

This is the benchmark that should decide between:
- direct absolute `mach_wait_until` scheduling,
- dispatch source timer for coarse/long waits,
- hybrid strategy if needed.

Do not use busy waiting.

---

## Probe E — Touch child leak validation

Run the same single-finger sequence for 10k and 100k frames.

Before fix and after fix compare:

- Allocations live object count
- resident memory
- VM Tracker
- Leaks
- number of created child IOHID events (profiling counter)
- number of matching `CFRelease(child)` operations (profiling counter)

Expected after fix: live memory should no longer grow linearly with injected frame count.

---

## Instruments matrix

| Scenario | Primary tool | Secondary |
|---|---|---|
| Idle 10 min | Energy Log / Time Profiler | System Trace wakeups |
| Recording 1/10/60 min | Time Profiler | Allocations, File Activity |
| 10k/100k recording | Allocations | File Activity, signpost/counters |
| RAW playback 10k/100k | Time Profiler | System Trace, counters |
| Touch leak | Allocations + Leaks | VM Tracker |
| Playback jitter | System Trace + custom timestamps | Time Profiler |
| Indicator active drag | Time Profiler main thread | Core Animation / signpost |

## Acceptance targets for first optimization pass

These are engineering targets, not claims about current measurements:

- Idle: no periodic high-frequency timers/polling; CPU statistically near baseline SpringBoard noise.
- Recording: no synchronous disk write per event.
- Recording: no Foundation string/data allocation required per touch event in the final hot path.
- RAW playback: license feature checks should scale with session/heartbeat, not line count.
- Injection: no linear retained-object growth with frame count.
- Indicator: main-queue work should be coalesced so queued work does not grow with input event rate.
