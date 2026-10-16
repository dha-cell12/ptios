# S009 Benchmark Plan — VPN / Accessibility Rootfull Paths

## Probe A — Task 59 timeout hierarchy and SpringBoard IPC head-of-line blocking

Exercise Task 59 through the normal daemon -> SpringBoard -> localhost VPN broker route.

Cases:
- query,
- diagnostics,
- connect/disconnect that completes in <5 s,
- connect/disconnect that completes in 5–20 s,
- broker unavailable,
- broker accepts but stalls.

Collect:
- daemon CFMessagePort send/receive duration,
- SpringBoard `handleIPCMessage` duration,
- localhost broker socket duration,
- broker operation duration,
- latency of an unrelated ping/status/touch-ack queued behind Task 59,
- client-visible error/success and whether the VPN operation continues after the caller timed out.

Current source timeout hierarchy:
- daemon CFMessagePort response wait: 5 s,
- broker query/diagnostics wait: 8 s,
- broker connect/disconnect wait: 24 s,
- SpringBoard broker socket send/receive timeout: 30 s.

Acceptance:
- no inner operation is allowed to outlive an already-failed synchronous outer IPC request without an explicit asynchronous operation contract,
- unrelated SpringBoard IPC is not blocked by a long VPN transition,
- retries cannot create duplicate/ambiguous connect/disconnect work.

---

## Probe B — VPN broker concurrency

Open 1/4/8/16 localhost broker clients concurrently and issue a mix of:
- query,
- diagnostics,
- connect/disconnect,
- intentionally stalled requests.

Collect:
- libdispatch worker count,
- blocked stacks in `dispatch_semaphore_wait`,
- request p50/p95/p99/max,
- memory/thread-stack growth,
- completion latency for a new query while long transitions are active.

Acceptance: long VPN transitions do not consume an unbounded number of global worker slots; admission is explicitly bounded.

---

## Probe C — Hello/status VPN diagnostics cost

Poll Task 60 at:
- 1 Hz,
- 5 Hz,
- 10 Hz.

Instrument only aggregate counters/time for:
- `SecTaskCreateFromSelf`,
- `SecTaskCopyValueForEntitlement`,
- private compatibility marker `fileExistsAtPath`,
- total `TLinkVPNDiagnosticsSnapshot` duration,
- Task-60 total duration,
- allocations/bytes.

Source expectation: each snapshot creates a SecTask and performs 10 entitlement lookups before building the diagnostics dictionary.

Compare:
A. current full probe per Task 60,
B. process-lifetime cached immutable entitlement/framework capabilities + only truly mutable VPN state refreshed.

Acceptance: static capability probes disappear from the steady-state status polling path.

---

## Probe D — AX snapshot scaling

Create test screens with source accessibility element counts near:
- 25,
- 100,
- 250,
- 500,
- 1000+.

For each, test:
- mostly visible elements,
- mostly offscreen/filtered elements,
- mostly non-clickable elements.

Collect:
- source_count,
- scanned_count,
- returned count,
- AX attribute calls,
- total AX RPC time,
- allocation count/bytes,
- snapshot latency p50/p95/p99/max.

Important: record whether `scanned_count` exceeds requested `max_elements` when filters remove rows.

Acceptance:
- a hard scan-work budget exists independently of returned-row count,
- work scales predictably and cannot run through an arbitrarily larger source list merely because rows are filtered.

---

## Probe E — Find/tap early-match cost

Place the requested target at:
- element 1,
- element 10,
- element 100,
- near the end,
- absent.

Run Task 79 and Task 81 with selector index 0.

Collect:
- elements scanned,
- elements fully serialized,
- AX attribute calls,
- temporary node dictionaries,
- match-array entries,
- latency.

Compare:
A. current full snapshot + second-pass matching,
B. single-pass selector scan that fetches only attributes needed to reject candidates, then fully serializes the selected match.

Acceptance: an early match does not require materializing the complete snapshot when action correctness does not require it.

---

## Probe F — AX serial-queue head-of-line and abandoned work

