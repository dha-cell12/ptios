# C04g — captured caller stop in VPN client IO

Date: 2026-10-30 (Asia/Bangkok). Baseline: `1d4de324`, C04f build passed according to the user. Complete normalized Connectivity source SHA-256 before this change: `ab932187d09fb6528f82239ad07a7e26553e8761a7a428a0b271fcfade161506`.
Status: **user reported the C04g working-tree build passed before C04h (HEAD still `1d4de324`, the C04f commit); independent device qualification pending**.
Finding: **P0-19/P1-63 caller-to-client cancellation portion**. Broker operation cancellation and outer IPC isolation remain open.

## Change

C04f bounded socket waiting to 30 seconds, but that local window did not observe a caller that had already stopped. A cancelled script or an earlier native parent deadline could still leave its synchronous VPN client waiting until the socket deadline.

Capture the current shared native budget once at client entry. A stopped caller is refused before socket creation. Supply a synchronous borrowed predicate to the existing bounded IO adapter. Observe the captured budget's stopped state at clock/deadline checkpoints, before send/receive and after each poll, so cancellation, inherited native deadline and output-limit exhaustion stop further waiting. Pending polls retain C04f's maximum 250-ms slice; a cancellation occurring while a poll sleeps is observed when that poll returns, subject to scheduling and syscall behavior. No extra thread, timer or watcher is created.

Keep native and continuous-clock domains separate. The adapter queries native stopped state rather than converting the native steady-clock deadline into the continuous-clock epoch. The independent continuous 30-second ceiling remains. Hold the shared budget for the invocation; nested providers changing TLS cannot replace that captured caller. Adapter context and window remain borrowed only while the synchronous function executes, and no callback escapes with their pointers.

Normal socket ownership closes on each stop return and on unwind. Existing phase labels remain: a pre-stopped caller/connect failure uses vpn_broker_unavailable, write rejection uses vpn_broker_send_failed and read rejection uses vpn_broker_no_response. The typed task entry still checks its native budget after the call and uses its existing stop reply. Preserve complete request/response framing, decoder, endpoint, license gates, diagnostics fallback, radio cores and broker source. Already written request bytes are neither replayed nor rolled back. No caller budget means the C04f behavior; cleanup budgets retain their existing native reason policy, without adding any authority exemption.

Rootfull/roothide Connectivity is covered. Production TrollStore clients and TouchPOC are unchanged. Closing this client sooner does not prove the broker's operation ended; C04e retains its pending ticket until completion evidence.

## Verification

The existing client runner adds a complete C04f source/hash reversal for only the captured-budget preflight, predicate binding and include. Earlier full-source C04f and frozen decoder guards remain, and runtime extraction still uses the actual current client function.

The portable suite retains all 100,000 window/connect/IO cases and adds actual native-budget cases: no backend connect/send/read after pre-cancellation; cancellation during connect, connect completion, send, receive and a stalled poll; one-poll cancellation observation; inherited parent deadline and output exhaustion; captured parent state while a different TLS budget is active; unchanged cleanup/null policy; and 1,000 concurrent token publications. Native cancellation/reason code is exercised directly rather than replaced with a Boolean fixture.

The Foundation fixture retains frozen transport parity and real loopback tests. New actual-function cases verify pre-cancel/deadline/output refusal before opening an FD, cancellation inherited through a child budget in every IO phase, one-poll exit, exact descriptor balance, no response reads after cancelled writes and no replay of committed bytes. A provider leaves a different TLS budget active through post-receive checking to confirm that the captured caller still controls admission. The fixture restores nested/outer scopes and checks cleanup policy and final empty TLS. New runtime cases require macOS CI and were not run on Windows. No real VPN, profile, radio or license state is changed.

Windows validation: 68 workflow runners (36 source checks, 32 safety runners), 521 existing workflow source checks, expanded assert preprocessing including the updated fixture and git diff --check pass after focused H264/image-storage reruns. Both initial cores passed their assertions but Windows denied removal of their temporary executables; the unchanged runners passed on retry. Sixteen artifact-only checks are skipped. No device stop-latency, memory, power or throughput improvement is claimed.

## Remaining work

Caller stop is cooperative at IO checkpoints, not syscall/Foundation preemption or a strict stop-latency guarantee. The caller's existing cleanup and diagnostic fallback policies are preserved; this stage does not redesign the entire task pipeline. No cancellation command/deadline is sent to the broker, and committed VPN effects/operations may outlive the client. The outer IPC callback is still synchronous, its shorter timeout still differs from the client/broker windows, and IPC isolation, manager cancellation/coalescing, disconnect propagation, production TrollStore transports and real device/sleep/backend qualification remain open. C04/P0-19/P1-63 are not fully closed.
