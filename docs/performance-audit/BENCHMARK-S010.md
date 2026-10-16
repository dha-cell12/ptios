# S010 Benchmark Plan — AppDelegate / TrollStore Compatibility

## Probe A — TouchPOC tunnel idle-client wakeups and accept head-of-line

Build/install the CI-produced `TouchPOC.tipa` with `TouchPOCTunnel.appex`.

Start the tunnel TCP server and connect one client to port 6001 without sending data.

Collect for 60 s:
- `recv` calls/s,
- `usleep(5000)` wakeups/s,
- provider CPU,
- wakeups/context switches,
- dispatch queue occupancy,
- latency for a second client to connect and receive a response.

Repeat with:
- no client,
- one idle client,
- one slow byte-at-a-time client,
- one client that sends a complete line immediately.

Source expectation for one idle client: roughly **200 EAGAIN sleep/wake cycles/s**.

Then call provider/server stop while the idle client remains connected and measure whether the read loop exits.

Acceptance:
- no periodic recv/sleep polling for idle sockets,
- accept processing is not serialized behind a connected client's lifetime,
- stop closes/cancels all active clients promptly.

---

## Probe B — TouchPOC tunnel 1 Hz filesystem heartbeat

Run an otherwise idle tunnel for 10 minutes with no command file changes.

Collect:
- timer fires,
- command file stat/read count,
- `poll_state.txt` atomic writes,
- tunnel log open/seek/write/close count,
- bytes written,
- `NSLog` count,
- filesystem wakeups,
- provider CPU/energy.

Current source-visible quiet tick performs:
- one heartbeat log,
- command file existence/read,
- one atomic `poll_state.txt` rewrite,
- and, when command is absent/empty, one additional log every tick.

Compare:
A. current 1 Hz polling,
B. app-message/socket/notification driven command delivery,
C. event-driven delivery with diagnostics persisted only on change or coarse sampled cadence.

Acceptance: quiet tunnel approaches zero periodic filesystem I/O.

---

## Probe C — TouchPOC silent-audio background residency

Compare the POC app:
A. current `UIBackgroundModes=audio` + zero-volume infinite AVAudioPlayer loop,
B. audio keepalive disabled.

Background the app for 30 minutes.

Collect:
- process residency/suspension state,
- audio subsystem activity,
- CPU wakeups,
- energy impact,
- memory footprint,
- socket availability.

Acceptance for any non-diagnostic production use: background residency must be justified by a supported service mechanism rather than a perpetual silent audio stream.

---

## Probe D — Private VPN configuration helper cancellation and deadline

From a TrollStore script call `vpnconf.createResult` and exercise:
- normal IKEv2 creation,
- normal legacy private profile creation,
- intentionally delayed helper,
- helper that never exits,
- script cancellation before helper spawn,
- script cancellation immediately after helper spawn.

Collect:
- script state/latency,
- helper pid lifetime,
- caller `waitpid` duration,
- request/result temporary-file lifetime,
- time from cancellation to script terminal state,
- orphan helper/process count.

Acceptance:
- helper execution has an explicit monotonic deadline,
- cancellation after spawn reaches the helper or terminates/reaps it safely,
- script worker cannot remain blocked indefinitely,
- request/result files are cleaned on timeout/cancel.

---

## Probe E — Stream supervisor helper hang isolation

Instrument `SCStreamSupervisor` and force `privhelper --ensure-streamd` / `--kill-streamd` to:
- exit normally,
- delay 2 s,
- delay 30 s,
- never exit.

While the helper is pending, issue:
- ensure,
- restart,
- stop,
- application foreground/background lifecycle ensures.

Collect:
- supervisor serial queue wait time,
- outstanding requests,
- helper pid lifetime,
- UI-visible service status latency,
- background-task expiration behavior.

Acceptance:
- the supervisor serial queue is never held indefinitely by child process wait,
- helper timeout/failure returns a bounded result,
- later stop/restart requests can make progress.

---

## Probe F — TrollStore private VPN 100 ms polling

For private VPNConnectionStore paths, measure:
- profile create publication,
- disconnect-before-cleanup,
- connect,
- disconnect.

