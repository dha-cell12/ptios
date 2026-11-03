# C06w — bounded StreamControl app task client

Date: 2026-11-03 (Asia/Bangkok). Baseline: `913a8867`; user reported C06v build passed and requested continued implementation. Production StreamControl only; TouchPOC excluded.

## One transaction deadline

The production app's `TLinkSocketClient` is used by license reload and several UI task requests. Its preceding connect was blocking, send ignored partial writes, and receive/send socket timeouts applied separately to each syscall. Trickle input could hold the C06v reload flight beyond its nominal two seconds, and a fault/timeout after a nonempty prefix could become a response.

Use the existing nonblocking/CLOEXEC/SIGPIPE-safe descriptor owner and bounded continuous-clock IO primitives. One window spans setup, command encoding, connect, exact writes, reads and final UTF8 result acceptance. LF or a nonempty EOF completes an ordinary response; a timeout/error never completes a prefix. Keep whole returned chunks, including the first LF and any bytes following it in that chunk, as before.

Existing callers use 2–8 second values, which remain. Nonpositive finite timeouts retain the five-second default; positive fractional durations round up to the next millisecond. Nonfinite durations return `invalid timeout` before opening a socket. Larger values saturate at 30 seconds before integer conversion. This replaces undefined nonfinite/out-of-range casts and avoids renewing the deadline across phases or short reads. Opaque allocation, encoding or kernel stalls cannot be preempted; this is not a hard bound on arbitrary native code.

## API and framing

Keep the public header, `requestTask` codec, task/argument concatenation, `127.0.0.1:6000`, newline normalization, UTF8 C-string command/NUL behavior and length-based UTF8 response decoding. Whitespace, embedded response NUL, LF/EOF success and `non-utf8 response` remain. Nil/unencodable commands now fail closed instead of reaching `strlen(NULL)`.

Socket/connect/no-response diagnostic prefixes remain, with captured native errors instead of dependence on ambient errno. A failed exact write now returns `send failed errno=…`. Empty EOF reports zero native error, expiry uses ETIMEDOUT and an unframed cap uses EMSGSIZE. Buffers cannot exceed one MiB. A LF-terminated response may occupy exactly that limit; unframed exact-cap EOF and the old final-chunk cap overshoot are refused.

The void fire-and-forget method uses the same exact-write path under one two-second window and closes without reading. It still has no reply/commit acknowledgement and can commit before a timeout. The unused private `connectSocketWithTimeout:error:` selector is removed; its callers now use the scoped transaction helper. Public methods and all ordinary callers remain unchanged.

Descriptors close on every return and NS/C++ unwind. No worker thread, retry, cancellation, global client admission or new daemon behavior is added. C06v coalescing now uses this bounded production TrollStore transport; its coordinator source, pending/retry policy and publication effects remain. Root coordinator transport remains C06p. Per-caller queue residence, a whole-flight budget under continuing publications, cross-process transactions and device qualification remain open. C06/P1-77 stay partial.

## Verification

Freeze the complete preceding client class. Restore the original connection/read/send methods and remove only the new helper/include to verify the exact previous file and SHA256, including the unchanged requestTask codec/imports. Add the runner to root and production TrollStore workflows; fixture extraction runs on Windows.

Portable tests exercise the actual IO core: 100k fractional/default/saturated windows, NaN/infinity/tiny/large inputs, exact partial writes, no-read completion, LF/EOF/empty/one-MiB boundaries, connect/send/read faults, trickle/backpressure and shared phase-time consumption. The new native ARC/ASan/UBSan fixture compiles complete current/frozen classes with controlled transport, real descriptor allocation/flags and Foundation codecs. It compares public APIs, task arguments, Unicode/NUL/whitespace/LF/EOF/error outputs, exact fire-and-forget and NS/C++ resource cleanup. Real nonblocking POSIX socketpairs exercise reply, no-reply and a silent-peer deadline. No installed daemon, port 6000, privileged helper or license state is contacted/changed.

Windows validation: all **82 workflow runners** (36 source, 46 safety), **521 existing workflow source checks**, complete prior-client restoration/hash, fixture extraction, JavaScript syntax, expanded assert preprocessing and `git diff --check` pass. Sixteen artifact-only checks skipped. New Apple compilation/native execution/iOS builds require macOS CI. No measured device latency or allocation improvement is claimed.
