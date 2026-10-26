# C02d5 — bounded helper change waits and publication cursors

Date: 2026-10-26 (Asia/Bangkok). Baseline: `22b449f`; the user reported C02d4 built successfully before this slice.
Status: **user reported build `29858f0` passed before C02d6; independent device/performance qualification remains pending**.
Finding: **P0-12 prerequisite: change publication and wait endpoint before switching the runtime polling loop**.

## Result

The helper exposes an additive protocol-1.0 `waitForChange` command. A started/pinned client can wait for session lifecycle or native-RPC-slot publication using the helper's sequence. The existing production runtime still polls status every 200 ms and opens fresh sockets; adopting this endpoint and reconnect/cancellation handling are the next slice. This change alone makes no idle CPU, socket-count, wakeup or latency improvement claim.

Each helper owns one condition-protected sequence, initially 1. Publication increments it and wakes all registered waiters. Comparison, registration, predicate checks and sleep share one mutex, covering changes between a caller reading its cursor and registering. A cursor behind the current sequence returns immediately; a cursor ahead fails `change_cursor_ahead`. The sequence never wraps: at the exact-JSON integer limit (2^53−1), publication closes the notifier and future waits fail closed until helper replacement. Helper identity scopes all cursors; they are not persistent across helper restarts.

The server captures `changeSequence` before reading the status fields/native slot and returns `changeWaitContract: "session_native_rpc_v1"`. A publication concurrent with or after that read remains observable to a subsequent wait on that cursor. This is a wake hint, not a durable event journal, a replay log, an atomic multi-field status snapshot or a sequence for every metric/log update. Existing status ownership/coherence requires further work before runtime adoption. Callers must read a fresh status after any wait outcome and validate helper/session/native-request identity before dispatching effects. They must derive their next cursor from that status, rather than advancing only from a hint reply.

## Wire and admission

A wait request carries the usual helper/session/transport request IDs, the original C02d4 sender deadline, and a payload containing exactly `afterSequence` and `waitMs`. IDs must be valid nonempty strings of at most 64 UTF-8 bytes. Sequence and duration must be finite, nonnegative integral JSON numbers, excluding booleans/strings/fractions; the duration is 1..750 ms. Missing sender expiry and malformed payloads fail `invalid_wait_request`; old helper/session IDs fail their existing mismatch errors. The public client rejects use before start has bound the helper. There is no automatic retry or silent fallback to another command.

The endpoint briefly obtains the existing timed command owner to validate active session/helper ownership, then releases it before waiting. It retains the original admitted-client socket lease and the earlier accepted/sender deadline. The wait ends by the requested duration or 25 ms before the transport deadline, whichever is earlier. The reserve is an output opportunity, not a delivery guarantee; the normal post-wait/serialization/write deadline checks still apply.

At most four callers may block on the condition. A fifth same-cursor wait returns `change_wait_busy`; already-changed cursors do not consume a waiting slot. This prevents sleeping waiters from occupying all eight admitted clients. Other in-flight reads/writes still share the global eight-client limit, so this is not absolute control-slot reservation or a fairness guarantee. Quiet peer disconnect is retained only until the bounded wait ends; prompt disconnect/caller cancellation remains open. Normal client descriptors, output caps and exception cleanup retain C02d2–d4 ownership. Listener shutdown wakes waits; waiter counts are released on normal, timeout, stop and C++ exception paths.

Replies retain command/request/helper/session correlation and carry `sequence`, `changed` and reason `changed` or `timeout`. Busy, stopped and invalid cursor return correlated error envelopes. Status includes active waiters, limit and maximum duration for diagnostics. The handshake advertises the contract, and old helpers can return unsupported-command errors; there is no production runtime capability negotiation in this slice.

## Publication coverage

Publish after session start/reset, entry into running, stopping/cancellation, license revocation, direct-execution license failure, and terminal lifecycle cleanup. Terminal publication follows native-slot cleanup. Native workers publish when a pending request becomes available, when a reply is consumed, and when timeout/scoped cleanup removes a slot. An unrelated session's cleanup does not publish a false removal. Publication holds no command owner or notifier lock across socket I/O or opaque execution, and the notifier never calls back into RPC/session locks.

The existing serialized socket command handler, license authority/enforcement, first-response-wins slot, native replay ledger and ownership gates remain. No native effect is executed by a wait request. Production TrollStore/TouchPOC execution source is unchanged; both build workflows run the new portable suite and expanded existing macOS fixtures.

## Verification

The new portable runner checks 100000 publication/registration-gap/cursor cases, 80000 concurrent publications, four blocking slots/fifth rejection, simultaneous wake fan-out, old-cursor immediate returns while full, quiet timeout, shutdown and zero final waiters. Existing identity/transport fixtures extract and compile the actual new publication and wait methods alongside their production dependencies.

The expanded macOS transport fixture checks the actual public client and socket endpoint, four sleeping waits plus an independent status request, immediate fifth rejection, changed-before-registration and quiet timeout, helper/session/cursor/strict-payload/deadline gates and shutdown cleanup. The actual native worker fixture waits on its production publication before consuming the pending request, then checks generation advancement on response/cancel cleanup across 100 lifecycles. These Foundation/GCD/ARC/sanitizer paths require macOS CI and have not run on Windows.

All 62 workflow runners (36 source-contract, 26 native), 521 direct workflow source-grep assertions, standards-conforming assert preprocessing and git diff --check pass on Windows; 16 artifact-only checks require CI outputs. iOS/device behavior, saturation recovery, sleep/wake and performance acceptance remain pending.

## Next slice

Qualify this build, then address lifecycle/status ownership and wire the runtime to capability-gated waits using the cursor from the status it actually processed. Preserve replay-before-execution, helper/session replacement fences, deadline/cancel handling and a bounded compatibility path for old helpers. Event waits must not turn hint payloads into native requests or acknowledge an unobserved side effect. Remaining P0-13 adapters, P1-40 invalidation and C01/C02 device/performance acceptance remain open.
