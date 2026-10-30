# C04f — fixed VPN client socket budget

Date: 2026-10-30 (Asia/Bangkok). Baseline: `038d1f03`, user reported build passed including C04e and the storage-json fixture keyword correction. Complete normalized Connectivity source SHA-256 before this change: `43bd81226ed03494388cef5d302fe8fe3255aa19676516cebd972b29bcf36219`.
Status: **user reported build passed at `1d4de324` before C04g; independent device qualification pending**.
Finding: **P0-19/P1-63 client transport portion**. Synchronous outer IPC isolation is still open.

## Change

The SpringBoard VPN broker client used blocking connect and separate 30-second socket timeouts. Each successful receive could start another wait, allowing a small trickle of response bytes to hold the calling thread far longer than 30 seconds. Receiving an error after a prefix could also fall through and parse the incomplete prefix as a successful response.

Start one continuous-clock 30-second window before socket creation. Use the existing scoped socket owner to prepare O_NONBLOCK, FD_CLOEXEC and SO_NOSIGPIPE. Nonblocking connect handles EINPROGRESS/EALREADY/EINTR through writable readiness, SO_ERROR and getpeername. Exact request writes and every response chunk use the same deadline. EINTR/EAGAIN retries and byte progress never renew it. Limit each poll to 250 ms and recheck continuous time, including after sleep and late readiness. Invalid or regressed clocks fail closed. Check time before accepting decoded response text as well.

Keep the loopback destination 127.0.0.1:6014, CRLF requests, existing command/authority/parser/diagnostics behavior and all response success/error decoding. Preserve normal whole-chunk LF and real EOF framing. At the existing size boundary, stop after exactly 1 MiB; the old loop could overshoot by up to 4095 bytes when prior reads were short. The cap remains a legacy completion boundary without introducing a new response schema. On timeout or a fatal receive error, discard any accumulated prefix and return vpn_broker_no_response. A prefix ending in real EOF still follows the old decoder. Partial output to the broker is not replayed.

Keep stage-specific error labels: socket creation/preparation failure uses vpn_broker_socket_failed, connect failure/expiry uses vpn_broker_unavailable, write failure/expiry uses vpn_broker_send_failed, and read/decode expiry uses vpn_broker_no_response. Successful calls leave a supplied error pointer unchanged, as before. RAII closes the descriptor on every return and on NS/C++ unwind; the normal path still closes before decoding.

Rootfull/roothide Connectivity is covered. Production TrollStore foreground/agent clients and TouchPOC are unchanged. This client window is local to its invocation; it does not pass an absolute deadline to the broker or cancel manager work on disconnect. C04e's pending-operation admission remains responsible for outstanding broker submissions.

## Verification

New check-vpn-client-io-safety.mjs runs in both workflows. It replaces only the current transport function/include with its frozen predecessor, then checks the complete Connectivity source and its SHA-256. The final success/error decoder is independently compared byte-for-byte. The old native bridge transport guard now verifies that same frozen pre-C04f transport; actual transport is covered by the new full-source guard and runtime extraction. Existing typed VPN parser/core/task/bridge guards remain. P2's loopback destination check follows the actual shared connect adapter.

The portable suite passes 100,000 fixed-window plans, immediate and pending connect, refusal/completion errors, interrupted/empty/late polls, 250-ms poll slices, invalid/edge clocks, short exact writes, EINTR/EAGAIN, one shared connect/write/read window, trickled and late response rejection, EOF, zero writes and fatal IO. These checks run on Windows with warnings treated as errors.

The new macOS fixture compiles the actual client function and its frozen predecessor with controlled peer IO/time and real scoped descriptors. It compares 180 ordinary/error/EOF/Unicode/NUL/invalid-UTF8/whole-chunk framing cases and exact request bytes, checks nil command/error-pointer behavior, setup/connect/send/read faults, prefix rejection, phase-consumed deadline, stalled/trickled reads, exact fragmented 1-MiB input, NS/C++ descriptor unwind and 128 balanced lifecycles. A separate case uses an actual ephemeral loopback TCP listener, nonblocking connect completion and real request/reply sockets; the destination is redirected only in the fixture. No production broker, profile, VPN, radio or license state is changed. This Foundation/POSIX/ARC/sanitizer runtime was not run on Windows and requires macOS CI.

Windows validation passed: 68 workflow runners (36 source checks, 32 safety runners) after one focused C01 rerun, 521 existing workflow source checks, expanded assert preprocessing including the new runtime fixture and git diff --check. C01's initial assertions passed but Windows denied removal of its temporary executable; its unchanged runner then passed on retry. Sixteen artifact-only checks are skipped. No device latency, memory or power improvement is claimed.

## Remaining work

This is synchronous bounded waiting, not asynchronous IPC isolation. SpringBoard's callback/outer daemon IPC can still be held while the socket request runs; the existing shorter outer IPC timeout remains mismatched. There is no parent cancellation propagation, manager preemption/cancellation/coalescing or rollback of committed effects. Socket setup, Foundation encoding/decoding and scheduling can overrun cooperatively until the next check. The local client and accepted-time broker windows are independent. Production TrollStore transports, real sleep/backend behavior and device qualification remain open. C04/P0-19/P1-63 are not fully closed.
