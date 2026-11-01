# C06p — bounded root license reload transport

Date: 2026-11-02 (Asia/Bangkok). Baseline: `e9315a31`; user reported C06o build passed and requested continued implementation. This checkpoint hardens the C06 lifecycle reload edge for rootfull/roothide. Production TrollStore keeps its existing TLinkSocketClient route; TouchPOC excluded.

The root coordinator used blocking connect, per-call two-second socket timeouts, a single send and a single recv. It could reject a partial write, decode an incomplete TCP chunk as a complete reply, or accept a capped prefix. The timeout did not form one budget across connect/write/read.

Reuse the existing nonblocking socket/continuous-clock/connect/wait primitives through a small reload transaction core. Sample one two-second window before socket creation and carry it through setup, connect, exact request writes, response reads and decoder checks. Poll in slices at most 250 ms without renewing the window for progress or EINTR. Keep the endpoint `127.0.0.1:6000` and exact `76reload\r\n` command. Socket ownership handles every return and NS/C++ unwind; prepare checks nonblocking/CLOEXEC/SIGPIPE protection.

Read through LF or true EOF rather than one recv. Preserve the old 8191-byte payload ceiling and CString UTF8/NUL/whitespace decoder behavior. LF within the cap and nonempty EOF frames can complete; timeout/fatal-read prefixes, empty EOF and a cap reached without LF return streamd_no_response. An exact-cap EOF-only response is also refused because the cap was reached without framing; no truncated success is synthesized. A final decoder-time budget check refuses an overdue result. Stage error strings remain socket_create_failed, streamd_connect_failed, streamd_send_failed, streamd_no_response and streamd_invalid_response. Setup failures now fail closed rather than ignoring socket-option errors.

This deliberately changes incomplete/fragmented/oversized/late-response behavior. The original publication/retry scheduling, diagnostics fields/counts, HTTP/signature/lease authority and TrollStore routing are unchanged. A sent reload may commit even if its reply times out; no new internal retry or rollback is introduced. The existing outer retry remains. This is cooperative IO budgeting, not a bound on queue residence, diagnostics/file work, opaque kernel stalls or every caller's end-to-end lifetime. It does not reduce diagnostics writes or implement shared HTTP cancellation.

## Verification

Add the runner to both production workflows using C++14, matching the root app's gnu++14 and TrollStore targets. The portable core includes the actual shared IO headers. A frozen prior reload function and staged complete-coordinator hash preserve everything outside the conditional include/root helper, then run existing C06o/subscriber/C06f guards.

Portable cases cover 100k two-second windows, partial command writes and response chunks, LF/EOF/exact-cap/unframed-cap cases, EINTR, EAGAIN/backpressure, fatal connect/write/read errors, invalid clocks and phase time accumulation. Refused reads return no partial reply payload.

The new macOS fixture compiles the actual root adapter/decoder with controlled transport and real disposable descriptors. It checks Unicode/NUL/invalid UTF8/error replies, exact request bytes, descriptor flags/balanced closes, phase expiry/caps and NS/C++ read unwind. A real nonblocking POSIX socketpair exercises the transaction core's request/response framing; connect admission is controlled there. Neither an installed daemon nor port 6000 is contacted. These Foundation/ARC/ASan/UBSan assertions and the iOS root build require macOS CI/device qualification. No measured device latency/CPU/memory gain is claimed.

Windows validation: **77 workflow runners** (36 source, 41 safety) pass after a focused phase-2 guard rerun. Its initial failure expected the command literal in the old coordinator location; the guard now checks the helper call/include and exact command bytes in the new header. The other 76 runners passed on the full run. All **521 existing workflow source checks**, staged coordinator hashes, fixture extraction, JavaScript syntax, expanded assert preprocessing and `git diff --check` pass; sixteen artifact-only checks skipped. New native assertions were not compiled/executed on Windows.

Remaining work includes other lifecycle/TrollStore transport behavior, cross-process coordination, diagnostics IO/durability, shared HTTP/active-work cancellation, reload retry coalescing and device qualification. C06 remains partial.
