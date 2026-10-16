# S006 Benchmark Plan — JavaScript Runtime / Native Bridge

## Probe A — Helper RPC latency and polling tax

Compare identical lightweight native calls in:
1. in-process runtime,
2. current helper runtime.

Workloads:
- 1k and 10k `frontMostAppId`
- `framePickColor` against an existing frame
- taps where safe on a test device

Capture:
- helper request creation timestamp
- first SpringBoard observation timestamp
- native execution start/end
- response received in helper
- p50/p95/p99/max total RPC latency
- status polls/RPC
- Unix socket connections/RPC
- CPU, wakeups and context switches

Also run an active helper script for 10 minutes with no native calls. Current design should generate ~5 status socket/JSON cycles/s due to the 200 ms polling loop.

A/B:
- current 200 ms poll,
- event-driven persistent transport or long-poll prototype.

Do not benchmark by shortening the fixed poll interval as the proposed optimization.

---

## Probe B — In-process typed bridge overhead

Use a no-op/lightweight task and a frame-backed color read.

For 10k/100k calls record:
- allocations/call
- bytes allocated/call
- NSString/NSData/CFWriteStream creation counts
- processTask time
- response parse time
- total p50/p95/p99

Compare:
A. current typed args -> NSString wire -> NSData -> CFWriteStream -> NSString -> split array,
B. structured in-process handler returning typed result,
C. legacy rawTask unchanged for compatibility.

Expected acceptance: structured hot calls should not allocate an in-memory stream or parse protocol delimiters.

---

## Probe C — Cancellation propagation

For each operation:
- shell command lasting 30 s,
- native gesture lasting several seconds,
- worst-case template search,
- OCR request under load,

start the operation and request stop after 100 ms.

Measure:
- stop request -> native handler notices cancellation
- stop request -> worker returns
- side effects after stop
- old-generation event count after session completion

Current bridge is expected to lose Task context because it calls `processTask`, which routes to `processTaskWithContext(..., nil)`.

Acceptance: long native operations observe the same session token at bounded intervals; no old-generation side effects occur after cancellation completion.

---

## Probe D — Helper policy/config overhead

For 10k helper RPCs, measure:
- config.json opens/reads
- JSON parse count/time
- policy time
- argument fingerprint JSON bytes/time
- total RPC CPU

A/B current per-RPC `TLinkautoJSHelperConfigSnapshot()` vs immutable generation/mtime-backed snapshot.

Acceptance: normal RPC policy check performs no synchronous filesystem read/JSON parse.

---

## Probe E — Helper RPC cache memory

Generate up to 256 unique request IDs with controlled result sizes:
- 1 KiB
- 64 KiB
- 512 KiB
- near 1 MiB where supported

Record:
- cache entry count
- retained result bytes
- RSS
- eviction cost
- fingerprint bytes

After redesign, enforce an explicit cache byte budget as well as entry count.

---

## Probe F — Console logging stress

Scripts emit:
- 100 lines/s
- 1,000 lines/s
- burst 10,000 lines

Record:
- JS-thread time spent in console call
- log queue depth / queued bytes
- NSFileHandle opens/closes
- metadata syscalls
- disk writes
- RSS
- script-finish flush duration
- logd CPU due to NSLog

A/B current per-line double-file open/write/close vs persistent bounded batch writer.

Acceptance: queue memory is bounded and script teardown does not wait on an unbounded log backlog.

---

## Probe G — readLine syscall amplification

Files with newline at:
- 80 bytes
- 4 KiB
- 64 KiB
- 512 KiB limit

Count `read()` syscalls. Current implementation should approach one syscall per byte.

Compare with buffered per-handle reader using 8/16/32 KiB chunks.

---

## Probe H — File representation/copy cost

Read a 512 KiB UTF-8 text file through the file-handle API.

Track simultaneous:
- NSMutableData
- UTF-8 NSString
- base64 NSString
- JS conversion allocations

Then compare explicit text-only and base64-only result modes.

Also benchmark:
- readJSON file -> NSString -> NSData -> object,
- writeJSON object -> NSData -> NSString -> NSData/write,
against direct NSData JSON I/O.

---

## Probe I — Input/output bounds

Input:
- 8,191 / 8,192 / 8,193 chars
- max-size batch/gesture/shell payload

Verify current silent truncation signature and then explicit rejection/structured handling.

Output:
- 0.5 / 1 / 2 / 4 MiB producer response

Measure peak allocated-buffer stream size before rejection. Acceptance: output budget prevents materialization beyond the configured cap.

---

## Probe J — Runtime startup

Measure 1k tiny script starts:
- VM creation
- JSContext creation
- prelude evaluation
- source evaluation
- cleanup

This is P2. Do not pool VM/context unless measured startup cost materially matters and isolation/leak tests pass.

### Suggested aggregate diagnostics
- js_native_call_count
- js_native_total_us / max_us
- js_native_wire_bytes
- js_native_cancel_latency_us
- helper_status_poll_count
- helper_socket_connect_count
- helper_rpc_detection_us
- helper_config_reload_count
- helper_rpc_cache_entries / bytes
- js_log_queue_bytes / dropped_lines
- js_file_read_syscalls
- js_file_bytes_read / written

No per-call production NSLog/signposting.
