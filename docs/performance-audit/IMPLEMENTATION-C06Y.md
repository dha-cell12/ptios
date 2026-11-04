# C06y — owned respawn timer and stale callback refusal

Date: 2026-11-04 (Asia/Bangkok). Baseline: `7b50bf56`; user reported C06x build passed and requested continued implementation. Production StreamControl only; TouchPOC excluded.

## Timer ownership

The previous dispatch-after respawn block could remain queued after a later stop/restart/ensure. Its final autoRespawn/running checks did not distinguish an older respawn request from a newer service lifecycle. An old block could become eligible again when those booleans changed.

Use one resumed, initially unarmed dispatch source on the existing supervisor serial queue. The supervisor owns its source and an object identity for that scheduled respawn. Before effect delivery, require the same identity, retire the source/identity and then apply the existing autoRespawn/running gate. A stale or duplicate callback cannot cancel a newer timer or call spawn. Retiring before spawn also preserves a new timer created by reentrant work.

Cancellation clears ownership, replaces the event handler and cancels the resumed source. Accepted ensure, restart and direct-spawn attempts retire preceding timers after their existing permission/busy gates. Stop retires a pending timer before its busy gate because stopping already disables auto-respawn even when the helper requires retry. A stale PID exit returns before cancellation; an accepted exit retires any preceding timer before updating state and scheduling its replacement.

Preserve C06x's zero-to-three-second continuous throttle, existing owner queue, spawn/gate/log policy and helper/transport/probe behavior. This changes the scheduled resource from an unowned dispatch-after block to a cancellable source. Cancelling an already submitted delivery also relies on the identity check, since cancellation cannot retract a callback already running/queued.

Source/token allocation failure leaves no pending owner and logs that explicit ensure is required. Setup NS/C++ unwind cancels the resumed source before propagation. Spawn exceptions retain the preceding propagation policy, with timer ownership already retired. There is no idle timer or automatic retry after allocation/setup failure.

This token identifies a scheduled respawn, not a kernel process. Direct-child PID-reuse fencing, cancellation of running helper work, whole ensure/restart deadlines, multi-process transactions and device qualification remain open. A pending source may retain its supervisor until delivery/cancellation, as the preceding delayed block did. All source/state operations remain on the supervisor queue. C06/P0-23 stay partial.

## Verification

Freeze the complete preceding supervisor. A restoration removes only owned-respawn fields/methods/call sites and restores the old dispatch-after delivery, then verifies the exact prior file/hash before the C06x/C06u/C06t/C06e/C06c chain. Explicit source guards require each lifecycle cancellation call and its position relative to admission/busy gates. Existing watcher timing/exit fixtures use a controlled scheduling shim; a new fixture compiles the actual ownership methods.

The native ARC/ASan/UBSan fixture compiles those methods with controlled source providers and separately with real GCD sources. Controlled cases cover replaced/cancelled/stale/duplicate delivery, auto-respawn/running gates, source allocation failure, NS/C++ installation/arming/spawn faults, cancellation releasing a weak owner and reentrant scheduling. One thousand fake-source lifecycles require balanced creation/cancellation and zero final fake sources. Thirty-two real serial-queue cycles schedule/cancel/replace zero-delay sources and require one spawn with retired ownership; a delayed source is cancelled without spawning. Only the fixture's spawn counter changes; no real service/process is launched or stopped.

Windows validation: all **84 workflow runners** (36 source, 48 safety), **521 existing workflow source checks**, full preceding-supervisor/earlier checkpoint hashes, lifecycle call-count/order guards, fixture extraction, JavaScript syntax, expanded assert preprocessing and `git diff --check` pass. Existing watcher/helper portable checks also pass focused reruns. Sixteen artifact-only checks skipped. New Apple compilation/native execution/iOS builds require macOS CI. No measured device wakeup/latency improvement is claimed.
