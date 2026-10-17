# B04 — H264 backpressure, TS batching and pacing

Date: 2026-10-17. Baseline: `a54251b` (user reported the corrected B03 build passed before this group).

Status: source implemented for rootfull/roothide `pccontrol/H264Stream.xm` and production TrollStore `stream-app/streamd/H264Stream.mm`; new macOS/iOS build and device qualification pending. Prototype TouchPOC is excluded.

Scope: P1-12, P0-06, P1-13, P1-18, plus the small accept-error fix P2-06. Next group is B05 (license hot path); OCR remains C01.

## Sending and wire compatibility

Both production streams use the shared C++11 `TLinkH264Socket` adapter. Each send is nonblocking (`MSG_DONTWAIT`) and preserves the unwritten suffix across short writes, EINTR and EAGAIN. Poll waits are at most 50 ms per iteration. The monotonic window allows **2 seconds without write progress** and **5 seconds total per complete access unit**. PAT/PMT, PES, H264 payload or ZXH2 header/payload share that window; sending the next chunk cannot restart it. A fatal send or deadline failure ends the stream rather than leaving a partial frame on an open connection. There is no application output queue.

TS packet generation preserves the previous byte order, continuity counters, stuffing, PCR and PES framing. A fixed 64-packet, **12,032-byte stack batch** is flushed when full and at the end of each packetizer call. PAT and PMT share one 376-byte write, and table-send failures now propagate. Batches do not wait across frames. TCP may still split or combine these writes.

The **52-byte ZXH2 layout and wall-clock capture/encode/send timestamp semantics remain unchanged**. Encoder input and TS PTS now follow elapsed monotonic capture time instead of a synthetic sum of frame periods. Existing codec, profiles, ports, one-viewer admission, capture backends and license gates are retained.

After existing encoder/buffer cleanup, the client socket and active-viewer slot are released before session-end persistence. Each admitted session has a UUID; adaptive decisions and end updates check it under the existing state transaction lock so a late old-session update cannot deactivate or retune its replacement. Failures before session-start persistence need not produce a persisted end record.

Accept retries EINTR/ECONNABORTED immediately, terminates on invalid listener descriptors, and backs off 100 ms for other failures. Six blocking listener workers remain; this does not claim an idle CPU benefit.

## Adaptive snapshot and recovery telemetry

The capture thread reads numeric FPS/bitrate under a short mutex. It requests refresh at most once per second, with **one outstanding decision job per process**. Disk locking, JSON, thermal sampling and adaptive policy run on a background worker. There is no idle sampler timer and reconnects cannot accumulate queued refresh jobs behind a stuck old worker. Invalidated samplers discard late results.

Initial targets use thermal-capped profile defaults. A snapshot at least **3 seconds old** falls back to the profile minimum FPS and **200,000 bit/s** until a valid result arrives. Lock failures and obsolete-session results do not refresh its age. The existing Task94 feedback schema, persistence location, hysteresis and cooldown policy remain. Staleness uses monotonic time; persisted timestamps remain wall-clock epochs.

Recovery reporting uses a coalesced mailbox independent of the state I/O lock: twelve runtime/port keys maximum, one worker, at most twelve pending and twelve in-flight entries. Reasons are clipped to 256 UTF-16 units. Cumulative success/failure counts saturate safely and are preserved when writes succeed; intermediate event rows coalesce to the last reason/result. Telemetry remains best effort on persistence failure or process exit.

## Absolute pacing

A shared monotonic pacer sleeps to absolute deadlines and skips missed slots without replaying a backlog. Normal, pool-exhaustion and recoverable encoder-error branches use it. Capture/encode/send work consumes the frame period; a pool miss no longer adds a full relative sleep after capture. Existing FPS adaptation remains active.

## Verification

Windows validation passed all **36 existing source-contract checks** and **10 native regression runners (A01–B04)**, including the new H264 runner with MSVC warnings treated as errors. `git diff --check` passed. The portable H264 harness extracts both production packetizers and raw writers and checks:

