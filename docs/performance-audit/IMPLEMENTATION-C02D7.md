# C02d7 — runtime adoption of bounded helper change waits

Date: 2026-10-26 (Asia/Bangkok). Baseline: `014db57`; the user reported C02d6 built successfully before this slice.
Status: **user reported build `12a915e` passed before C02d8; independent device/performance qualification remains pending**.
Finding: **P0-12 runtime wait adoption, cancellation and replay-safe reconciliation**.

Follow-up: C02d8 adds opted-in server EOF cancellation; see `IMPLEMENTATION-C02D8.md`. The implementation and validation descriptions below record this slice before that follow-up.

## Runtime behavior

The rootfull/roothide helper runtime now uses waitForChange when the first validated status advertises both `changeWaitContract: session_native_rpc_v1` and `sessionSnapshotContract: lifecycle_rpc_owner_v1` with a valid positive numeric cursor. Negotiation is local to the pinned helper/session. Missing or unknown contracts keep the legacy 200-ms status-delay path; an explicit unsupported_command reply downgrades the remainder of the session. Matching contracts with a malformed cursor, later capability loss or a regressing status cursor fail closed.

After handling a running/starting/stopping status, the negotiated path waits up to 750 ms for publication instead of unconditionally sleeping 200 ms. Every successful hint, quiet timeout and recoverable wait fault returns to a fresh status request. A hint never supplies native work and never advances the processed status cursor. Native effects still require the current helper/session/native-request ownership check and reserve-before-execute replay dispatch. Hints have a strict numeric/boolean/reason schema; malformed hints and identity/session/cursor errors terminate the run.

A busy wait or transient wait socket failure uses a cancel-aware 100-ms backoff and a new status connection. Lost native-response acknowledgements follow the same status reconciliation path, retaining the session replay ledger; if the same native ID remains pending, the cached reply is sent rather than repeating its effect. Unknown ACK errors, rejected ownership and status-read failures remain fatal. No helper start or native command is automatically repeated by this loop. It still opens fresh sockets; persistent connection transport is not implemented.

## Budgets, cancellation and cleanup

The manifest helperTimeoutMs/helper_timeout_ms keeps the existing default 10000 ms and maximum 300000 ms. Its execution window still begins after a successful start, but now uses the shared continuous clock rather than wall-clock NSDate. Start has its own at-most-1000-ms budget, shortened by an existing caller native budget. Caller cancellation/stopped budgets reject before start. Each subsequent status/ACK/wait budget is shortened by both the remaining manifest window and caller/native budget.

An owned task context carries the helper session/run IDs, caller automation/touch hooks, scalar policy, cancellation and an inherited native deadline. The caller context's owner fields and native budget are not modified. The loop checks stop/deadline/output state after I/O, before replay dispatch, and again after policy/config work immediately before a native call. Native operations receive the owned context and keep their existing cooperative deadline/cancellation/output and cleanup rules. This does not undo a committed effect or instantly preempt opaque native work.

The helper client now accepts a synchronous, run-owned cancellation check. When configured, its nonblocking I/O adapter checks before send/receive and uses poll slices no larger than 50 ms while retaining the original absolute I/O deadline. Silent wait/status sockets can close on cancellation without waiting for the full request budget. Actual latency includes kernel scheduling and opaque calls; 50 ms is the requested poll slice, not a hard real-time guarantee. This cancellation polling adds kernel wakeups, so no net energy/wakeup improvement is claimed without measurements. Unconfigured client callers retain the existing unsliced I/O path.

Failure/exception cleanup clears the client's cancellation hook before one best-effort, pinned stop request (separate 250-ms cleanup budget), then releases tracked native handles and runtime/context/replay ownership. Stop-send errors cannot prevent local cleanup. Per-iteration autorelease pools bound retained temporary status/hint objects to their iteration; replay-owned data retains its explicit existing byte/identity limits. The root runtime's cross-thread stop snapshot and its session-ID assignment/clear now share the handle lock, preventing copy/release races. Independent stop delivery while native work is busy remains in place.

The server retains C02d5's four sleeping waiters, eight-client admission, deadline/output reserve and C02d6's lifecycle owner. A disconnected waiter can still occupy its bounded server slot until its wait ends; prompt server disconnect cancellation remains open.

## Start outcome and default fallback

Default helper selection previously considered any “helper start failed” text eligible for in-process fallback. A lost start reply can mean that the helper already began the script. The caller now accepts fallback only through explicit internal helperFallbackSafe metadata: a correlated helper_busy rejection or connect/socket-setup failure before command delivery. An already-busy current runtime does not fall back into itself.

Read/write timeouts, missing/mismatched replies, oversized frames and unclassified start failures do not authorize fallback. Some definitely rejected requests are conservatively left as errors rather than inferring delivery state from an ambiguous code. Explicit helper selection retains its error behavior. This change prevents automatic script reexecution after an uncertain start; it does not recover the unknown session ID when an acknowledgement is lost.

## Verification

The portable transport suite adds 1000 injected cancellation schedules, bounded poll slices with the original absolute timeout, pre-cancel write suppression, and 100000 runtime-window budget plans including saturation boundaries. Existing 100000 partial/EINTR/EAGAIN framing and sender-window cases remain. The actual macOS client/socket fixture adds cancellation of a silent peer and verifies descriptor close rather than a full-budget wait.

The existing change-wait runner now compiles the actual runtime helper method in a Foundation/ARC/ASan/UBSan fixture with the real task context, replay ledger and streaming fingerprint. The helper client and config/native policy dependencies are controlled. It exercises capability and legacy modes, quiet timeouts, unsupported/busy/lost-wait replies, status-derived cursor use, lost-ACK replay with one effect, cursor/identity/hint rejection, caller cancellation at status/policy/wait/native boundaries, pre-expiry/output rejection, timeout after status, NS/C++ exception cleanup, caller-context isolation and safe/uncertain start classification. The complete production UIKit/JavaScriptCore/helper/device stack remains a separate qualification.

All 62 workflow runners (36 source-contract, 26 native), 521 direct workflow source-grep assertions, standards-conforming assert preprocessing and git diff --check pass on Windows; 16 artifact-only checks need CI outputs. Focused wait/transport and preprocessing checks were repeated after the final fallback/stop ownership changes. Windows cannot compile/execute the new Objective-C++ Foundation paths. macOS CI and device traces must validate behavior and actual CPU/RSS/wakeup/p50/p95/p99 changes. No measured performance improvement is claimed.

## Remaining work

Qualify matching rootfull/roothide builds with quiet helper scripts and rapid native calls, stop while waiting and during native work, sleep/wake, busy wait admission, dropped ACKs/connections and helper/session replacement. Verify one native effect per ID, cleanup and bounded FD/memory recovery. Compare legacy peers and mixed capability versions. Persistent connections, cancellation wake descriptors/prompt server disconnect handling, unknown-start recovery, richer status reconnection and C01/C02 performance/device acceptance remain open, along with remaining P0-13 adapters and P1-40 invalidation. TouchPOC and production TrollStore execution source are unchanged; both workflows run the shared checks.
