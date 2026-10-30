# C06d — BGTask terminal admission and watchdog ownership

Date: 2026-10-31 (Asia/Bangkok). Baseline: `c999a8f7`; user reported C06c build passed. Complete normalized scheduler baseline SHA-256: `7c3e43108982f4ebf077b1987a685906b78245d3babbd98505a35f1ffbef47c3`.

Status: source validation on Windows; new complete scheduler Foundation/GCD/ARC/ASan/UBSan runtime pending macOS CI and independent device qualification. Addresses part of **P1-76** in the production StreamControl scheduler. TouchPOC is excluded.

## Change

The existing finished dictionary prevented duplicate BGTask completion, but did not stop a late license callback from submitting another supervisor ensure. Late ensure completions could also overwrite license diagnostics after expiration/timeout. An uncancellable dispatch_after retained completion/task captures for the full twenty-two-second window, and the expiration handler retained its own task through the finish block.

Add a mutex-protected per-invocation owner with Ready, Refreshing, Ensuring and Finished phases. Admission permits one refresh and one ensure, only in that order while active. Completion, expiration and watchdog race through the same terminal transition. A callback arriving after terminal close cannot admit an ensure; duplicate license callbacks cannot submit a second ensure. A supervisor result arriving after terminal close cannot publish license diagnostics or complete again. Each BGTask has its own owner; a closed old run's retained callbacks cannot act through a newer run.

Replace dispatch_after with a resumed, initially unarmed, one-shot GCD source. Publish it to the owner, install expiration, then arm the existing twenty-two-second watchdog. Timer publication after terminal close cancels immediately; arm and close are serialized. After expiration-handler assignment, clear it again if completion won during assignment. This covers a terminal callback racing the handler's publication without holding the state mutex across an external setter.

The winning finish detaches timer and completion captures under the mutex, then clears the timer event handler and cancels the source before completion delivery. Delivery clears task.expirationHandler before setTaskCompletedWithSuccess. Retained late provider/expiration/timer callbacks may keep the small finished token, but no longer retain the BGTask through its completion closure. Release and delivery are outside the mutex so reentry does not deadlock. This removes retention until the original watchdog deadline after an early completion; GCD cancellation acknowledgement may still occur later.

The winning supervisor completion includes the existing license result/detail in the same diagnostics update as the task result. Healthy final fields, success=licenseSuccess && running, failure detail fallbacks, and ensure-after-license-failure policy remain unchanged. Registration identifiers, fifteen/thirty-minute rescheduling, request requirements, initial running diagnostics, mode and diagnostics storage implementation are preserved by full-source reversal. Diagnostics update count/timing changes from two writes to one on normal completion; no device IO improvement has been measured.

Timer allocation failure reports background_task_watchdog_unavailable before starting refresh. Synchronous NS/C++ setup/refresh or ensure-provider exceptions finish with fixed failure details and retire installed resources. A released scheduler reports background_scheduler_unavailable when a later active refresh callback arrives. This is not a general guarantee against allocation failure, exceptions from BGTask completion/diagnostics themselves, or an unresponsive external call.

## Verification

Both workflows run check-background-task-safety.mjs. The source guard reverses only the new include and marked handler body, reproducing the entire preceding scheduler and its fixed SHA-256. Registration, scheduling, diagnostic persistence and the handler preamble therefore retain their complete prior source.

The new macOS fixture compiles complete current and frozen scheduler implementations against controlled BGTask, license and supervisor providers. Diagnostics are overridden in memory; no production plist, HTTP request, service or actual iOS BGTask registration is touched. GCD sources are real, resumed once and joined through cancellation acknowledgements. Controlled deadlines avoid twenty-two-second sleeps; one case exercises real timer delivery with a shortened timer adapter.

Cases include forty-eight frozen refresh/processing, coordinator-present/absent, success/failure and terminal scenarios; duplicate license/supervisor callbacks; retained expiration/watchdog callbacks; expiration before and after ensure admission; unchanged diagnostics after terminal close; independent old/new runs; source allocation failure; expiration during handler installation; NS/C++ provider faults and late recovery; early task release despite retained callbacks; scheduler release; two hundred owner admission/finish races; sixty-four actual refresh/expiration callback races; reentry; late timer publication; and 128 balanced source/task lifecycles. No HTTP or supervisor cancellation is simulated as a production capability.

Windows validation: all **73 workflow runners** (36 source, 37 safety) pass, with no failed runners. All **521 existing workflow source checks** pass; sixteen artifact-only checks are skipped. JavaScript syntax, expanded assert preprocessing and git diff --check pass. These checks do not compile or execute the new Foundation/GCD/ARC/ASan/UBSan fixture; that requires macOS CI.

## Limits and remaining work

Admission linearizes against terminal close. If refresh or ensure claims admission first, expiration can occur before the subsequent provider call actually begins. That already admitted work can continue, including supervisor work waiting on its own serial queue. No mutex is held across a provider call or synchronous callback. This phase suppresses callbacks admitted after close; it does not implement provider preemption, a cancellation-aware supervisor queue, or an absolute no-side-effects-after-expiration guarantee.

The license coordinator's shared refresh/HTTP request is unchanged and can outlive the BGTask; per-subscriber cancellation and its interaction with other callers remain open. Supervisor active waits, queued work, auto-respawn, coalescing and operation deadlines also remain open. Timeout does not roll back committed license/service effects, and it never replays a refused result. Concurrent BGTasks still share last-writer diagnostics without a global generation policy. iOS scheduling, suspension, priority, real twenty-two-second timing, device lifetime/performance and the rest of C06 require separate qualification. P1-76 remains partially open.
