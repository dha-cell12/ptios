# C06b — script cancellation reaches the private VPN helper

Date: 2026-10-31 (Asia/Bangkok). Baseline: `f9cacba2`; user reported build passed after C06a and the queued-completion transition fixture correction. Normalized pre-change request SHA-256: `d8569f97581ab17b181e3fad12ec376f13d32454727bf1749c96fd43fc989bec`; complete TrollStore server SHA-256: `1f77d0902cccfcb4d9d768ee3e4e58a0cbea01f4fb6771417a1cef3484ec82f3`.

Status: source/portable validation on Windows; expanded Foundation/ARC/sanitizer runtime pending macOS CI and independent device qualification. Addresses script caller cancellation within **P0-22**.

## Change

Production TrollStore vpnconf.create/createResult checked script stop before decoding its options, then called the synchronous helper transport without any stop signal. C06a bounded that wait, but stopping or revoking a script during helper work still left it waiting for normal completion or the thirty-second timeout.

Add TLinkVPNRunPrivateConfigurationHelperWithStop with an optional synchronous BOOL block. Preserve the existing function as a wrapper passing nil, so app/vpnagent/other existing callers retain their previous behavior. The script binding passes TLinkScriptStopRequested(strongSession), which reads the exact captured session under its existing monitor and also treats a missing session as stopped. Existing JS preflight, field normalization, lastResult/logging, licensing and all other bindings remain unchanged. This path does not invent a TLS native budget that TrollStore's script binding does not currently supply.

Copy the callback locally. Check it after existing identity/path/input validation, before admission/request work, before opening the serialized request, after a successful write/close before argv/spawn preparation, before result parsing and before returning a valid result. A stop observed at these gates returns vpn_private_helper_cancelled. Preserve existing validation and I/O failure precedence. A stop racing the last pre-spawn check may still allow a spawn; adopt it immediately as before and observe stop during the subsequent wait.

Pass a borrowed C++ Stop predicate only to the synchronous wait. Check it before and after each WNOHANG probe, using the existing at-most-ten-millisecond polling interval. Once stopped, latch that reason and run the existing TERM/KILL grace/reaping policy without consulting the caller again. Cleanup must continue after cancellation. A stop observed after the child is already reaped rejects success and sends no signal to that retired PID. Late stop after valid result parsing also rejects success. The unchanged owner attempts nonrecursive cleanup of its credential/result paths and retains its slot while any child remains unreaped.

Publish probe results directly into owner state through waitInto. A caller predicate can throw an NS/C++ exception immediately after a successful reap; the owner destructor must already know that PID is retired. It now skips further probes/signals for a latched retired result. Existing unwind cleanup handles a still-running child. Exceptions propagate rather than producing a synthetic healthy response.

No callback, closure address, session, JS context, request dictionary or credential data is stored in deferred state. The local callback outlives the synchronous wait and owner scope; background reaping retains only the existing child/ops/path state. There is no caller callback invocation on the reaper queue.

## Verification

Extend the existing workflow runner and retain its original C06a full-source reversal. Add a frozen complete C06a request baseline; a shared reversal verifies both the complete pre-C06b request and the complete pre-C06b TrollStore server. Storage and Event Channel checks first apply that independently hashed adapter reversal and retain all their original historical digests. Current runtime extraction still uses the new source. Extraction of the actual script stop function/call adapter is checked on Windows as well as macOS.

Portable C++11 tests retain 100k deadline and 80k concurrent admission lifecycles, adding 100k stop lifecycles. Cover pre-stopped/live/EINTR/denied-signal/unreaped cases, stop after reap without signalling, and exception after reap with the retirement flag already published. The no-stop/default wait path retains existing tests.

Expanded macOS tests compile the complete current/frozen request transport, actual script stop/read adapter and actual owner with ARC/ASan/UBSan. Cover each of three pre-spawn gates with no child creation, stop during an actual disposable subprocess, missing/stopped script sessions, a valid result discarded after late stop, NS/C++ predicate faults after request write and after reap, and a weak callback capture released while a controlled unreapable child still occupies its slot. Existing foreign-path, TERM/KILL, deferred file cleanup and repeated lifecycle cases remain. Identity/persona providers are controlled; no actual privileged helper, VPN/profile/radio/license state is changed.

Windows validation is recorded in STATE.md. New Foundation/GCD/ARC/sanitizer scenarios require macOS CI. No measured device latency/memory/CPU result is claimed.

## Limits

This connects the existing script stop flag; app/vpnagent callers using the old nil-callback API are unchanged. It does not add an inherited deadline or interrupt request filesystem operations, posix_spawn, system calls, a blocked stop predicate or existing session-lock contention. Keep the callback short and synchronous. Cancellation is cooperative, including the remaining gap before spawn or return. It cannot undo a configuration/Keychain effect already committed and does not authorize automatic replay. Cross-persona TERM/KILL permission and device behavior still require qualification; denied signals keep the bounded owner/reaper until retirement. P0-23 supervisor waits, private backend polling, broker admission and transaction recovery remain open.
