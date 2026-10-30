# C06e — supervisor ensure admission after queue residence

Date: 2026-10-31 (Asia/Bangkok). Baseline: `e8a56fa1`; user reported C06d build passed. Status: source/portable validation on Windows; expanded Foundation/GCD/ARC/ASan/UBSan runtime pending macOS CI and independent device qualification. Addresses part of **P1-76**, extending C06d in production StreamControl. TouchPOC is excluded.

## Change

C06d prevented a license callback arriving after BGTask completion from submitting an ensure. An ensure admitted by the scheduler before expiration could still wait on the supervisor's serial queue, then start after the task finished. C06e adds an admission check on that queue, after queue residence and before any ensure work.

Add ensureServiceWithStartPermission:completion:. Its optional short, nonblocking permission block is evaluated once on the supervisor queue, before the existing helper-busy fence, auto-respawn enable, service/helper probes or direct-spawn fallback. NO returns supervisor_ensure_cancelled_before_start; a synchronous NS/C++ predicate exception returns supervisor_ensure_admission_exception. Both refuse without running the ensure body and report NO asynchronously on main. A nil completion is valid. The old ensureServiceWithCompletion: method delegates with nil permission, preserving its existing owner-queue body, main completion, helper-busy result and ordinary lifecycle behavior. Other start/stop/restart/watchdog methods retain their complete source.

The scheduler supplies run->beginSupervisor() as the permission block. Add a SupervisorStarted phase between Ensuring and Finished. The new transition is allowed once, only while Ensuring, under the same mutex as terminal close. The existing beginEnsure transition still governs the license callback's submission. If expiration/timeout closes the owner while an ensure is queued, beginSupervisor refuses when the queue reaches it. The completion received later cannot overwrite the BGTask's terminal result or diagnostics. Retained permission/completion blocks keep the same closed token without restoring the task captures C06d detached.

Permission is an admission boundary, not an active cancellation predicate. If beginSupervisor wins the mutex before terminal close, the existing ensure body may proceed afterward, including enabling auto-respawn. No state mutex is held across supervisor probes, helper waits or external callbacks. A closed/refused request is not replayed and does not terminate an already running service or change the existing auto-respawn flag. A newer independent BGTask can make its own request.

## Verification

The existing two workflow runners now check an additional reversal stage through scripts/lib/background-supervisor-admission-baseline.mjs. Reproduce the complete pre-C06e supervisor, public header, scheduler and BGTask owner with SHA-256 respectively:

- supervisor: `5ab346f8af40b022231eb28d9235bad173bba2cd968e46090e7219a1445c8a65`
- supervisor header: `4bba2d1f6c0ddab9117f82c1cbe260b2ac4d68d5971ef65b15d38282449a8db3`
- scheduler: `c65efdfe0ed5bd763c3ade66ad3ceb79644e6e64011ca9f5d521823dabb0916c`
- BGTask owner: `7097eb51f5b14487928da5446a53ff7158f57c510fc47b4260eb5fcbaf5baed7`

Then run the unchanged preceding C06c/C06d complete-source reversals and frozen digests. Runtime extraction still compiles current source; the legacy supervisor header is restored to its preceding surface so the new selector is not falsely required of the frozen class. No historical digest or frozen implementation is replaced.

Expand the complete supervisor fixture with real serial-queue holds and main-queue completion delivery. Compare old wrapper, nil permission and allowed permission against the frozen public ensure for success and direct fallback, including result detail, provider counts and auto-respawn. Add false/NS/C++ permission refusal before effects, nil completion, sixty-four requests closed by the actual BGTask owner during real queue residence, two hundred owner-start/finish races, and a deliberately held admitted provider proving the active-work boundary. Service/probe/fallback effects remain controlled; no real daemon, privileged helper or network service is affected. Existing disposable helper subprocess and ownership tests remain intact.

Expand the complete scheduler fixture with a controlled deferred supervisor-start adapter. Expiration and watchdog completion while queued release the BGTask despite retained permission/reply blocks; starting later is refused without another diagnostics write. Healthy queued admission succeeds once and a second permission call is rejected. These adapter tests complement the actual supervisor queue cases rather than claiming an iOS BGTask integration run.

Windows validation: all **73 workflow runners** (36 source, 37 safety) pass after a targeted touch rerun, and **521 existing workflow source checks** pass; sixteen artifact-only checks are skipped. JavaScript syntax, expanded assert preprocessing and git diff --check pass. The initial touch runner passed rootfull assertions, then MSVC reported LNK1104 opening its temporary executable for the TrollStore variant. The unchanged runner passed both variants on rerun; no touch source changed. New Foundation/GCD/ARC/ASan/UBSan additions have not executed on Windows and require macOS CI. No device latency, memory or power measurement is claimed.

## Remaining work

Shared license HTTP cancellation/coalescing is unchanged. The permission block and reply remain queued until the supervisor reaches the request; no queue capacity limit, immediate dequeue, deadline inheritance or active-work preemption is added. Existing helper timeouts, fallback sleeps, sockets, direct waiter and auto-respawn retain their prior limits. Work that wins permission before terminal close can still produce later effects, and expiration does not undo committed service/license changes. Generic permission callbacks must not block the owner queue or assume main-thread execution. Concurrent BGTasks still share last-writer diagnostics. iOS scheduling/suspension, cross-persona termination, device qualification and remaining C06 work stay open; P1-76 is partially addressed.
