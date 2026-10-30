# C06c — bounded supervisor helper waits and retained admission

Date: 2026-10-31 (Asia/Bangkok). Baseline: `573ea337`; user reported the preceding C06b build passed. Complete normalized supervisor baseline SHA-256: `851abce84156b80eabfab2dd110e8edd53861d91223b1b08a166f948bda929f4`.

Status: source/portable validation on Windows; new complete supervisor Foundation/POSIX/GCD/ARC/sanitizer runtime pending macOS CI and independent device qualification. Addresses part of **P0-23** in production StreamControl.

## Change

runPrivhelperEnsureStreamdLocked and runPrivhelperKillStreamdLocked used blocking waitpid on the supervisor serial queue. A hung root helper could therefore prevent later lifecycle requests from running indefinitely. The separate long-lived direct streamd child is already waited on a background queue and is unchanged.

Use the existing C06a/b exact-PID owner for these two helper submissions. Preserve paths, argv, persona setup and healthy exit/log mapping. Admit before argv allocation; allocate a resumed monitor before spawn; adopt immediately on successful spawn. Wait with the existing thirty-second steady-clock policy, TERM/KILL attempts and two 250-millisecond grace windows. EINTR uses the same deadline. Unknown/unreaped children move to nonblocking deferred reaping rather than another blocking wait. Timeout maps to -ETIMEDOUT, wait failure to -ECHILD, capacity/lane refusal to -EBUSY and monitor setup failure to -ENOMEM. Record last native/signal error and reap-pending state in failure logs.

Check posix_spawnattr_init before using its output. On failure free argv and return its error without calling persona setters, spawning, or destroying uninitialized attributes. Preserve successful persona calls and existing spawn error mapping. Failed argv allocation and spawn still release their existing resources.

Add one process-local supervisor helper lane. Its RAII lease is retained by child/reaper state, in addition to the existing common four-child admission cap shared with VPN helpers in that process. The lane remains occupied through unknown child death and source cleanup; failed admission cannot release another helper's lease. A deferred owner holds only this resource lease, child state and POSIX adapters, with no supervisor reference or callback. Existing VPN owners use an empty extra lifetime and keep their previous behavior.

While that lane is occupied, new ensure/restart/stop/direct-spawn lifecycle requests fail closed before further service effects. Ensure completes asynchronously on main with NO and supervisor_helper_pending. Other void methods log that retry is required. A stop request still disables auto-respawn, then refuses further cleanup while the earlier helper is unresolved. No refused request is automatically replayed when the lane opens; callers must retry explicitly. This is a new busy outcome, not a guarantee that the service stopped.

After cleanup's own kill-helper wait, preparePortForSpawnLocked checks the lane again. If the helper is still unresolved, it returns NO instead of proceeding into direct-spawn fallback. A successful or fully reaped helper releases the lane and preserves existing port probes/fallback behavior. This prevents a timed-out supervisor helper from silently overlapping a later command on the same lifecycle queue. The lane also rejects another supervisor instance's helper submission; high-level preflight checks are not a transaction across independent supervisor queues/processes.

## Verification

Both workflows run check-supervisor-helper-safety.mjs. It reverses the owner/wait/attribute-check changes inside each complete helper method, then reverses only the new lifecycle guards/includes/fence. The result must equal the frozen complete supervisor source and SHA-256, preserving the background daemon waiter, watchdog, path/probe logic, delegate delivery and unchanged lifecycle code.

Portable C++11 tests exercise retained shared ownership of the lane, duplicate refusal/release behavior, 8 x 10k concurrent acquisition lifecycles and zero final active charges. Existing VPN/helper policy tests continue to cover deadline/cancellation/EINTR/ECHILD/signals and owner cleanup.

The new macOS fixture compiles complete current and frozen supervisor implementations. Real Foundation queues, completion dispatch, POSIX attribute objects, argv allocations and disposable subprocesses exercise the helper methods. Path/persona/spawn providers and service/network/delegate effects are controlled; no actual privileged helper or daemon is launched, and no real service is stopped. Compare all three kill/ensure/replace argv variants for exit zero/nonzero/spawn error and allocation faults; check new attribute-init failure without spawn. Add shared four-child saturation, a controlled unreapable helper holding the supervisor lane, another-instance rejection, queue/main completion progress after timeout, busy ensure/restart/stop/spawn with no service effects, auto-respawn disable, refusal after cleanup's own timeout, retirement without replay and 64 balanced helper/source lifecycles.

Windows validation: all 72 workflow runners (36 source, 36 safety), expanded assert preprocessing, JavaScript syntax and git diff --check pass. Existing workflow source checks are recorded in STATE.md. Actual Foundation/POSIX/GCD/ARC/ASan/UBSan additions require macOS CI. No measured device latency/CPU/memory improvement is claimed.

## Limits

The active helper wait still occupies the lifecycle serial queue until completion or timeout/grace. Request admission is before spawn but this is not an end-to-end bound on argv/filesystem/persona/spawn operations, local sockets, probes, other sleeps or scheduling. There is no new cancellation/preemption/coalescing of active supervisor work. Refused stop/restart work needs an explicit retry after the old helper retires.

TERM/KILL permission from mobile to a root-persona helper remains subject to device qualification. Denied signals or persistent wait errors can pin the lane until eventual exit/ECHILD or process restart; the reaper stays bounded and does not claim successful termination. Killing a helper does not undo already committed service effects. Cross-process/multiple-queue lifecycle transactions, BGTask expiration/late ensure behavior, private backend polling, direct daemon waiter lifecycle and the remaining C06/device work remain open. TouchPOC is excluded.
