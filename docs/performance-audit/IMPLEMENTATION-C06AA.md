# C06aa — bounded supervisor ensure admission

Date: 2026-11-04 (Asia/Bangkok). Baseline: `bdb05d57`; user reported C06z build passed and requested continued implementation. Production StreamControl only; TouchPOC excluded.

## Admission before enqueue

Each ensure call previously retained another owner-queue block, permission predicate and completion while a slow helper/probe could keep the serial queue occupied. There was no bound on active plus queued ensure requests.

Give each supervisor instance an admission state with eight slots. Acquire a lease before enqueueing owner work. Excess requests receive `NO, supervisor_ensure_queue_full` asynchronously on main without running or retaining their startPermission on the owner queue. A nil-completion refusal logs explicit retry. No automatic retry or worker is created for a refused request.

Accepted work retains its lease through queue residence and execution. Release it before posting permission/helper-busy refusals or a normal completion, so completion reentry can use the freed capacity. A stack scope releases on normal nil-completion return or unwind even if GCD still retains the job block. Lease release is atomic/idempotent; later scope/destructor releases cannot decrement twice. The state has no caller/coordinator capture and stays alive through shared leases.

Preserve the existing startPermission timing on the owner queue, admitted ensure/probe/helper/fallback/timer effects, callback fields/main delivery and exception propagation. This is a count bound, not coalescing, a queue-residence deadline or active cancellation. Completion blocks already posted to main are outside the admission count. Helper-child/reaper quotas and busy fences remain independent and charged under their preceding policy even after ensure work returns. Stop/restart and other owner commands are not covered by this cap.

The public method signatures remain, with a header comment documenting capacity/refusal. A saturated caller must explicitly retry. Whole-operation deadlines, supervisor cancellation/coalescing, multi-instance/process coordination and device qualification remain open. C06/P0-23 stay partial.

## Verification

Freeze the complete preceding supervisor. Restore the include/field/init, admission prefix, stack scope and explicit releases; compare the complete preceding ensure body and full file/hash before the C06z/C06y/C06x/C06u/C06t/C06e/C06c chain. Header restoration removes only the new capacity comment before the prior API hash guard.

The portable runner compiles the actual admission/lease/scope types and checks eight-slot saturation/recovery, retained tickets after release, 100k lifecycles, exception unwind, null-state refusal, per-instance isolation, 160k attempts from sixteen threads and simultaneous duplicate release. All final admission counts must be zero.

Extend the existing complete current/frozen supervisor fixture in `check-supervisor-helper-safety.mjs` rather than compiling a duplicate supervisor. New native Foundation/GCD/ARC/ASan/UBSan cases hold the real owner queue and separately hold an active provider, admit eight requests, require an independent ninth main-queue refusal and verify no rejected permission capture remains. They check release-before-completion reentry, nil-completion refusal, drain/recovery and NS/C++ unwind while the job block remains retained. Existing permission/expiry/helper cases continue to run. A controlled owner-enqueue adapter is used only for catching injected owner-work exceptions; ordinary cases use real GCD. Provider effects are controlled and these additions launch/stop no real service.

Windows validation: all **86 workflow runners** (36 source, 50 safety), **521 existing workflow source checks**, complete previous-supervisor/earlier checkpoint hashes, header restoration, JavaScript syntax, expanded assert preprocessing and `git diff --check` pass. Focused admission/helper runners pass, including the actual portable admission types. Sixteen artifact-only checks skipped. New Apple native execution/iOS builds require macOS CI. No measured device latency or memory gain is claimed.