Collect:
- 100 ms sleep/run-loop iterations,
- `TLinkVPNPrivateConfigurationRecords` calls,
- total configuration records enumerated,
- currentConnection/status calls,
- CPU/wakeups,
- operation latency.

Worst source-visible create verification budget is 50 attempts; a 20 s connection transition can perform roughly 200 status polling iterations.

Compare event/notification-driven private-store state changes if available, or adaptive/coarser polling with a hard operation budget.

Acceptance: active transitions do not require fixed 10 Hz polling when a notification/state-change primitive is available.

---

## Probe G — TrollStore VPN broker concurrency and static preflight cost

Test both:
- foreground app broker on 6015,
- background vpnagent on 6016.

Cases:
- idle connected client that sends no newline,
- 1/4/8 concurrent query clients,
- long connect/disconnect,
- repeated diagnostics/query at 1/5/10 Hz.

Collect:
- accepted/active clients,
- utility worker count,
- foreground-broker queue/HOL latency,
- semaphore wait duration,
- entitlement/preflight probe count,
- main-thread foreground-state sync wait,
- p50/p95/p99 request latency.

Acceptance:
- one slow client cannot block unrelated foreground broker requests,
- background broker has explicit bounded admission,
- immutable entitlement/framework preflight is cached rather than rebuilt per operation.

---

## Probe H — AppDelegate keyboard observer lifecycle

In representative UIKit apps, count:
- `UIKeyboardImpl` instances,
- initializer hook invocations,
- registrations for `keyboardcontrol`,
- removals for the same notification name,
- handler invocations per one posted keyboard command.

Cycle keyboard/input views repeatedly.

Acceptance:
- exactly one intended delivery per live keyboard target,
- registration occurs only after successful initialization,
- deallocation removes the same notification registration,
- no stale/duplicate observer work accumulates.

---

## Probe I — Global dyld hook overhead

In processes receiving the appdelegate tweak, benchmark image enumeration / repeated `_dyld_get_image_name` calls with:
A. hook disabled,
B. current suffix-check hook.

Collect call count and aggregate CPU/time only; do not add per-call logging.

Acceptance: keep the hook only if compatibility requires it and measured overhead is negligible on relevant workloads.

---

## Probe J — POC foreground refresh timer

Leave the POC root view idle for 10 minutes.

Collect:
- 1 Hz timer fires,
- main-thread wakeups,
- string allocations from status refresh,
- CPU/energy.

Compare event-driven UI updates.

Acceptance: diagnostic UI should not require a permanent 1 Hz refresh when underlying values have not changed.

---

## Suggested aggregate diagnostics

- poc_provider_idle_recv_count
- poc_provider_idle_sleep_wake_count
- poc_provider_active_client_count
- poc_provider_accept_queue_wait_us / max_us
- poc_tunnel_heartbeat_count
- poc_tunnel_file_read_count
- poc_tunnel_file_write_count
- poc_tunnel_log_write_count
- vpn_private_helper_active_count
- vpn_private_helper_wait_us / max_us
- vpn_private_helper_timeout_count
- vpn_private_helper_cancelled_count
- supervisor_helper_wait_us / max_us
- supervisor_queue_wait_us / max_us
- vpn_private_poll_iteration_count
- vpn_private_configuration_enumeration_count
- trollstore_vpn_broker_active_count / max_active
- keyboard_observer_registration_count
- keyboard_command_delivery_count

Avoid per-5-ms or per-1-Hz production logging.

## Acceptance criteria

- An idle tunnel client does not create ~200 wakeups/s.
- Tunnel command delivery does not poll/read/rewrite/log to disk every second while idle.
- Production compatibility does not depend on perpetual silent audio playback.
- Private VPN helper and supervisor child waits have bounded monotonic deadlines and cancellation/cleanup.
- Private VPN state transitions avoid fixed 100 ms polling where possible.
- VPN broker concurrency is bounded without single-client head-of-line blocking.
- Keyboard observer registration/removal is symmetric.
- Compatibility hooks/timers have measured and justified steady-state cost.
