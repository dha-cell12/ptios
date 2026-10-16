# S011 Benchmark Plan — License Lifecycle / Control Plane

## Probe A — Rootfull cache-miss authority round-trip

Measure `TLinkLicenseFeatureAllowed` in each rootfull process with:
- warm cache,
- 5 s TTL expiry,
- generation change,
- authority server delayed by 50/250/1000/3000 ms,
- authority unavailable.

Collect:
- feature-check p50/p95/p99/max,
- cache queue wait time,
- authority socket connect/send/recv time,
- authority request count,
- cache hit/miss count,
- callers blocked behind one miss.

Run specifically with:
- ScriptPlayer 1 Hz license heartbeat,
- one H264 client with 5 s license heartbeat,
- both concurrently,
- normal external tasks.

Acceptance:
- a cache refresh must not synchronously block protected runtime work for authority/network-style timeout durations,
- only one refresh may be in flight per process and ordinary checks use the last verified snapshot,
- authority outage has a bounded, explicitly designed stale-snapshot/fail-closed policy.

---

## Probe B — Generation invalidation: Darwin notify versus 250 ms file polling

Instrument all rootfull processes using the verifier.

For 10 minutes with stable license generation, collect:
- feature check count,
- Darwin notification count,
- generation file read count,
- generation poll count,
- file-open/read bytes and latency per process.

Workloads:
- idle,
- script heartbeat only,
- H264 heartbeat only,
- high-rate task dispatch.

Then advance generation once and measure invalidation propagation latency using:
A. current notify + file poll,
B. Darwin notify only with startup/recovery validation,
C. a much coarser safety reconciliation poll.

Acceptance:
- steady-state protected work should not read the generation file up to four times/s/process merely to duplicate Darwin notification invalidation,
- cross-process invalidation remains reliable after missed-notification/restart scenarios.

---

## Probe C — Authority server concurrency/admission

Open 1/4/16/64 clients to `license-authority.sock`.

Cases:
- valid status requests,
- clients that connect but delay newline,
- clients that read responses slowly,
- burst synchronized cache misses from pccontrol/tlinkautod/jsd/vpn-broker.

Collect:
- active utility workers / max,
- accept rate,
- per-client lifetime,
- trust-checkpoint lock wait/hold time,
- Keychain sign operations,
- status evaluation latency,
- response latency,
- memory/worker growth.

Acceptance:
- explicit active-client admission exists,
- slow clients do not create an unbounded utility-worker pool,
- status computation is coalesced/cached when many clients request the same generation.

---

## Probe D — Authority proof crypto/I/O decomposition

For one authority status refresh count and time:
- client config reads,
- client lease read/parse,
- client lease ECDSA verification,
- authority local lease ECDSA verification,
- authority device-key possession sign + verify,
- trust-checkpoint signature verification,
- trust-checkpoint sign/write if due,
- authority response private-key signature,
- client authority response signature verification,
- JSON/base64 allocations and bytes.

Repeat at 1 Hz and every 5 s.

Acceptance:
- immutable lease/public-key anchoring is not re-verified redundantly on every short-lived status proof when generation has not changed,
- private-key signing is not used as a periodic heartbeat primitive unless required by the threat model.

---

## Probe E — Trust checkpoint contention and 60 s write cadence

Issue concurrent authority status requests around the trust-checkpoint 60 s advancement boundary.

Collect:
- exclusive flock wait/hold time,
- checkpoint read/verify count,
- checkpoint signature count,
- atomic rewrite count,
- callers queued behind the lock.

Acceptance:
- lock scope contains only state that truly requires serialization,
- repeated status reads do not cause needless checkpoint I/O,
- the intended <=1 write/minute behavior remains true under concurrency.

---

## Probe F — Lease save validation amplification

For one successful refresh and one activation, count:
- full `TLinkLicenseStatusDictionary` evaluations,
- lease file reads/writes,
- checkpoint reads/resets/recreates,
- private-key sign operations,
- generation writes/notifications,
- post-save `localStatus` calls.

Compare current transaction with a design that validates the candidate once in memory, commits atomically, then publishes one generation change.

Acceptance:
- a successful lease commit performs one authoritative candidate validation, not repeated full disk/crypto passes,
- rollback safety is preserved without reset-then-recreate churn.

---

## Probe G — Lifecycle launch/foreground single-flight placement

Cold launch StreamControl and capture:
- app launch callback,
- didBecomeActive callback,
- UI snapshot refreshes,
- `manager localStatus` calls,
- automatic refresh decisions,
- diagnostics writes.

Repeat rapid foreground/background cycles.

Acceptance:
- single-flight/coalescing happens before expensive status verification,
- launch followed by didBecomeActive does not cause redundant full status/crypto work for the same generation.

---

## Probe H — Background task timeout/cancellation

Run BG refresh with:
- HTTP response 1 s,
- HTTP response 19 s,
- HTTP response 21 s,
- HTTP request that ignores/extends timeout,
- iOS expiration before completion,
- slow/hung stream supervisor ensure.

Collect:
- BGTask completion time,
- URLSession task lifetime,
- refresh callback after BGTask completion,
- supervisor ensure calls after expiration,
- file writes/notifications after task expiry.

Acceptance:
- expiry/watchdog cancels or invalidates downstream refresh work,
- a late completion cannot start service recovery after the BGTask has already completed,
- timeout hierarchy leaves budget for streamd ensure or splits the operations.

---

## Probe I — Lifecycle diagnostics write amplification

For:
- launch outside refresh window,
- foreground outside refresh window,
- failed refresh,
- successful refresh,
- activation/deactivation,

count reads and atomic rewrites of `license_lifecycle.plist`.

Also measure bytes rewritten and time under `@synchronized(self)`.

Acceptance:
- diagnostics are memory-backed/coalesced and flushed once per logical operation or at a coarse cadence,
- refresh history append does not read the same plist twice before one write.

---

## Probe J — Task 75/76/97 diagnostic authority cost

Measure each rootfull diagnostic task:
- 75 status,
- 76 reload,
- 97 capability.

Collect authority request count, generation-file reads, crypto operations, output size and latency.

Exercise any supervisor/health-check caller that probes 97 repeatedly.

Acceptance:
- status/capability probes reuse a verified snapshot where freshness permits,
- diagnostics do not force a fresh signed authority proof on every probe.

---

## Suggested aggregate diagnostics

- license_cache_queue_wait_us / max_us
- license_cache_refresh_count
- license_authority_request_count
- license_authority_active_clients / max_active
- license_authority_worker_wait_us
- license_authority_status_compute_us
- license_authority_sign_count
- license_client_lease_anchor_verify_count
- license_generation_file_read_count
- license_generation_notify_count
- license_trust_lock_wait_us / hold_us
- license_trust_verify_count
- license_trust_write_count
- license_status_full_validation_count
- license_lease_commit_validation_count
- license_lifecycle_status_request_count
- license_lifecycle_diagnostics_read_count
- license_lifecycle_diagnostics_write_count
- license_bg_late_completion_count
- license_bg_cancel_count

Avoid per-heartbeat production logging.

## Acceptance criteria

- Rootfull heartbeat/task checks do not synchronously perform a multi-process signed authority round-trip on TTL boundaries.
- Stable generations do not cause repeated generation-file polling in every busy process.
- Authority server concurrency is explicitly bounded.
- License proof crypto is proportional to license state changes, not heartbeat frequency.
- Lease refresh commits do not repeatedly re-verify/re-sign the same state.
- Lifecycle single-flight/coalescing precedes expensive status work.
- BGTask timeout/expiration stops downstream work.
- Diagnostics persistence is batched/coalesced.
