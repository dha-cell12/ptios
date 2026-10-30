# C06a — bounded private VPN helper child ownership

Date: 2026-10-31 (Asia/Bangkok). Baseline: `91b13d41`; the user reported the preceding build passed, including C04k and the transition fixture indentation correction. Complete normalized private-request baseline SHA-256: `5e00471542cf0f5e31851c3474081dfda7281c76afe85da8eb22417ab8ed192b`.

Status: source/portable implementation validated on Windows; new Foundation/POSIX/GCD/ARC/sanitizer runtime requires macOS CI; independent device qualification pending. Addresses **part of P0-22**, not every C06 helper lifecycle.

## Change

TLinkVPNRunPrivateConfigurationHelper previously called waitpid(pid, &status, 0) after a successful spawn. A hung privhelper could therefore hold the caller's private queue or script execution indefinitely.

Acquire one of four process-local admission slots before request-directory/file work. Allocate and resume an initially unarmed monitor before spawning. Failed admission returns vpn_private_helper_busy; failed timer setup returns vpn_private_helper_monitor_failed. These failures do not spawn a helper or write credentials. The cap includes setup, live children and deferred reaping; it is not a system-wide limit across app, streamd and vpnagent.

Adopt the exact positive child PID immediately after successful posix_spawn. Probe that PID with WNOHANG and a steady-clock 30-second wait window, sleeping at most ten milliseconds per poll. EINTR consumes the same window. Check the clock again after each probe, so an exit observed after expiry does not publish a successful configuration result. Missing ownership/ECHILD retires the PID without later signalling it; other wait faults fail closed.

On expiry/failure, attempt TERM after confirming the child is still waitable and running, allow 250 milliseconds, then attempt KILL with another 250-millisecond grace. A final WNOHANG probe catches exits during the last sleep. Return vpn_private_helper_timeout or vpn_private_helper_wait_failed and ignore any result file on that path. Include last native/signal error and helper_reap_pending observation. No blocking wait follows SIGKILL. Scheduler delays and kernel calls remain cooperative boundaries; this is not a hard real-time bound.

If a child is still unreaped, retain its admission slot and an asynchronous 250-millisecond timer on a dedicated serial reaper queue. Every callback performs one WNOHANG probe; no worker blocks waiting for death. If no KILL was attempted, a confirmed running child receives one attempt. A denied signal or persistent wait error retains ownership/capacity until eventual exit/ECHILD or process restart. Terminal observation clears the handler, cancels the resumed source and eventually releases the state/slot. Other children can still be probed because callbacks do not block on waitpid. The owner also follows this cleanup path during NS/C++ unwind after spawn.

The owner stores only immutable path copies and child state. Mark the request path owned only after O_EXCL creation succeeds, and the result path owned only after successful spawn. An uncreated/foreign request path is never removed by the new owner. Attempt nonrecursive unlink of owned credential/result paths immediately on scope exit and again after a deferred child exits, covering late result publication. Existing healthy-path file cleanup and result validation remain. Unlink failures are best effort, as before; an already-open descriptor or child memory is not erased by unlink.

Preserve trusted identity checks, helper-path checks, directory policy, request version/UUID/field allowlist, serialization and byte limits, permissions, fsync, persona attributes, argv, normal result validation and healthy reply fields. A complete source reversal/hash guard enforces this. The shared transport serves production TrollStore app/vpnagent/streamd callers; rootfull's ordinary public NEVPN path is unchanged. TouchPOC is excluded.

## Verification

Both build workflows run check-vpn-helper-child-safety.mjs. The portable C++11 policy tests cover healthy and signalled exits, EINTR, ECHILD, wait errors, TERM-only recovery, KILL escalation, denied signals, never-reaped children, invalid PIDs and clock bounds. Run 100k short deadline/grace lifecycles and 8 x 10k concurrent admission lifecycles, checking the four-slot cap and zero final charges.

The new macOS fixture compiles the actual owner and complete current/frozen request functions with ARC/ASan/UBSan. Only identity/persona/spawn provider and temporary-directory adapters are controlled; request serialization, actual POSIX file I/O, mode/link/length checks, result parsing, child ownership and GCD sources remain real. Compare six old/new transport/result scenarios, checking per-invocation helper_wait PIDs before excluding that naturally variable field from equality. Real subprocesses are disposable shell/sleep children, not the privileged helper. Add a real timeout with a prewritten successful result that must be discarded, a TERM-ignoring child requiring KILL, NS/C++ unwind, external reap/ECHILD, foreign-path preservation, four-child rejection before spawn, a deliberately unreapable controlled child holding capacity while late output is cleaned after retirement, and 64 balanced actual child/source lifecycles. No real VPN/profile/radio/license state is changed. A reduced wait duration is used only in timeout fixtures.

Windows validation: all 71 workflow runners (36 source checks, 35 safety runners), 521 existing workflow source checks, expanded assert preprocessing, JavaScript syntax and git diff --check pass; sixteen artifact-only checks are skipped. New actual Foundation/POSIX/GCD runtime remains pending macOS CI. Synthetic counts are safety evidence, not measured device CPU/latency/memory gains.

## Remaining work

The window covers the post-spawn wait, not queue residence, request filesystem operations or posix_spawn itself. It does not inherit script/caller cancellation yet. Killing the helper does not undo a profile/Keychain/system mutation already committed and does not guarantee transaction crash recovery; timeout is not permission to replay configuration automatically. Descendants/process groups are not signalled. The owner assumes exclusive wait ownership of its spawned child; arbitrary external waitpid(-1) handlers are outside that contract. P0-23 supervisor waits, private backend polling clocks, foreground/agent broker admission, operation coalescing and remaining C06/device work are unchanged. P0-22 remains partially open for caller cancellation and end-to-end timing/qualification.

The real helper may run under a root persona while its parent is mobile. TERM/KILL permission across that identity boundary must be qualified on device; same-user macOS subprocess fixtures do not establish it. A denied signal is reported and preserves the bounded owner/reaper rather than claiming termination or reusing its slot. No credential/entitlement escalation is introduced to force a signal.
