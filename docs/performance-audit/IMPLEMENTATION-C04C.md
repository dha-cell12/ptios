# C04c — accepted-time VPN broker request ingress

Date: 2026-10-30 (Asia/Bangkok). Baseline: `127580fb`, C04b build passed according to the user. Complete normalized broker source SHA-256 before this change: `6d29f36a4e5898860201eef7223b6f077f663b24170bfb5bc6465a2fff524930`.
Status: **user reported build passed at `dd0dae9d` before C04d; independent device qualification pending**.
Finding: **P1-63/P0-19 request ingress portion**, not an end-to-end VPN timeout.

## Change

The broker's 30-second SO_RCVTIMEO previously applied to each blocking recv. A client sending occasional bytes could keep one of eight client leases for much longer. Sample the process continuous clock at admission entry, immediately after accept, and store that sample in the existing lease. Every worker uses one fixed 30-second request window derived from this sample. Queue residence consumes that same window. Expired queued clients perform no socket read or command dispatch; invalid or regressed clock samples fail closed.

Read chunks using recv with MSG_DONTWAIT, followed by the existing deadline-aware poll helper when not ready. Check the fixed window before and after each receive, retry EINTR/EAGAIN without renewing it, and reject fatal read faults or expiry rather than dispatching accumulated partial bytes. Check the window again after UTF8 command preparation, immediately before entering the unchanged response dispatcher. The old 256-byte chunk size, 1,024-byte cap, whole-chunk LF behavior, fast EOF/half-close input, UTF8 fallback and command normalization remain. In particular, this stage does not introduce a new mandatory-newline protocol.

MSG_DONTWAIT affects only the individual read operation. It does not switch the descriptor's global blocking mode, so the existing send loop and response behavior remain. Keep eight-slot admission, exact-once FD/slot cleanup, exception containment, ordinary authority gates, manager calls, diagnostics, 8/24-second manager waits, relative output timeout and listener configuration. Close a failed ingress using the existing lease; no new timeout wire response is sent. Rootfull/roothide port 6014 is covered; production TrollStore listeners are separate and unchanged. TouchPOC is excluded.

## Verification

The existing broker safety runner now compiles the production portable ingress helper on every host. It reverses only this stage's include/window/read/gate/timestamp changes and compares the complete result with a frozen C04b file and SHA-256. All earlier full-source admission/authority/parser/output guards remain. Both workflows already run this runner.

The portable suite covers 100,000 queue-age boundary cases, 0–1,100-byte requests under three receive sizes, unchanged whole-chunk LF/EOF/NUL/1,024-byte behavior, 1,000 byte-at-a-time deadline cases, receive and poll EINTR/EAGAIN, stalled sockets, fatal faults, a byte/EOF delivered at expiry, late poll readiness, invalid counts, unavailable/regressed clocks and uint64 saturation. Expired or faulted chunks expose count zero; no partial success is reported.

The Foundation fixture compiles the actual current handler/enqueue code rather than a reconstructed previous stage. It retains C04b's real-socket/GCD ownership, frozen parser parity, exception, FD-reuse and 8,000-client admission cases. Their clocks are held fixed to isolate them from CI scheduling load. New cases control admission/read/decoder time to check expired queued clients, regressed/unavailable clock samples with zero reads, a real MSG_DONTWAIT receive plus real poll with one millisecond left, trickled input and decode-time expiry with zero response-provider calls, fatal partial-read refusal, capacity recovery and a fresh successful request. Existing CF/manager/authority behavior remains protected by the complete source comparison; no real VPN/profile/license state is changed.

Windows verification passed: all 67 workflow runners (36 source checks, 31 safety runners), 521 existing workflow source checks, the new portable ingress suite, expanded assert preprocessing and `git diff --check`. Sixteen artifact-only checks are skipped. The new Foundation/POSIX/GCD/ARC/sanitizer runtime requires macOS CI and was not executed on Windows. These tests establish policy and ownership, not measured device latency.

## Remaining work

This is a request ingress deadline. Once the request enters the response dispatcher, license work, manager initiation/wait/completion, encoding and response writes keep their existing behavior; this is not a 30-second bound on the entire worker or an operation cancellation mechanism. A queued expired lease is released when its worker gets scheduled, not by a new timer. Synchronous IPC head-of-line blocking, late completion synchronization/operation admission, output deadlines, slow readers, TrollStore admission and device qualification remain open. P0-19/C04 are not closed.