- partial writes, retries, fatal/invalid/zero writes, exact no-progress expiry and a whole-frame ceiling shared across calls;
- absolute pacing, deadline boundaries and 10,000 variable-work scheduling turns;
- 3,000 TS cases against a frozen pre-change generator, including continuity/start/PCR combinations, exact payload bytes, batch sizes and root/TrollStore parity;
- ZXH2 golden header bytes and write-failure propagation.

For those TS fixtures, calls to the send adapter decrease from **404,971 packet writes to 7,870 batch writes**. This is a deterministic fixture count, not a measured device syscall, CPU, FPS or energy improvement.

Both production workflows run `check-h264-safety.mjs`. Its macOS ASan/UBSan branch compiles the actual network/table/release helpers and the complete shared adaptive implementation, redirecting only its private storage-root function into a temporary directory and doubling event publication. It exercises real socket backpressure and slot release, PAT/PMT CRC, two real TS payload round trips, closed-peer handling, real adaptive state/feedback, obsolete-session guards, a blocked background sampler, replacement/invalidation, stale fallback and 1,201 coalesced recovery counts. This branch has not run on Windows. It does not compile or simulate the full VideoToolbox/capture frame loop; workflow artifact builds and device checks cover that boundary.

## Remaining acceptance and limits

1. Build rootfull, roothide and production TrollStore with both workflow validation and artifact compilation. Run the new macOS integration branch.
2. Decode every TS/ZXH2 profile on real clients, including keyframes, orientation changes, thermal changes, encoder recovery and frame-pool pressure. Verify real-time PTS continuity and the unchanged raw wall-clock fields.
3. Stall a receiver and trickle bytes below frame rate, disconnect mid-header/payload, then reconnect across ports repeatedly. Measure timeout and teardown latency, confirm no stale session update or held viewer slot.
4. Delay adaptive state I/O; frame snapshot reads must remain independent, jobs remain bounded and stale fallback must recover. Exercise feedback, recovery counts, revoke/expiry and reconnect together.
5. Compare send syscalls, capture cadence/jitter, dropped frames, CPU, allocations/RSS, p95/p99 latency and energy against B03 with identical device/profile/load.

Network deadlines bound the sender's cooperative nonblocking loop, subject to scheduling/poll granularity. Capture, VideoToolbox operations/invalidation, license checks and session-start/end persistence can still block outside that window; there is no hard end-to-end teardown SLA. Start/end persistence remains synchronous outside the frame loop, though the viewer slot is released before end persistence. The fixed TS batch and bounded adaptive work do not impose a process RSS ceiling. No private capture backend changes or device performance claims are included.

## macOS portable harness correction

Both root and TrollStore CI stopped compiling the portable H264 fixture because its local `htonl` definition collided with the Darwin SDK macro pulled in by libc++ headers. The fixture now explicitly includes `<arpa/inet.h>` on POSIX hosts and confines the byte-swap fallback to Windows. Production framing and sender code are unchanged. The existing golden-header and root/TrollStore byte-parity cases exercise this conversion; the macOS Foundation/socket integration branch still requires CI execution.

## C++11 atomic compatibility correction

The next CI log confirms the 3,000-case portable H264 suite passes, then shows the macOS runtime fixture failing because newer libc++ rejects mixing `<stdatomic.h>` with `<atomic>` before C++23. Both production H264 translation units and the runtime fixture now consistently use `<atomic>`, directly initialized `std::atomic` values and qualified C++ atomic operations. The default sequentially consistent ordering and viewer/keyframe/license-counter behavior are retained without changing the C++ language level. The portable harness now also compiles the actual production active-slot declaration and release helper for both runtimes, checking ordinary release and an obsolete FD that must not clear a different viewer. Socket shutdown/close are doubled only for these portable cases; real socket cleanup remains covered by the macOS branch.

After this correction, the H264 native runner and all 36 existing source-contract checks pass on Windows. The macOS Foundation/socket branch and iOS artifacts still require CI confirmation.
