# C06r — script-bound direct helper cancellation

Date: 2026-11-02 (Asia/Bangkok). Baseline: `9a6a9be3`; user reported C06q build passed and requested continued implementation. This checkpoint adds caller cancellation to the direct short-lived privhelper path in production TrollStore streamd. TouchPOC excluded.

## Synchronous caller binding

Bind the exact script session around synchronous script task dispatch using a stack-owned stop scope and a thread-local pointer to its borrowed Stop object. The scope retains that session, restores an outer scope on return/NS/C++ unwind, and releases the retained session after restoring the pointer. It does not consult the global current-script slot, and the reaper never retains the stop predicate/session.

Route the generic structured script task entry and six direct JS task call sites through the wrapper. Only helper-reachable tasks 11/24/31/54/59/72 create a live stop binding. Task 74 installs a no-stop binding because confirmed respring intentionally stops the script before invoking its helper; ordinary authority and confirmation gates still apply. Other tasks dispatch directly without the extra scope/session retain, preserving the touch and non-helper cleanup fast paths.

This binding applies only to the synchronous same-thread call chain. External calls without a binding keep the original policy even while a script is stopped. It is not automatic context propagation to other queues, network backends or asynchronous clipboard restoration.

## Helper cancellation and retirement

Copy the current borrowed Stop at helper entry. Check before path/admission work, immediately before spawn, inside the existing child wait and after completion before interpreting success. Cancellation returns the new private helper code -109. Wrap the final stop/spawn/adopt section in finally so an early return/unwind there still frees argv. Existing argument construction/allocation failure policy is otherwise unchanged.

Keep C06q's four-child process cap, duration policy, TERM/KILL grace and late reaper. A stopped child that cannot retire retains its slot, but not the script session/callback. A terminal child is retired before a subsequent stop check. Cancellation can refuse a late successful result; it cannot undo an already committed app/service effect. There is no replay or rollback.

Task consumers retain their existing response formatting. Some consumers report helper failures inside an otherwise successful legacy envelope; this change does not add a blanket JS result override. Other error codes, authority/argv/spawn/fallback behavior, the separate VPN configuration stop API and non-helper tasks remain. Preflight/spawn/opaque IO cannot be preempted; full end-to-end cancellation and cross-process coordination remain open. C06 is partial.

## Verification

Keep the complete prior C06q helper as a frozen fixture. A staged restoration removes only the scope/prototype/seven call-site bindings and helper changes, verifies the entire prior streamd hash, then executes the C06q/C06b guards. The existing portable child policy and actual timeout-expression probes remain.

A portable C++ probe compiles the actual scope/wrapper with only Objective-C bridge casts/types replaced by plain C++ substitutes. It checks nested restoration, C++ unwind, non-helper bypass and respring exemption; it does not test ARC. The macOS fixture compiles the actual script stop function, scope/wrapper and direct helper, with task dispatch controlled. It adds stopped/nil-session preflight, stop during path/argv preparation, stop during a real disposable child wait and immediately after spawn, nested old/fresh session isolation, independent-thread external calls, NS/C++ wrapper unwind, cleanup bypass, respring and weak session lifetime. A synthetic unreapable child verifies pending ownership survives while the caller session is released. No privileged helper, app, URL, data or service is touched.

Windows validation: all **77 workflow runners** (36 source, 41 safety), **521 existing workflow source checks**, staged hashes, fixture extraction, JavaScript syntax, expanded assert preprocessing and `git diff --check` pass. The helper runner also passes focused final reruns after fast-path/preflight adjustments. Sixteen artifact-only checks are skipped. New Foundation/ARC/sanitizer and iOS execution require macOS CI; no device performance/cancellation-latency measurement is claimed.
