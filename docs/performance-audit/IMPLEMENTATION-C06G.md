# C06g — per-subscriber background refresh cancellation

Date: 2026-10-31 (Asia/Bangkok). Baseline: `1bc3bfa3`; user reported C06f build passed and requested continued implementation. This checkpoint implements part of **P1-76** in the shared application coordinator/scheduler for rootfull/roothide and production TrollStore. TouchPOC excluded.

Status: source and portable regression validation on Windows. New Foundation/GCD/ARC/ASan/UBSan cases require macOS CI; device qualification remains independent.

## Subscriber ownership

Add `subscribeToBackgroundRefreshWithCompletion:` returning an object conforming to `SCLicenseRefreshSubscription`. Keep the existing completion-only API and refresh decision/HTTP/persistence behavior. Each subscription owns its caller completion and a retirement block. Cancel and delivery compete under the subscription monitor; the first winner detaches both blocks. Invoke retirement and any claimed caller completion outside the monitor. Duplicate cancel/delivery has no effect. A delivery that already claimed its completion can finish after cancel returns; cancellation does not preempt running callbacks.

When cancellation wins, it clears the caller completion synchronously. Retirement is dispatched to a dedicated serial queue before acquiring the coordinator monitor, so an expired BGTask does not wait for a held diagnostic transaction to unlink its callback. The registry uses a UUID and an explicitly copied heap block to remove exactly that subscription from the pending refresh completions. Registry removal is eventual; a queued main-delivery wrapper may still execute but cannot claim a cancelled subscription. During monitor contention, lightweight settled tokens can remain queued/registered, without their caller captures. No new registry/queue admission cap is provided.

Normal delivery also retires its registry entry. NS/C++ exceptions during subscription admission cancel and retire before rethrowing; the scheduler's existing exception boundary finishes the task. Admission that already started a shared flight does not roll it back.

## BGTask integration

The scheduler subscribes instead of using the completion-only API and installs subscription cancellation as the per-run cleanup. `TLinkBackgroundTaskRun` detaches cleanup with the timer and completion at the first terminal transition, then cancels the timer and runs cleanup outside its mutex before completion. Cleanup provider exceptions cannot suppress task completion. If expiration/watchdog wins before subscription publication, late cleanup installation cancels it immediately. A nil subscription finishes with `license_refresh_subscription_unavailable`.

Keep existing rescheduling, watchdog duration, diagnostic fields, first-result ownership and C06e supervisor start permission. Already claimed refresh callbacks still pass through the run phase gate; ensure work waiting on the supervisor queue still checks its permission before starting. Active supervisor work is not cancelled.

The shared refresh continues when one or every subscription cancels. Foreground/manual/completion-only callers remain independent consumers; a later caller can join the same flight. Manager result verification, signed persistence and publication may still occur after every background subscriber expires. This checkpoint cancels subscriber interest, not the HTTP transport or shared decision work.

## Verification

Extend the existing lifecycle and background-task runners; no new runner is added. Complete-source reversal/hash guards preserve the pre-C06g coordinator/public header, scheduler and run owner, then retain the preceding C06f/C06e/C06d guards. Update the workflow scheduler-selector check to the new API; its coordinator compatibility check remains.

New native cases use the actual subscription implementation and complete current coordinator/scheduler with controlled providers and private temporary diagnostics:

- Two hundred cancel/delivery races, duplicate settlement, callback/retirement/destructor reentry, capture release and an already claimed callback finishing after cancellation.
- Cancel one subscriber among active/nil-completion/legacy consumers, cancel after main delivery is queued, all subscribers cancelled, a later legacy join, skip and busy-operation results. Check exact callback/registry retirement while the shared manager request and publication retain ownership.
- Cancel while the coordinator monitor is held: release caller captures without waiting, then drain eventual registry removal. NS/C++ admission faults before and after shared-flight admission leave no subscriber entries/callbacks.
- Expiration/watchdog before subscription return, nil subscription, delivery followed by expiration, late/duplicate provider callbacks and cleanup publication after terminal state. Cleanup reentry and NS/C++ faults retain one task completion.

Windows validation: all **74 workflow runners** (36 source, 38 safety), **521 workflow source checks**, JavaScript syntax, expanded assert preprocessing and `git diff --check` pass. Two initial runners passed their assertions but encountered temporary executable-unlink EPERM; focused reruns passed. Sixteen artifact-only checks are skipped. New Apple Foundation/GCD/ARC/sanitizer assertions have not executed on Windows.

## Remaining work

P1-76/C06 remain partial. Shared HTTP/decision/diagnostic IO lacks a new end-to-end deadline, transport cancellation and admission cap; a manager that never replies can retain a flight. Registry unlink can wait behind coordinator work, and main-delivery wrappers cannot be removed from GCD. Already claimed callbacks and admitted supervisor work are not preempted. Active supervisor cancellation/coalescing, remaining diagnostics IO, signed-artifact crash recovery and device/performance measurements stay open. No measured latency, RSS, power or syscall improvement is claimed.
