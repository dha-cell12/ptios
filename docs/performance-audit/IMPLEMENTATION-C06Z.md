# C06z — direct-child callback ownership

Date: 2026-11-04 (Asia/Bangkok). Baseline: `5f61cb4f`; user reported C06y build passed and requested continued implementation. Production StreamControl only; TouchPOC excluded.

## Successful spawn identity

The direct child watcher previously returned only a PID/status to the supervisor queue. After a child was reaped, its callback could remain queued while a newer direct spawn acquired the same numeric PID. The existing PID comparison alone could then mark the new run stopped or schedule an inappropriate respawn.

Allocate a fresh object identity before posix_spawn, so metadata allocation cannot fail after creating an unobserved child. Publish it to the supervisor only on spawn success, before publishing PID/running state and queueing the background watcher. A failed attempt preserves the preceding child identity. The watcher captures its own identity and still waits/reaps its exact PID on the background queue, including C06x EINTR retries.

On the owner queue, require a nonnil identity equal to the current direct child. Clear that identity before invoking the preceding exit handler. Stale or duplicate callbacks cannot clear a newer identity, change state/log/events or cancel/schedule a respawn even when numeric PIDs match. The existing PID guard and exit/respawn policy remain as a second check.

## Explicit lifecycle changes

Accepted stop/restart and helper replacement revoke preceding direct-child callback ownership. Clearing occurs after their busy gates, and helper replacement clears only when shouldReplace is true. A refused busy operation preserves the existing watcher; a busy stop still disables auto-respawn under its preceding policy. Ordinary auxiliary ensure does not revoke a healthy direct child's watcher.

Revocation affects state delivery, not reaping: the old background wait continues to collect its child, then its stale owner callback becomes inert. A later successful direct spawn installs a new identity. No new kill, wait thread, child quota, retry, helper authority or argv/persona behavior is added.

This token represents an app-managed direct spawn/lifecycle. It is not a kernel birth identity or an attestation of a process observed through hello. Unannounced external replacement/PID reuse, externally adopted daemons, active wait/helper cancellation, whole-operation deadlines, cross-process coordination and device qualification remain open. The watcher retains its small identity until reaping/delivery, alongside its preceding supervisor capture. C06/P0-23 stay partial.

## Verification

Freeze the complete preceding supervisor and restore only the identity field, allocation/adoption, lifecycle invalidations and callback adapter. Verify the exact previous file/hash before the C06y/C06x/C06u/C06t/C06e/C06c chain. Source guards require allocation before spawn, adoption after its failure return, token retirement before effect delivery and bounded-method stop/restart invalidation after busy refusal.

The native Foundation/GCD/ARC/ASan/UBSan fixture compiles complete current/frozen spawn/watch methods and the unchanged exit policy. Controlled providers compare ordinary argv/spawn/wait/exit output and failure ownership. A reaped-child callback is held while a second spawn uses the same synthetic PID: the new callback adapter preserves the newer state, while the frozen producer demonstrates the old mutation. Other cases cover duplicate/nil callbacks, explicit invalidation, busy refusal, failed spawn retaining the old watcher and weak token lifetime after stale retirement. Thirty-two real serial-GCD runs use disposable children exiting with code seven, inject EINTR before real waitpid, retire identity/state and verify no unreaped child remains. No installed service, real privileged helper or real PID-reuse event is controlled.

Windows validation: all **85 workflow runners** (36 source, 49 safety), **521 existing workflow source checks**, full preceding-supervisor/earlier checkpoint hashes, lifecycle placement guards, fixture extraction, JavaScript syntax, expanded assert preprocessing and `git diff --check` pass. The child guard passes a focused rerun after strengthening per-method invalidation counts. Sixteen artifact-only checks skipped. New Apple compilation/native execution/iOS builds require macOS CI. No measured device latency or memory improvement is claimed.
