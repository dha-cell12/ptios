# C03ab — bounded local monotonic run durations

Date: 2026-10-30 (Asia/Bangkok). Baseline: `e1f20e22`, C03aa build passed according to the user. Complete normalized history source SHA-256: `fc3231d21d671e2317b2b544eea5f2a9bfbe1ef18ee827f796cbde7ea9dffeee`.
Status: **user reported build passed at `3ed8519e` before C04a; independent device clock/sleep qualification pending**.
Finding: **P2-16 wall-clock run durations**, partial improvement.

## Change

History duration used ended_at_ms minus started_at_ms. Changing wall time during a run could inflate its duration or clamp it to zero. Keep persisted start/end timestamps as wall epochs, but prefer a local continuous-clock delta when this process has a matching committed begin.

Capture mach_continuous_time at the same preparation point as the begin epoch. Convert with a cached Mach timebase and 128-bit intermediate arithmetic; unavailable scale/overflow returns an invalid-clock sentinel. Register the captured start only after index write acknowledgment. Compute finish duration from the tracked start only if scope/run ID and the authoritative started_at_ms match and the current monotonic sample is valid/non-regressed. Otherwise keep the legacy nonnegative wall-clock subtraction.

The process-local tracker has 50 FIFO slots, scope keys bounded to 4,096 bytes and IDs to 96 bytes. It copies key bytes and is serialized by the existing history monitor. UUID starts are created internally; Objective-C wrappers reject embedded NUL IDs before C-string lookup. Overflow retires only the oldest optional timing entry. No clock, identity or new field is persisted; untracked/cross-process/restarted/evicted runs retain fallback. This does not make cross-process duration immune to wall changes.

Successful finish index acknowledgment retires the entry. Required write failures, including uncertain post-index failures, retain it for a retry. Failed begin never registers a start. Registration/lookup/retirement exceptions are best effort and cannot turn a committed history transaction into a failure; fall back to wall duration when tracking is unavailable. Allocation is prepared before tracker replacement/eviction. Normal artifact/status/event duration fields derive from the same finished record. Index/marker/recovery/retirement, redaction, evidence and public field layout remain unchanged. Shared rootfull/roothide and production TrollStore are covered; TouchPOC excluded.

## Verification

Reverse only the clock/tracker block/includes and begin/register/finish-duration/retire calls, then compare the complete source with the user-passed baseline. Retain all earlier full-source checks. Guards require registration/retirement after their checked index writes. Both workflows' existing history runner now compiles the production portable tracker on every host.

The native suite exercises forward/backward/paused wall time, clock regression/unavailability/near-maximum values, epoch/scope/ID mismatch, invalid keys, replacement and FIFO overflow against an independent deque oracle, 10,000 admissions and 100,000 begin/finish lifecycles with zero final entries. These are policy/resource checks, not device timing measurements.

The Foundation harness compiles/samples the actual Darwin clock separately, then controls clock samples for deterministic persistence cases. Existing frozen ordinary wall-clock parity uses equal wall/monotonic fixture clocks. New cases verify real artifact/status/event durations across wall jumps while preserving epoch fields, untracked/restart and altered authoritative-start fallback, unavailable/regressed clocks, record/index/uncertain write failures and retries, failed begin, NS/C++ optional-registration failures that preserve ACK/diagnostics, and a NUL identity fence. Existing actual lock, recovery and cleanup cases remain.

Windows validation passed: all 65 workflow runners (36 source, 29 native) after a focused FileHandle rerun cleared a temporary exe-unlink EPERM (its initial assertions passed), 521 source checks, full-source/history guards/contracts, final elapsed core, expanded assert preprocessing and `git diff --check`. Sixteen artifact-only checks were skipped. New Foundation/Darwin/ARC/sanitizer execution requires macOS CI.

## Remaining work

Optional clocks are process-local, not a persisted reboot/cross-process protocol; untracked fallback still depends on wall time. FIFO eviction can remove a still-running old entry. Every run still uses the existing persistence and IO path, and small sampling/rounding differences from epoch subtraction are expected. No latency/RSS/durability improvement is claimed. Device sleep/time-change tests, a wider elapsed protocol, retention and other C03/device qualification remain open.
