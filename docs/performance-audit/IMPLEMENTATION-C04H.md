# C04h — dedicated VPN IPC sender and receiver

Date: 2026-10-30 (Asia/Bangkok). User reported the C04g working-tree build passed; HEAD remains `1d4de324`. Preserve all those working-tree changes. Complete normalized pre-C04h source SHA-256: daemon SocketServer `98a399ae2ebed67cf25b0aa6cf36c0769b55730bd0c00b0e5e80f627678c64b3`; SpringBoard IPC receiver `4bd4de54d4e32065d2cb0b22e19ab574c8a4d0fa35dbfc68c2c36ca2628fae26`.
Status: **source/core implemented; new Foundation/CF/GCD/ARC/ASan/UBSan runtime pending macOS CI; independent device qualification pending**.
Finding: **P0-19/P1-14/P1-63 private IPC portion**. The daemon task lane remains shared and is not fully isolated by this stage.

## Change

Task 59 previously used the common serial IPC sender and legacy SpringBoard receiver. Its broker socket wait could therefore hold those owners, and the ordinary CF request wait remained shorter than a legitimate VPN transition.

Route reply-bearing `TASK::59` requests through a dedicated serial sender queue and a new SpringBoard CFMessagePort/run-loop thread, named `com.tlinkauto.tlinkautod.springboard.vpn.v1`. The sender's remote-port cache belongs only to that queue. No marker check or legacy ping is needed for this port. Missing/private-port failure returns vpn_ipc_unavailable; it never retries on legacy IPC. Oversized task-59 requests still select the private route and are rejected as vpn_ipc_invalid rather than escaping to legacy. Other tasks and no-reply routing remain unchanged.

Use message ID 4 and a private TVP1 envelope: four magic bytes, eight big-endian native deadline bytes and the unchanged UTF8 task command. Accept only task 59, no embedded NUL and 8..4095 payload bytes. Expired or more-than-30-second future deadlines fail before task processing. The sender creates a native child budget capped at 30 seconds and inherits any earlier parent deadline/cancellation/output reason. Allocate CF send/receive timeouts from its remaining time, with send at most one second and their sum at most the remaining 30 seconds. This replaces the legacy independent five-second waits for this route.

The private receiver checks the envelope before forwarding to the existing generic handler. That handler decodes the same envelope and installs its deadline in the existing response/native-budget scope. C04g's VPN client then observes that native deadline while retaining its independent continuous socket ceiling. Task parsing, task and broker license authority, response formatting, diagnostics exemption/fallback, profile scope and actual manager calls remain unchanged. A separate atomic admission guard rejects nested private VPN reentry; exceptions return request_failed and release the guard. Source-install failure invalidates/releases the new port. The background owner removes its source and balances CF objects if its run loop exits.

This isolates IPC owner queues/run loops; it does not make the call asynchronous. The daemon's ordinary task work queue is deliberately unchanged, so a network task 59 can still hold later ordinary daemon tasks before they reach any IPC queue. C01 keeps its own sender/receiver. Old clients sending task 59 directly to the legacy port remain supported and can still hold it. Full benefit requires upgrading both daemon and SpringBoard tweak; a new daemon with an old tweak fails closed on the missing private port. No public TCP listener or capability field is added.

Rootfull/roothide is covered. Production TrollStore foreground/agent listeners and TouchPOC are unchanged. Timeout is not evidence that VPN effects ended, and no cancellation message or replay is sent.

## Verification

New check-vpn-ipc-safety.mjs runs in both workflows. Full-source reversal/hash guards remove only the new sender block, two routing hooks, receiver/decode/startup blocks and includes, then compare both complete files with their pre-C04h snapshots. Historical Event Channel guards first reverse those independently guarded additions before retaining their original whole-file digests; actual event runtime extraction remains current. C01, owned-capture and socket callback fixtures import the new shared protocol/queue dependencies so their actual-source compilation stays complete.

The portable suite passes 100,000 envelope/deadline cases, exact task/type/magic/header/4095/NUL boundaries, oversize classification without legacy fallback, parent deadline preservation/cancellation, bounded CF time allocation and nested admission ownership.

The new macOS fixture compiles actual private sender, queue selection, generic handler, private/C01 source installers and legacy sender. Three controllable real CFMessagePort/run-loop owners cover valid/expired/wrong-type/raw envelopes, oversize refusal, source-creation failure, NS/C++ handler faults, nested reentry, healthy wire replies and an intentionally held VPN handler while legacy ping/task and C01 image work continue through their independent owners. It also covers sender timeout without replay, late-handler recovery, a cancelled caller, missing private port and legacy availability after private shutdown. Calls use controlled task bodies and ephemeral port names; no actual VPN/profile/radio/license state is changed. This Foundation/CF/GCD/ARC/sanitizer runtime requires macOS CI and was not run on Windows. Startup/device behavior remains unqualified.

Windows validation passed: 69 workflow runners (36 source checks, 33 safety runners) after updating and rerunning the historical Event Channel reversal, 521 existing workflow source checks, focused VPN/C01/owned-capture/socket/event checks, expanded assert preprocessing and git diff --check. Sixteen artifact-only checks are skipped. No device latency, throughput, memory or power result is claimed.

## Remaining work

Daemon task-lane isolation/admission and earlier queued-time budgeting remain open. A sender without an existing parent starts its 30-second budget when it enters the VPN sender, not when network admission occurred. CFMessagePortSendRequest remains opaque/non-preemptible, so cancellation is checked before/after it rather than interrupting its wait. Parent cancellation is not serialized into the remote envelope; only its deadline crosses processes. Direct legacy callers, mixed-version deployment, startup races, old daemon task ordering, manager cancellation/coalescing, disconnect propagation and real device/sleep/backend qualification remain open. C04/P0-19/P1-14/P1-63 are not fully closed.
