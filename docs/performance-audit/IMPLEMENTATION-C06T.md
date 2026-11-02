# C06t — supervisor task transport deadline

Date: 2026-11-02 (Asia/Bangkok). Baseline: `f8184b2b`; user reported C06s build passed and requested continued implementation. Production StreamControl only; TouchPOC excluded.

## Shared transaction window

`sendLocalTaskLineLocked:timeout:` runs synchronously on the supervisor lifecycle queue for status, hello and shutdown. Its previous receive/send socket timeouts applied separately to kernel calls, its connect was blocking, and it ignored partial sends. A peer producing repeated short reads could extend queue occupancy beyond the requested timeout. A read fault/timeout could also return a nonempty partial prefix as a response.

Use the existing nonblocking/CLOEXEC/SIGPIPE-safe socket owner and bounded continuous-clock connect/write/read primitives. One window starts before socket allocation and covers setup, command encoding, connection, exact writes, reads and final UTF8 decoding. All existing call sites retain their one- or two-second budgets; nonpositive values retain the one-second default. Larger private-method inputs saturate at 30 seconds without integer multiplication overflow. No clock-domain fallback is added.

Keep `127.0.0.1:6000`, the supplied command and newline normalization, UTF8 C-string/NUL command behavior, complete read chunks and the length-based UTF8 result decoder. Preserve ordinary LF/EOF replies, whitespace and embedded response NULs. Nil/unencodable input now fails closed instead of reaching `strlen(NULL)`. An error, expiry, empty EOF or unframed capped prefix returns nil. A newline-terminated reply may occupy exactly 64 KiB; buffers cannot exceed that limit. The preceding reader could append beyond its nominal 64-KiB threshold by a final 2048-byte chunk, or accept an exact-cap EOF prefix. Those oversized/unframed boundary cases are now refused.

The descriptor closes on every return and NS/C++ unwind. Existing probe interpretation, service/version/path policy, helper ownership, fallback, retry, stop/restart, watchdog and delegate behavior are unchanged. The lifecycle queue still waits synchronously. The deadline applies per task transaction, not the entire multi-probe ensure/restart operation or its queue residence. Opaque allocation/encoding/kernel stalls cannot be preempted. A shutdown command may commit before its reply times out; there is no rollback, replay suppression or new cancellation/coalescing. C06/P0-23 remain partial.

## Verification

Freeze the complete preceding method. A staged reversal checks the entire prior supervisor SHA256 and feeds the existing C06e/C06c guards. Add a safety runner to root and production TrollStore workflows. The existing complete supervisor native fixture imports the new transport header and compiles with C++14, matching the production target; its helper/lifecycle assertions remain.

Portable cases execute the actual transport core with controlled IO: 800k timeout plans including integer bounds, partial writes for hello/status/shutdown, EINTR, LF/EOF/64-KiB boundaries, empty/error replies, connect/write/read consumption of one budget, backpressure and trickled responses that cannot renew the deadline.

The macOS ARC/ASan/UBSan fixture compiles the complete actual and frozen methods with controlled network/clock providers and real descriptor allocation/flags/cleanup. It compares healthy commands/replies, newline normalization, Unicode, NUL, whitespace and EOF/empty responses; checks setup/connect/write/read/trickle/cap failure and NS/C++ unwind; and executes the core over a real nonblocking POSIX socketpair. It never contacts an installed daemon, port 6000 or a privileged helper. Actual endpoint policy is checked in source and the frozen connect adapter.

Windows validation: all **79 workflow runners** (36 source, 43 safety), **521 existing workflow source checks**, full-supervisor/earlier checkpoint hashes, fixture extraction, JavaScript syntax, expanded assert preprocessing and `git diff --check` pass. Sixteen artifact-only checks skipped. Apple compilation/native execution/iOS builds require macOS CI. No device latency or throughput gain is claimed.
