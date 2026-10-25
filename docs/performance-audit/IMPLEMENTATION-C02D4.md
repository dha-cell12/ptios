# C02d4 — sender expiry across helper backlog and command waits

Date: 2026-10-26 (Asia/Bangkok). Baseline: `6cbe63c`; the user reported C02d3 built successfully before this slice.
Status: **source implemented; new macOS/Foundation/iOS CI and device qualification pending**.
Finding: **P0-12 prerequisite: carry the sender's original request deadline into helper admission**.

## Behavior

The client stamps each complete transport envelope with an optional `requestDeadline` object before serialization/connect. Its exact fields are `clock: "mach_continuous_ms_v1"`, `issuedMs` and `expiresMs`. The same original client budget covers serialization, backlog/connect, write and read; the helper never constructs a new sender budget at accept, parse or command-owner acquisition.

After framing/validation, the helper uses the earlier of the original 1000-ms accepted-client window and the sender expiry. A future-issued or already-expired sender window closes without entering the command handler. Command-owner wait, the check immediately before handleEnvelope, response serialization checks and writes all retain the shortened deadline. A complete request left in the listen backlog after its client timed out therefore cannot be revived by a fresh accept window. No transport retry is introduced, and a lost response remains an uncertain outcome if its handler already began.

On Darwin, helper socket deadlines now use the same kernel continuous clock in both processes. Integer tick conversion uses the timebase and a 128-bit intermediate, avoiding an overflow in ticks multiplied by the numerator. Timebase failure expires work rather than switching clock domains. The continuous clock advances during sleep; see [Apple's Mach time declarations and availability](https://github.com/apple-oss-distributions/xnu/blob/main/osfmk/mach/mach_time.h) and [Apple's clock documentation](https://developer.apple.com/documentation/driverkit/mach_absolute_time). The production iOS minimum is 14/15; the API is available from iOS 10 and macOS 10.12. Windows portable tests use the local steady clock and injected policy timestamps, not a Darwin wire peer.

The codec rejects malformed presence: wrong object/clock/field count, booleans, strings, fractions, negative/out-of-exact-JSON-range times, nonpositive windows and windows over 30000 ms. Timestamp values are nonnegative integral NSNumber values at most 2^53−1. Protocol validation checks shape; the receiving handler checks current expiry/future issuance. Full JSON framing, the 1-MiB envelope bound, eight-client budget, command serialization, identity/replay and descriptor ownership remain in force.

## Compatibility and limits

This is an additive protocol-1.0 extension for updated client/helper pairs. Absence explicitly retains legacy accepted-time behavior; malformed presence cannot downgrade to legacy. Old helpers can ignore unknown fields and do not enforce sender expiry. There is no new capability negotiation or promise across mixed installed versions; deploy matching binaries before qualifying this contract.

The clock is boot-local, and the field is for live local socket requests, not persistent replay, wall-clock scheduling, authorization or cross-device deadlines. Client-supplied expiry never lengthens the helper's own window. This slice cannot preempt a handler already entered, propagate cancellation into opaque handler internals, undo a side effect, or detect an early-disconnected client before its advertised deadline. Event waits, control-slot fairness, generation/cursors, reconnect ordering and replacing 200-ms polling/fresh sockets remain open. P1-40 invalidation and independent device/performance acceptance remain open. TouchPOC and production TrollStore source are unchanged; both workflows retain the shared regression runner.

## Verification

The existing portable transport runner now also checks 100000 sender-age/budget plans against the expected remaining window, preserving a shorter local deadline and rejecting expired/future/invalid/extreme windows. Prior 100000 framing/partial-write/EINTR/EAGAIN cases remain.

The expanded macOS fixture compiles actual client, codec, accepted-client handler and queued-worker code. It checks metadata on actual client exchanges; malformed envelopes through codec and real socket receiver; expired/future requests with a fresh accept window and suspended queue; a real client timing out before server accept; and a shorter sender budget while the command owner is held. Each denied command checks zero handler effects and balanced admission. Existing legacy EOF, stalled peer, identity, saturation, exception and descriptor tests remain.

All 61 workflow runners (36 source-contract, 25 native), 521 direct workflow source-grep assertions, standards-conforming assert preprocessing and git diff --check pass on Windows; 16 artifact-only checks require CI package outputs. Foundation/ARC/GCD, Darwin clock/sanitizer and iOS/device execution cannot run on this Windows host and require CI/device qualification. No CPU, RSS, wakeup or latency improvement is claimed.

## Device acceptance and next slice

Build matching rootfull/roothide binaries. Hold socket backlog or command ownership beyond a short client timeout and confirm no late command effect when released; include start/stop/native-response commands and unchanged live success/identity behavior. Exercise sleep/wake and helper restart within a boot, short client versus server budgets, legacy peers and malformed/future clocks. Verify all descriptors/admission charges return to baseline and measure actual latency/saturation recovery.

Continue P0-12 event generation/cursor waits and reconnect ordering, releasing command ownership before waits and preserving bounded clients and nonrenewing deadlines. Cancellation inside handlers and device/performance acceptance remain separate work.
