# A02 — P1-07 / P1-09 / P1-10

Date: 2026-10-16. Base: `a34b9ac` (A01 build reported passed by the user).
Status: source implemented; native host and source-contract checks passed. New iOS build and device validation pending.

## Scope and changes

This group concerns the global indicator in `pccontrol/TouchIndicator/TouchIndicatorWindow.xm`, built into the rootfull/roothide tweak. TrollStore production uses its own foreground visual-feedback implementation and does not instantiate this class. The excluded prototype `poc-trollstore` tree remains untouched.

- **P1-07:** use direct array slots for finger IDs 0–19. Reject negative/out-of-range IDs before any slot access; validate the full-width HID index before narrowing to int. Show/move coordinates remain CGFloat.
- **P1-09:** give lifecycle state, HID registration and UIKit objects one owner: the main run loop. Public start/stop/reload calls execute inline on main or dispatch synchronously from a background caller. They copy an owned NSError object back only after completion; the caller's NSError** is never captured by deferred work. A task success response therefore follows successful setup.
- **P1-10:** stop transitions to Stopping before unregistering, unschedules on the same run loop and common mode used for registration, releases the Create-rule client ownership, then clears the global pointer. Stop is idempotent and never stops the shared main run loop.
- Per-session generation tags reject callbacks from a previous client after stop/restart. Client/window/configuration startup failure rolls back to Stopped and cleans owned resources; a duplicate start cannot create another client.
- Construct/update/hide the UIWindow and its finger views synchronously on main. Hide clears all slots and hides the window before releasing ownership. No old async UI blocks can resurrect a stopped indicator. Cache the coordinate font per window.
- Preserve task26 actions 0/1/2 (hide/show/reload), default color when configuration is absent during start, and protocol status conventions. Invalid actions/configuration report an error instead of accidentally treating arbitrary text as action 0. Reload still requires a running indicator and an existing config file; valid color changes update visible slots.
- Internal startup errors return through NSError rather than presenting a blocking CFUserNotification on the main owner. Bootstrap can still surface its own startup failure using its existing caller behavior.

P1-08 is **not marked complete**: this removes per-move dispatch backlog and font lookup churn, but formatting/layout still occurs for each accepted move. Display-cadence coalescing and device CPU/frame-latency measurements remain separate work.

## Design limits

The main run loop replaces the old indefinitely parked global-worker run loop. Registration uses `kCFRunLoopCommonModes` so the same owner handles callbacks and UIKit work during normal/tracking modes. The schedule/unregister APIs return no startup completion status, so successful Create/registration is not proof of event delivery on a particular iOS version.

Start/reload configuration reads are synchronous on main and occur only on lifecycle control requests. This trades a small infrequent config read for simple ordering; move handling performs no configuration I/O. Calls from other threads can wait for main-thread availability. Do not introduce a main-thread wait on a background caller that is itself waiting for this operation.

## Verification completed

`node scripts/check-touch-indicator-safety.mjs` compiles the actual production HID ownership core, generation guard and finger guard with C++14 against a test client/run loop. Windows execution used MSVC `/W4 /WX`:

- all valid slots 0–19, rejected -1/20 and extreme integer indices;
- duplicate start leaves the existing client/generation unchanged;
- stop rejects callbacks before unregister/release; registration and unschedule use the same main-loop/mode identity;
- idempotent stop never double-releases; a failed client Create can recover on the next start;
- old-session callbacks cannot be accepted after restart;
- 10,000 repeated start/stop cycles leave zero live test clients, with balanced unregister/unschedule/release counts.

Source checks enforce synchronous main-thread marshaling, error assignment after completion, slot guards before array accesses, complete failure cleanup, and absence of index-1, async UI work and CFRunLoopRun/Stop. The new check runs in the rootfull/roothide build workflow, with ASan/UBSan on macOS.

All 29 existing source-contract checks in that workflow also passed. These host tests do not execute UIKit, Objective-C error transport or the private HID framework on iOS.

## Remaining build/device checks

1. Build the new rootfull and roothide artifacts. A01's reported successful build predates these A02 changes.
2. On a test screen, enable task26 action 1, exercise finger 0 and 19 down/move/up, then action 0. Verify no crash, stuck views or overlay remaining after stop. Exercise physical touches and injected touches in scrolling/tracking modes.
3. Repeatedly show/hide from concurrent clients and during HID activity. Only one active indicator client/window may exist; after stop acknowledgment no old generation may alter a restarted window. Include stop twice, show twice, and reload while stopped.
4. Test missing/malformed config and failed HID-client creation in a diagnostic build, including callers passing a null NSError**. Errors must arrive before the task response and a later valid start must still succeed.
5. Track live IOHID clients and UIWindow/view instances with Instruments across repeated cycles. Verify release balance on the real private API, acceptable main-thread callback cost and absence of persistent worker run loops.

Do not label this group device-validated until target results are available. The next planned group is A03 (capture ownership/failure handling, P1-19).
