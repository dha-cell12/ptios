# S003 Benchmark Plan — IPC / Socket / H264

Goal: quantify the S003 hot-path findings before refactoring.

## Probe A — SpringBoard IPC touch overhead

Target path:
`tlinkauto-binary SocketServer -> CFMessagePort -> pccontrol/IPCMessagePort -> processTask -> Touch`

Run fixed-rate task 10 traffic at:
- 30 commands/s
- 60 commands/s
- 120 commands/s
- burst 240 commands/s for 30 seconds

Collect:
- SpringBoard CPU
- tlinkautod CPU
- logd CPU
- process wakeups
- allocations/command
- task delivery count
- dropped/rejected count
- license feature-check deltas in both processes
- message callback duration p50/p95/p99/max

Use task 61 for a separate ACK latency test.

### A/B sequence

A. Current source.
B. Logging disabled only for hot tasks.
C. B + no response-stream creation for fire-and-forget message id.
D. C + byte parser/length-aware dispatch.
E. D + cheap generation-backed license snapshot implementation.

This isolates the gain from each change instead of attributing everything to one rewrite.

---

## Probe B — IPC head-of-line blocking

On client 1, issue one long response task that occupies SpringBoard for 2-5 seconds.

While it is running, from client 2 issue:
- ping/home,
- task 10,
- task 61,
- small status request.

Measure enqueue-to-dispatch and end-to-end latency.

Repeat after queue isolation.

Acceptance goal: a heavy response task should not make unrelated high-priority touch/liveness traffic wait for the full heavy-task duration unless task ordering explicitly requires it.

---

## Probe C — MPEG-TS send syscall pressure

Profiles:
- Fast / port 7001
- Eco / port 7002

Tools:
- System Trace / syscall tracing
- Time Profiler
- Energy Log

Collect:
- send/sendto/sendmsg syscall count per second
- bytes per syscall
- kernel/network CPU
- SpringBoard CPU
- wakeups
- encoded fps
- end-to-end stream latency

A/B batching:
1. current 188-byte write
2. 7 TS packets / network write
3. 32 TS packets / write
4. one frame worth of packets / write
5. bounded sendmsg/writev implementation if selected

Wire output must remain MPEG-TS compatible.

Expected current lower bound from configured bitrates:
- Fast: roughly 1,330 TS payload sends/s
- Eco: roughly 598 TS payload sends/s

---

## Probe D — Slow/stalled H264 receiver

For each representative profile:
- connect normally for 10 s,
- stop reading without closing the TCP connection,
- hold for at least 30 s.

Capture:
- duration of the longest send call
- worker stack state
- whether license heartbeat still executes
- active-client slot state
- ability for a second client to connect
- CPU/wakeups
- memory
- time to cleanup after peer finally closes

After bounded-backpressure implementation, verify deterministic disconnect/recovery within the chosen budget.

Do not choose the final timeout until LAN/WAN measurements are available.

---

## Probe E — Adaptive decision filesystem cost

Instrument aggregate timings around:
- `TLinkAdaptiveAcquireLock`
- state file read
- JSON parse
- optional state write
- total `TLinkAdaptiveStreamingDecision`

Counters:
- decision count
- lock wait total/max
- disk read count/bytes
- disk write count/bytes
- total/average/max decision time

Run 10-minute streams on:
- 12 FPS Eco
- 15 FPS Fast
- 30 FPS raw/RTC

Also test storage contention.

After caching redesign, normal frame-loop decision should be an in-memory snapshot read with no synchronous filesystem operation.

---

## Probe F — Listener idle footprint

Compare idle SpringBoard for 10 minutes with:
1. all six current blocking accept loops,
2. streaming server disabled,
3. event-driven listener prototype.

Measure:
- thread count
- resident/private memory
- thread stack VM
- CPU
- wakeups
- energy impact

Do not claim battery improvement from listener consolidation until this measurement exists.

---

## Probe G — daemon slow socket writer / multiple clients

Create:
- one client that requests a large response and reads very slowly,
- one normal low-latency client.

Measure:
- `socketQueue` backlog
- second-client request latency
- response truncation/errors
- memory used by output buffering

Target architecture must have a strict per-client output cap and must not allow one slow peer to block all clients.

---

## Suggested lightweight diagnostics

Avoid per-packet NSLog/os_signpost in production.

Prefer aggregate counters exposed through existing diagnostics:
- ipc_received_hot
- ipc_hot_no_response
- ipc_callback_total_ns / max_ns
- ipc_response_bytes
- h264_send_calls
- h264_send_bytes
- h264_send_block_total_ns / max_ns
- h264_adaptive_decisions
- h264_dropped_late_frames
- h264_disconnect_backpressure
- listener_accept_errors_by_errno

For latency distributions, enable sampled signposts only in profiling builds.

## S003 optimization acceptance criteria

- Hot touch IPC: zero unconditional per-event logs in production.
- Fire-and-forget touch: no allocated response stream/property path.
- External per-command license enforcement remains active but becomes constant-time on cache hit.
- TS streaming: network syscall count is no longer proportional to 188-byte packet count.
- A stalled receiver cannot block the stream worker/client slot indefinitely.
- Normal H264 frame loop performs no synchronous state-file JSON read.
- One slow daemon TCP client cannot globally block unrelated clients.
- Idle listeners have no polling/busy-spin behavior.
