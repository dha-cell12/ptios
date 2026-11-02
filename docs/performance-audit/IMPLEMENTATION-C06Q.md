# C06q — bounded direct streamd privhelper ownership

Date: 2026-11-02 (Asia/Bangkok). Baseline: `e26c09de`; user reported C06p build passed and requested continued implementation. This C06 helper-lifecycle follow-up covers the remaining direct short-lived privhelper caller in production TrollStore streamd. TouchPOC excluded.

TLinkRunPrivhelper serves app/URL opening, app kill/data cleanup, respring, clipboard foreground launch/restore and vpnagent recovery. Its nominal timeout ended in SIGKILL followed by blocking waitpid(pid, ..., 0). A child that did not exit could therefore hold the caller indefinitely; an interrupted wait also returned immediately without child ownership cleanup.

Reuse the existing exact-PID child owner/reaper. Acquire its process-local admission before argv allocation/spawn; adopt a successful positive PID immediately before argv teardown. Keep ownership through synchronous wait and late reap. The common limit is four pending child owners per process, shared with other uses of this owner, rather than a fresh per-command quota. A timed-out/unresolved child retains its slot until terminal evidence; no timed quota reset is added.

Keep the existing positive timeout's 100ms floor/truncation and default 3000ms, with a new maximum of 30 seconds. Existing callers request 1500–7000ms and retain their durations. The wait uses continuous time plus the existing TERM/KILL grace (up to 250ms each), WNOHANG probes and a resumed deferred reaper. It never performs a final blocking reap. Healthy exit/signal results, original argument/path/allocation/spawn errors and timeout -106 remain. EINTR retries; missing/failed waits return -105. New -107 reports exhausted child admission and -108 unavailable reaper setup; neither starts a helper.

Preserve complete argv, environment and spawn attributes (including their existing absence of persona changes), all task result formatting, authority checks and fallback/recovery consumers under a full-source hash. This does not serialize different helper commands, provide caller cancellation or prevent other processes/routes from committing effects. Timeout termination may occur after a service effect has committed; no rollback or automatic replay is introduced. Existing outer fallback policy is unchanged. The long-lived streamd child watcher and separate shell/OCR process waiters remain unchanged.

The bound covers child waiting, not path lookup, argument processing, spawn/kernel stalls or every caller's queue/transport lifetime. Persistent denied signals/wait errors or lost terminal evidence can retain four slots until late completion/process exit. Device permissions and subprocess/service effects require qualification; process restart does not establish old child completion. C06 remains partial.

## Verification

Extend the existing VPN child runner, retaining its portable deadline/cancel/ownership tests. A portable compile/run probe extracts the actual timeout-normalization expression and checks default/floor/cap and INT_MIN/INT_MAX. A frozen previous direct helper and staged complete-streamd reversal preserve all other server/task/script/authority/fallback source before the existing C06b guard. No old frozen fixture is edited.

The added macOS Foundation/ARC/ASan/UBSan fixture compiles complete current and frozen direct helper functions. Controlled spawn captures exact argv/options/environment and launches only disposable forked children; no real helper, app, URL, data directory, privileged service or installed state is touched. Cases compare healthy/nonzero/signal/spawn/invalid-PID results and allocation rollback, test bounded hanging-child termination/reap, EINTR/ECHILD, four synthetic unreapable/unsignalable children with fifth refusal before spawn, late slot retirement/recovery and 32 balanced lifecycles. Real reaper timers and explicit allocation tracking are used; short wait/grace values and held-child operations are controlled for tests. Reaper-allocation failure is not forced by this fixture.

The new Apple compilation/runtime and iOS build require macOS CI. Controlled counts and policy probes are not device CPU/memory/latency measurements.

Windows validation passes all **77 workflow runners** (36 source, 41 safety), **521 existing workflow source checks**, staged full-streamd/C06b hashes, actual timeout-expression compile/run, fixture extraction, JavaScript syntax, expanded assert preprocessing and `git diff --check`. Sixteen artifact-only checks are skipped. New Foundation/disposable-child assertions were not compiled or executed on this host.