Start one worst-case Task 78/79, then immediately issue Task 80 and a second Task 79 from other clients.

Repeat while closing the initiating client immediately after dispatch.

Collect:
- wait time before entering `TLinkAXQueue`,
- execution time inside the queue,
- time until abandoned work stops,
- number of queued callers,
- SpringBoard IPC callback occupancy.

Acceptance:
- client disconnect/cancellation can stop expensive queued/current AX work at safe checkpoints,
- a slow snapshot does not create multi-request queue buildup beyond an explicit bounded policy.

---

## Probe G — UI-tree result byte amplification

Generate snapshots at 50/250/1000 returned elements and vary label/value/identifier string sizes.

Measure:
- in-memory NSDictionary graph estimate,
- JSON NSData bytes,
- base64 NSString bytes,
- final legacy response bytes,
- peak transient allocations,
- CFMessagePort response bytes,
- encode duration.

Acceptance:
- explicit raw/wire response byte ceilings exist,
- per-node text fields are bounded,
- overflow returns a defined partial/truncated result instead of growing until memory/transport limits.

---

## Probe H — Frontmost-context main-thread crossings

For Tasks 78–81, measure:
- time waiting for each `dispatch_sync(dispatch_get_main_queue())`,
- number of frontmost-context queries per request,
- total request latency while SpringBoard main thread is idle vs deliberately busy.

Current source path performs a frontmost query before the AX operation and another context-change query after a successful operation.

Acceptance:
- main-thread crossings are minimized/cached safely,
- no request thread can wait indefinitely on main-thread work,
- context-change correctness is preserved.

---

## Probe I — AX lock-state/capability probe overhead

At 1/5/10 Hz call:
- Task 77 capability,
- Task 78 small snapshot,
- Task 80 hit-test.

Count:
- notify registration/get/cancel operations,
- SpringBoardServices `dlopen`/`dlsym` calls,
- Security `dlopen`/`dlsym` calls,
- entitlement probes,
- total probe time.

Compare cached framework/symbol handles and stable capability values against current repeated setup.

Acceptance: stable framework/symbol/capability discovery is process-lifetime cached; mutable lock state remains fresh.

---

## Probe J — AX deadline behavior

Run snapshot/find against a deliberately slow/unresponsive AX target at timeout_ms:
- 100,
- 500,
- 1500,
- 3000.

Measure elapsed time with a monotonic external clock.

Record overshoot caused by a single per-element AX call completing after the loop deadline check.

Acceptance:
- elapsed time is bounded close to requested deadline plus one explicitly documented RPC allowance,
- timeout budgeting uses a monotonic clock,
- cancellation is checked between RPCs/elements.

---

## Suggested aggregate diagnostics

- vpn_task59_total_us / max_us
- vpn_task59_outer_timeout_count
- vpn_broker_active_count / max_active
- vpn_broker_wait_us / max_us
- vpn_diagnostics_snapshot_count
- vpn_diagnostics_entitlement_probe_count
- vpn_diagnostics_total_us
- ax_queue_wait_us / max_us
- ax_snapshot_source_count / scanned_count / returned_count
- ax_attribute_call_count
- ax_snapshot_total_us / max_us
- ax_find_total_us / max_us
- ax_cancelled_count
- ax_result_json_bytes
- ax_result_wire_bytes
- ax_main_sync_wait_us / max_us

Avoid per-element production logging.

## Acceptance criteria

- Task 59 cannot monopolize SpringBoard IPC beyond the daemon's caller timeout.
- VPN broker concurrency is bounded.
- Frequent Task-60 status does not redo static entitlement/framework probes.
- AX find/tap can short-circuit rather than materializing a full snapshot.
- AX scan work has a hard bound independent of filtered return count.
- Slow/abandoned AX work is cancellable and does not indefinitely queue later UI tasks.
- UI-tree output has explicit byte/string bounds.
- Main-thread crossings are measured and minimized without weakening foreground-context validation.
- Timeout budgets use monotonic time and have documented overshoot limits.
