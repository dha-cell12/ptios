# S008 Benchmark Plan — Event Channel / Task 95

## Probe A — Idle long-poll filesystem rate

Run quiet event subscriptions for 10 minutes with:
- 1 subscriber,
- 2 subscribers,
- 4 subscribers,
- 8 subscribers.

Use default timeout 20 seconds and max timeout 25 seconds.

Collect:
- TLinkEventReadBatch calls/s,
- createDirectory/chmod/lchown calls/s,
- lock-file open/flock/close calls/s,
- journal.json opens/reads/s,
- JSON parse time/s,
- daemon CPU,
- wakeups/s,
- context switches,
- energy impact,
- filesystem activity.

Source expectation:
- ~10 read cycles/s per subscriber,
- up to ~80 cycles/s at 8 subscribers.

Compare:
A. current 100 ms file polling,
B. cached in-memory journal + local condition wait,
C. B + cross-process notification/generation reload only on change.

Acceptance: a quiet subscription approaches zero periodic filesystem reads/wakeups.

---

## Probe B — Event delivery latency

Publish timestamped events while 1/8 subscribers are waiting.

Measure:
- publish start,
- journal commit,
- waiter wake,
- response enqueue,
- client receipt.

Report p50/p95/p99/max.

Current design should show polling-phase latency bounded by roughly 0–100 ms.

Compare event-driven notification path. Verify no missed event across notification coalescing because cursor replay remains journal-backed.

---

## Probe C — Disconnect cancellation / capacity recovery

For each timeout 20s and 25s:

1. Start 8 Task-95 polls.
2. Immediately close all client sockets.
3. Sample active_polls every 10 ms.
4. Attempt a ninth poll.

Collect:
- time from disconnect to active_polls=0,
- ninth-poll busy duration,
- journal reads after disconnect,
- retained write streams,
- global worker count.

Acceptance after fix:
- all abandoned polls cancel promptly,
- no journal reads continue after client cleanup,
- capacity is immediately reusable.

---

## Probe D — Global worker occupancy

With 0/1/4/8 long polls, collect:
- daemon thread count,
- libdispatch worker count,
- blocked/sleeping thread stacks,
- stack VM/RSS,
- context switches and wakeups.

A/B:
- current global queue + repeated usleep,
- event subsystem wait primitive.

Do not create one dedicated OS thread per subscriber as the optimization.

---

## Probe E — Poll/publish lock contention

Run 1/4/8 quiet subscribers while publishing:
- 1 event/s,
- 10 events/s,
- bursts of 100 events.

Collect:
- flock wait p50/p95/p99/max for poll and publish,
- publish total latency,
- poll read latency,
- event delivery latency,
- lock acquisitions/s.

Compare current exclusive reader locks with event-driven cache/generation architecture.

---

## Probe F — Journal write amplification

Seed journal to:
- 0 events,
- 64 events,
- 128 events,
- 256 events.

Payload sizes:
- 64 B,
- 1 KiB,
- near 4 KiB.

For one publish measure:
- journal bytes read,
- JSON parse allocations/time,
- JSON serialization bytes/time,
- bytes written/atomic temp-file activity,
- total publish latency.

Compare:
A. current full-journal rewrite,
B. append journal with periodic compact/checkpoint,
C. fixed/ring persistence prototype if platform-safe.

Verify crash recovery and sequence/cursor correctness before choosing format.

---

## Probe G — Run-history coupling

With journal full and 8 event subscribers active, run:
- TLinkRunHistoryBegin,
- successful TLinkRunHistoryFinish,
- failed TLinkRunHistoryFinish.

Measure:
- run-history process-lock hold time,
- event publish wait,
- total begin/finish latency.

This quantifies S007 -> S008 coupling.

---

## Probe H — Task-95 response allocation/copy

Create batches:
- 1 event,
- 16 events,
- 32 events,
with payload sizes 64 B / 1 KiB / 4 KiB.

For legacy v0 and JSON-v1 capture:
- JSON serialization bytes,
- base64 bytes,
- NSString/NSData allocations,
- legacy response parse/split cost,
- framed JSON bytes,
- peak transient allocations.

Compare JSON-v1 direct typed batch encoding against legacy-wrapper/reparse.

Acceptance: JSON-v1 does not generate and parse a legacy base64 response internally.

---

## Probe I — SocketQueue response HOL

Client A requests max-size Task-95 batch and then reads slowly/stalls.
Client B sends:
- ping,
- task 61,
- task 10 delivery,
- status.

Measure:
- zx_writeAll block duration,
- socketQueue backlog,
- client B latency,
- cleanup latency.

This extends S003 P1-16 with a realistic large Task-95 response.

---

## Probe J — Cursor/gap correctness under compaction and reset

Generate >256 events while consumers have cursors:
- current,
- 10 behind,
- 255 behind,
- 300 behind.

Verify:
- gap semantics,
- oldest_cursor/latest_cursor,
- no duplicate matching event delivery,
- has_more.

Then corrupt/truncate journal.json in a controlled test.

Current expected behavior: read falls back to empty generation without explicit corruption state.

After redesign:
- quarantine corrupted journal,
- increment reset generation/epoch,
- client receives explicit resync condition.

---

## Probe K — Topic filtering

Journal layout:
- matching event then 100 unrelated events,
- alternating matching/unrelated,
- only unrelated events.

Measure request count needed for subscriber to reach a true wait state.

Validate optimization that advances through fully scanned non-matching tail without skipping matching events.

---

## Probe L — Wall-clock shift

During a 20-second long poll, simulate controlled forward/backward wall-clock adjustments.

Record timeout duration measured by a monotonic external clock.

After fix, timeout budget must use monotonic/continuous time and remain near requested duration.

---

## Suggested aggregate diagnostics

- event_poll_active_count
- event_poll_started_count
- event_poll_cancelled_count
- event_poll_timeout_count
- event_poll_read_cycles
- event_poll_wake_count
- event_poll_journal_reload_count
- event_poll_lock_wait_us / max_us
- event_publish_count
- event_publish_lock_wait_us / max_us
- event_journal_read_bytes
- event_journal_write_bytes
- event_journal_generation
- event_journal_reset_count
- event_response_raw_bytes
- event_response_wire_bytes
- event_response_socket_write_us

Avoid per-100ms production logging.

## Acceptance criteria

- Quiet long-poll does not poll the filesystem every 100 ms.
- Disconnect promptly releases active poll capacity.
- Event detection latency does not depend on periodic 100 ms polling.
- Publication does not rewrite O(full journal) state for every small event unless benchmark proves cost negligible.
- JSON-v1 does not round-trip through legacy Task-95 encoding.
- Large/slow event responses cannot monopolize the daemon's global socket queue.
- Long-poll timeout uses monotonic time.
- Journal corruption/reset is explicit and recoverable.
