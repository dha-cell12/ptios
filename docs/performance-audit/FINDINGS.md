# Cumulative Findings

## P0 — Critical Performance / Correctness

### [P0-01] Synchronous Foundation formatting and disk write in recording callback

**Status:** CONFIRMED  
**Location:** `pccontrol/Record.xm:137-190`  
**Hot path:** IOHID digitizer callback while recording

**Current behavior**

For every accepted touch child event, the callback:
- reads HID fields,
- calls `CFAbsoluteTimeGetCurrent()`,
- formats an `NSString`,
- converts it to UTF-8 `NSData`,
- calls `NSFileHandle writeData:`,
- calls `CFAbsoluteTimeGetCurrent()` again for the stored baseline.

**Why expensive**

This mixes allocation, formatting, encoding and synchronous file-handle writes directly into the event callback. Slow storage or allocation pressure can delay callback consumption and increase timing distortion/backlog.

**Impact**
- CPU: High during recording
- Memory/allocation rate: High
- Battery: Medium/High during long recording
- Latency/jitter: High risk for recorder fidelity
- Idle: None when recorder is stopped

**Recommended direction**

Keep the existing text format for compatibility in the first optimization. Replace per-event Foundation object creation with a small C/fixed record representation or direct stack formatting into a preallocated byte buffer. Append to a bounded buffer and batch writes on the same recording owner queue or a dedicated writer queue with clear backpressure semantics.

Do not jump to a new binary file format until profiling proves that formatting remains material after batching.

**Trade-off**

Batching introduces buffering/flush semantics and crash-loss window. Bound it by size/time and force flush on stop.

**Benchmark**

Record identical 10k/100k event traces before/after. Measure Time Profiler, Allocations, syscalls/disk writes, callback execution time p50/p95/p99, dropped/missing events, and output equivalence.

---

### [P0-02] Per-line license synchronization in RAW playback

**Status:** CONFIRMED  
**Locations:**  
- `pccontrol/ScriptPlayer.xm:417-434`
- `pccontrol/Task.xm:823-840`
- `shared/TLinkRootfullLicensePolicy.mm:93-103,136-161`
- `shared/TLinkLicenseVerifier.mm:1327-1378`

**Hot path:** every RAW playback line

**Current behavior**

RAW playback calls `processTask` for each line. Recorded events contain a delay line and a touch line, so the normal path performs about two dispatches per recorded event. Every dispatch performs a task->feature lookup and a license check. The feature checker synchronizes on a serial cache queue with `dispatch_sync`, even on cache hits.

**Why expensive**

The license path adds synchronization, Objective-C messaging, time calls, dictionary access and feature-array membership checks to every timing/touch line. This work scales with event count rather than with license state changes.

**Impact**
- CPU: High at dense/high-speed playback
- Memory: Low/Medium transient Objective-C traffic
- Battery: Medium/High
- Latency/jitter: Medium/High, especially for short inter-event delays

**Recommended direction**

For the trusted RAW-script playback path:
1. Validate script entitlement once before playback starts.
2. Store a session authorization/generation snapshot.
3. Use the already-existing 1-second heartbeat/generation invalidation for revocation.
4. Bypass redundant per-line task license checks only for internally parsed lines belonging to that authorized session.
5. Keep current per-command policy checks for external socket/IPC commands.

**Trade-off**

The authorization boundary must be explicit so untrusted external commands cannot enter the fast path. Revocation latency becomes bounded by heartbeat/generation strategy, which already exists and must be documented.

**Expected improvement**

Likely one of the largest CPU wins for dense RAW playback. Exact percentage is **INSUFFICIENT DATA** until `TLinkLicensePerformanceDictionary()` and playback benchmarks are collected.

**Benchmark**

Compare 10k and 100k event playback at 1x and accelerated speed. Capture:
- total feature_check_count,
- average/max feature-check µs,
- total CPU time,
- playback duration error,
- event-to-event jitter.

---

### [P0-03] RAW stop/start race can overlap playback workers

**Status:** CONFIRMED  
**Locations:** `pccontrol/ScriptPlayer.xm:401-437,584-632`

**Current behavior**

RAW playback runs on a global queue. Force-stop sets a plain Boolean cancellation flag, then immediately clears global playback state and publishes `isPlaying = false`. The worker may not observe the cancellation flag until its next loop iteration.

**Impact**
- Correctness: Critical
- Stability: High
- Performance: Overlapping workers can inject duplicate/interleaved touch events and consume extra CPU
- Timing: Unbounded corruption of expected playback sequence

**Recommended direction**

Unify RAW playback with the existing session/generation state machine:
- session owns cancellation,
- worker checks cancellation before every task and before/after waits,
- stop transitions Running -> Stopping,
- only worker completion transitions -> Idle,
- new playback cannot start until prior generation is fully finished.

**Benchmark/repro**

Start a high-density RAW script, stop and immediately start another script repeatedly. Add generation IDs to injection counters and assert no old-generation event occurs after new-generation start.

---

## P1 — High Priority

### [P1-01] Recording client/run-loop lifecycle and shared state are not serialized

**Status:** CONFIRMED  
**Location:** `pccontrol/Record.xm:94-133,207-245`

The IOHID client is scheduled on the recorder's background run loop but stop unschedules using the caller's current run loop. The client is then nulled without an observed CF release. `isRecording`, file handle and run-loop globals cross threads without a single owner/state machine.

**Direction:** recording owner queue/thread + explicit state enum + saved run-loop unschedule + CF release + stop executed on owner context.

---

### [P1-02] RAW repeat scheduling uses NSTimer + nested CFRunLoopRun on a global worker

**Status:** CONFIRMED  
**Location:** `pccontrol/ScriptPlayer.xm:541-555`

A one-shot NSTimer is scheduled on the current worker thread, then the code enters `CFRunLoopRun()`. This consumes a global worker and complicates stop/replay lifecycle.

**Direction:** dedicated serial queue and monotonic deadline scheduling. Prefer absolute deadlines to reduce cumulative drift; measure `dispatch_source_timer` vs absolute sleep/wait before choosing.

---

### [P1-03] Long-running RAW speed-adjust path may accumulate autoreleased strings

**Status:** HIGH-CONFIDENCE  
**Location:** `pccontrol/ScriptPlayer.xm:417-434`

When speed != 1 and a delay line is processed, every delay allocates an autoreleased string via `stringWithFormat:` inside one long-running GCD block. Exact pool-drain behavior is not explicit in this code.

**Direction:** avoid the NSString entirely; parse delay and execute the wait directly in the RAW player. Add a scoped `@autoreleasepool` per bounded batch as a safety net for other Objective-C work.

---

## P2 — Medium Priority

### [P2-01] Permanent popup IOHID listener adds non-zero event callback cost while idle

**Status:** HIGH-CONFIDENCE; magnitude needs measurement  
**Location:** `pccontrol/Tweak.xm:159-208`

The callback is registered on the main run loop and early-filters to keyboard events. It is cheap but not literally zero-cost during general HID traffic.

**Direction:** determine whether the client can be matched to the specific hardware-key event class or conditionally registered only when the feature is enabled. Benchmark callback count and CPU before changing.

---

### [P2-02] H264 servers reserve two global workers/sockets while no stream client exists

**Status:** CONFIRMED resource usage; CPU impact likely low  
**Location:** `pccontrol/H264Stream.xm:925-983`

Two server loops block in `accept()`. This is not busy waiting, so do not classify it as high CPU. It is, however, non-zero idle resource footprint.

**Direction:** consider a demand-driven listener only if profiling/resource constraints justify the extra lifecycle complexity.

---

## Validation backlog

- Verify IOHID child-event ownership after `IOHIDEventAppendEvent`; current Create-rule objects are not explicitly released.
- Verify touch-indicator finger index 0 handling.
- Quantify exact recording allocation/event and memory at 10k/100k events.
- Quantify callback counts for popup listener at idle/device interaction.


---

# S002 Addendum — Touch / Native Gesture / Indicator / Idle Path

## P0 — Additional Critical Findings

### [P0-04] IOHID child event ownership leak on every injected child

**Status:** CONFIRMED  
**Location:** `pccontrol/Touch.xm:169-220`  
**Hot path:** every injected touch frame

**Current behavior**

`generateChildEventTouchDown/Move/Up` return objects created by `IOHIDEventCreateDigitizerFingerEvent`. `appendChildEvent` passes those +1 Create-rule objects directly into `IOHIDEventAppendEvent` and loses the returned reference without a matching `CFRelease`.

The repository contains two sibling implementations that explicitly release the child after append:
- `poc-trollstore/HIDInjectCore.mm:104-105,124-125,141-142`
- `stream-app/streamd/HIDInjectCore.mm:183-184,203-204,220-221`

**Why expensive**

This is not transient allocation churn; it is a retained Core Foundation ownership reference per appended child. Parent events are released, but the caller's Create-rule ownership is not balanced.

**Impact**
- Memory: Critical for long/high-rate playback
- CPU: Secondary allocator/retain pressure
- Battery: Secondary
- Stability: Long sessions can grow resident memory until memory pressure / jetsam

**Quantifiable count**

For a single-finger stream, one child is created per injected frame. Therefore:
- 10,000 frames -> ~10,000 unbalanced child ownership refs
- 100,000 frames -> ~100,000 unbalanced child ownership refs
- 60 frames/s for one hour -> ~216,000 refs
- 120 frames/s for one hour -> ~432,000 refs

Exact bytes/object are **INSUFFICIENT DATA** and must be measured with Allocations / VM Tracker.

**Recommended fix**

Create the child in a local variable, append it, then `CFRelease(child)`. Keep the parent release unchanged.

**Trade-off**

Low, but because IOHID is private API, verify on-device that `IOHIDEventAppendEvent` retains/copies the child as expected. Existing `HIDInjectCore.mm` already exercises this ownership pattern in this repo.

**Benchmark**

Playback 100k touch frames before/after while graphing resident memory and live IOHID event allocations. Expected result: no linear memory growth attributable to child objects.

---

## P1 — Additional High Priority Findings

### [P1-04] Native gesture path serializes numbers to NSString and reparses them on every frame

**Status:** CONFIRMED  
**Locations:** `pccontrol/Task.xm:118-143,152-197,319-385`; `pccontrol/Touch.xm:101-160,230-295`  
**Hot path:** native swipe/zoom/gesture frame generation

**Current behavior**

Native helpers already have typed values (`type/finger/x/y`) but call:
`typed values -> NSString/NSMutableString -> UTF8String -> fixed-width ASCII parser -> typed values -> IOHID`.

`zx_performSingleTouch` allocates/formats an NSString per frame. Multi-touch `zx_performTouchFrame` builds a mutable string and repeatedly uses `appendFormat:`.

**Why expensive**

The internal native path pays wire-format serialization/parsing even though it is not crossing a wire/process boundary.

**Recommended fix**

Add a typed internal injection API in `Touch.xm`, for example a small `TLinkTouchPoint` struct and `performTouchFrame(const TLinkTouchPoint *, size_t)`. Preserve `performTouchFromRawData` only as the external compatibility/parser boundary.

**Trade-off**

Small increase in API surface. Keep one canonical typed implementation so the text parser becomes a thin adapter rather than duplicating behavior.

**Expected improvement**

Most meaningful for 60-120-step swipe/zoom gestures. Exact CPU/allocation reduction is **INSUFFICIENT DATA** until benchmarked.

---

### [P1-05] Relative usleep scheduling accumulates gesture drift and jitter

**Status:** CONFIRMED design issue; magnitude needs device measurement  
**Locations:** `pccontrol/Task.xm:164-196,325-333,374-385`

**Current behavior**

Swipe/zoom/gesture use repeated relative `usleep(interval)`. Processing/serialization/injection time is added on top of every interval, and scheduler oversleep accumulates step by step.

The generic gesture path also injects each MOVE before its interval sleep, while swipe/zoom sleep before the next MOVE, so timing semantics are inconsistent between gesture APIs.

**Recommended fix**

Use a monotonic start timestamp and absolute deadlines for each frame:
`deadline_n = start + n * duration/(N-1)`.
Sleep/wait until the deadline, then inject. Do not busy-wait.

Candidates: `mach_wait_until` or equivalent monotonic absolute scheduling on the dedicated playback/gesture worker. Keep UIKit off this path.

**Expected benefit**

Lower cumulative duration error and lower jitter without increasing CPU.

**Benchmark**

For 100/500/1000/5000 ms gestures at 30/60/120 steps, measure requested vs actual frame timestamp and final duration; report p50/p95/p99 absolute timing error.

---

### [P1-06] Touch parser can read past malformed/truncated payloads

**Status:** CONFIRMED robustness issue  
**Location:** `pccontrol/Touch.xm:101-160,230-253`; caller `pccontrol/Task.xm:823-846`

`performTouchFromRawData` receives only a pointer, not a length. Fixed-offset parsing reads fields based on declared touch count without verifying that the backing buffer contains `1 + count * TOUCH_DATA_LEN` bytes. `processTaskWithContext` has an `actualLength` parameter but does not propagate a bounded touch payload length.

**Impact**

Malformed/truncated IPC/network input can cause out-of-bounds reads or nonsensical events.

**Recommended fix**

Introduce a length-aware parser and reject payloads before any field access. Preserve a legacy wrapper only for callers that can guarantee a NUL-terminated full payload.

---

### [P1-07] Touch indicator finger 0 causes negative array indexing

**Status:** CONFIRMED  
**Locations:** `pccontrol/TouchIndicator/TouchIndicatorWindow.xm:304-407`; `pccontrol/Task.xm:152-196`; `pccontrol/Touch.xm:249-270`

Native tap/swipe default to finger `0`, and the injector accepts indexes `0..19`. Indicator methods only reject `index >= 20` but access `touchIndicatorViewList[index-1]` and `coordinateView[index-1]`.

**Impact**

With the indicator enabled, index 0 can access element `-1`, causing memory corruption/crash.

**Recommended fix**

Choose one canonical indexing convention. The least disruptive option is to store indicator arrays by `index` directly for `0..19`, and reject `index < 0 || index >= MAX`.

---

### [P1-08] Touch indicator queues one main-thread block and does text/layout work for every move

**Status:** CONFIRMED  
**Location:** `pccontrol/TouchIndicator/TouchIndicatorWindow.xm:383-407`

Every move callback enqueues a new main-queue block. The block formats a coordinate string, looks up a font, measures text, and updates multiple frames/layers.

**Impact**
- Main-thread pressure: High while indicator is enabled and touches move at high frequency
- Allocation rate: High
- Visual latency: queued stale move blocks can accumulate if main is busy
- Idle: zero once indicator callback is fully stopped

**Recommended fix**

Keep the feature event-driven but coalesce moves per finger:
- callback stores only latest position/radius,
- ensure at most one pending main-queue update per finger (or one display-frame coalescer while active),
- cache font and use fixed/bounded coordinate label geometry when practical,
- drop stale intermediate visual positions; the indicator is UI telemetry, not the canonical event stream.

Do not use an always-running display link when the indicator is off.

---

### [P1-09] Touch indicator async startup has unsafe NSError** lifetime and duplicate-start race

**Status:** CONFIRMED  
**Locations:** `pccontrol/TouchIndicator/TouchIndicatorWindow.xm:136-214`; caller `pccontrol/Task.xm:1173-1186`

`startTouchIndicator(error)` dispatches asynchronously and later writes through the caller-provided `NSError **`. The caller's local `NSError *err` belongs to a stack frame that may have returned by then. The task also replies success before async startup has actually succeeded.

Additionally, `isShowing` is checked before dispatch but only set inside the async block, allowing two rapid start requests to create multiple clients/run loops.

**Recommended fix**

Make startup state transition synchronous on a single owner queue:
`Stopped -> Starting -> Running -> Stopping`.
Return validation/startup errors before the task replies, or use a completion callback whose error object has owned lifetime. Never capture a caller's `NSError **` across async work.

---

### [P1-10] Touch indicator IOHID client leaks on every start/stop cycle

**Status:** CONFIRMED  
**Location:** `pccontrol/TouchIndicator/TouchIndicatorWindow.xm:201-214,118-131`

The client is created with `IOHIDEventSystemClientCreate`, then on stop it is unregistered/unscheduled and set to NULL without `CFRelease`.

**Recommended fix**

Release on the owner thread after unregister/unschedule. Serialize stop with callback lifetime.

---

### [P1-11] Tweak bootstrap performs UIKit screen access from a global queue

**Status:** HIGH-CONFIDENCE compatibility/stability issue  
**Location:** `pccontrol/Tweak.xm:308-359`

The bootstrap worker directly calls `[UIScreen mainScreen]` and reads bounds/scale off-main. `PopupWindow` defers actual view creation to main, but screen access itself is outside the main-thread boundary.

**Recommended fix**

Collect UIKit-derived screen state on main immediately after SpringBoard launch, then initialize non-UI services on background queues. Avoid moving filesystem/socket initialization back to main.

---

## P2 — Additional Medium Findings / Non-findings

### [P2-03] Fixed 20-slot active-finger scan is bounded and should not be optimized first

**Status:** REVIEWED — NOT A PRIORITY  
**Location:** `pccontrol/Touch.xm:276-288`

The injector scans 20 slots per frame to append unchanged active fingers. This is constant bounded work. Compared with IOHID object creation and current string serialization, replacing it with a bitset/index list is unlikely to be a meaningful first-order win.

Only revisit after P0/P1 fixes and profiling.

---

### [P2-04] Recording callback reads an unused HID range field and performs duplicate clock calls

**Status:** CONFIRMED micro-optimization plus timing issue  
**Location:** `pccontrol/Record.xm:155-188`

`range` is read but never used. More importantly, callback time is sampled once to compute delay and a second time after file I/O to set the baseline.

For correctness, baseline time should not depend on write duration. Prefer the HID event timestamp if validated; minimally sample once at callback/event processing start and advance the baseline before expensive I/O.

This also strengthens P0-01: synchronous write overhead currently contaminates recording timing semantics.

---

## S002 Memory / timing estimates

- Touch injection leak count can be estimated in **objects**, not bytes: approximately one leaked child ownership ref per appended child event.
- A one-hour single-finger stream at 60 Hz is ~216k child events; at 120 Hz ~432k.
- Exact bytes per IOHIDEvent object: **INSUFFICIENT DATA**.
- Native gesture temporary allocations scale approximately with frame count because every frame constructs at least one NSString/NSMutableString payload before IOHID creation.
- Exact allocation bytes/frame: **INSUFFICIENT DATA**.



---

# S003 Addendum — IPC / Socket Ingress / H264 Streaming

## P0 — Additional Critical Hot-Path Findings

### [P0-05] SpringBoard IPC hot touch path performs unconditional NSLog + Foundation parsing + response-stream setup per command

**Status:** CONFIRMED  
**Locations:** `pccontrol/IPCMessagePort.xm:14-98`; caller path from `tlinkauto-binary/SocketServer.mm:292-315,425-503,977-1025`  
**Hot path:** external task 10/61/62/63/64/65 automation ingress

**Current behavior**

The daemon explicitly recognizes touch/native/UI tasks as hot-path payloads and suppresses its normal IPC payload logging. SpringBoard does not apply the same rule.

For a normal task 10 touch message, `handleIPCMessage` currently:
- creates an NSString for the entire IPC payload,
- creates the task-prefix NSString,
- creates task/body substrings and parses task id through NSString,
- `NSLog`s the full received command,
- `NSLog`s task start,
- creates and opens an allocated-buffer `CFWriteStream`,
- calls `processTask`,
- copies the stream data property even though task 10 normally produces no response body,
- closes/releases the stream,
- `NSLog`s completion without response.

That is approximately **three NSLog operations per task-10 event** in the current path.

At:
- 60 commands/s -> about 180 SpringBoard log calls/s,
- 120 commands/s -> about 360 log calls/s,
before counting license checks, parsing, touch generation or any task-61 ACK traffic.

**Why expensive**

Unified logging formatting/transport, Objective-C string creation, CF stream allocation/open/copy/close and repeated parsing are all on the latency-sensitive SpringBoard IPC thread.

**Recommended fix**

Introduce an explicit hot-path IPC fast path before Objective-C command construction:

1. Inspect the `CFData` bytes/length directly for `TASK::` and the two ASCII task digits.
2. Suppress per-event NSLog entirely for known high-rate tasks; use aggregate counters/sampled diagnostics instead.
3. Use a distinct message id or protocol flag for fire-and-forget tasks so SpringBoard does not create a response stream/property when no response is expected.
4. Pass the raw task bytes and exact length into a length-aware task dispatcher.
5. Preserve the general NSString/response path for infrequent control/debug tasks.

**Trade-off**

Do not remove observability. Replace event logs with counters such as received/dropped/error count and sampled latency histograms.

**Benchmark**

Replay 10k/100k task-10 commands and compare:
- SpringBoard CPU,
- logd CPU/wakeups,
- allocations/command,
- IPC dispatch p50/p95/p99,
- task-10 throughput,
- end-to-end task-61 ACK latency.

---

### [P0-06] MPEG-TS streaming issues one send syscall per 188-byte TS packet with TCP_NODELAY

**Status:** CONFIRMED  
**Location:** `pccontrol/H264Stream.xm:268-274,370-435,834-871`  
**Affected profiles:** Fast (7001) and Eco (7002)

**Current behavior**

`writeTSPackets` constructs one 188-byte TS packet on the stack and immediately calls `sendAll` for that one packet. The socket has `TCP_NODELAY` enabled.

This guarantees at least one `send()` syscall per TS packet; partial writes can cause more.

Approximate lower-bound syscall rates based only on configured media bitrate:

- Fast 2,000,000 bit/s: `2,000,000 / (188 * 8) ≈ 1,330 send calls/s`
- Eco 900,000 bit/s: `900,000 / (188 * 8) ≈ 598 send calls/s`

PAT/PMT and transport overhead add slightly more.

**Why expensive**

Hundreds to >1,000 tiny TCP writes per second create syscall, kernel networking and wakeup overhead. `TCP_NODELAY` also prevents Nagle from naturally combining these tiny writes.

**Recommended fix**

Keep MPEG-TS packet boundaries in the byte stream, but batch network writes:
- build multiple 188-byte packets into a bounded preallocated buffer and call `send` once per batch/frame, or
- use `sendmsg/writev` with a bounded iovec set.

Benchmark batch sizes such as 7 packets (1316 bytes), 32 packets, and frame-level batches. Pick the smallest batching level that removes syscall pressure without materially increasing latency.

Do not change the wire format.

**Expected improvement**

Large CPU/wakeup reduction is expected for ports 7001/7002. Exact percentage is **INSUFFICIENT DATA** until syscall counts and CPU are measured.

---

## P1 — Additional High Priority Findings

### [P1-12] H264 blocking send has no write deadline/backpressure policy and can wedge the global active-client slot

**Status:** CONFIRMED design/lifecycle issue  
**Locations:** `pccontrol/H264Stream.xm:195-212,268-274,825-879,915-919`

Accepted client sockets remain blocking. No `SO_SNDTIMEO`, nonblocking mode, poll deadline or bounded send queue is configured.

If a connected client stops reading while TCP stays established, `sendAll` can remain blocked in the stream worker. During that period:
- no new frames are captured,
- the 5-second license heartbeat in the frame loop cannot run,
- cleanup cannot execute,
- `gActiveClientFd` remains occupied,
- all six listener ports reject other clients because the design allows one global active client.

**Recommended fix**

Use bounded low-latency backpressure rather than an unbounded blocking write:
- nonblocking socket + `poll/select` write deadline, or a bounded send mechanism with equivalent semantics,
- define a maximum no-progress interval,
- for a stale slow client, prefer dropping/disconnecting rather than accumulating latency,
- guarantee cleanup resets the active slot.

Exact deadline should be selected by profile benchmark, not guessed.

**Benchmark/repro**

Connect a client, then stop reading without closing. Verify:
- maximum worker blocking duration,
- time until disconnect,
- active slot recovery,
- license revocation responsiveness,
- thread count and CPU.

---

### [P1-13] Adaptive streaming decision performs synchronous filesystem lock/read/JSON work in the frame loop every 20 frames

**Status:** CONFIRMED  
**Locations:** `pccontrol/H264Stream.xm:694-714`; `shared/TLinkAdaptiveStreaming.mm`

Every 20 frames, the H264 worker calls `TLinkAdaptiveStreamingDecision`. That path synchronously:
- ensures the state directory,
- performs chmod/chown,
- opens the lock file,
- takes `flock(LOCK_EX)`,
- reads `state.json`,
- parses JSON,
- rebuilds mutable dictionaries,
- may serialize and atomically write JSON,
- unlocks/closes the file.

Approximate decision frequency while one client is active:
- 30 FPS profiles -> 1.5 calls/s,
- 20 FPS -> 1 call/s,
- 15 FPS -> 0.75 calls/s,
- 12 FPS -> 0.6 calls/s.

Feedback submission can also persist state as often as every 750 ms from the daemon process.

**Why expensive**

This is synchronous disk/metadata/locking work directly inside the realtime-ish capture/encode/send loop and can create frame latency spikes under storage contention.

**Recommended direction**

Preserve cross-process adaptive feedback, but remove normal frame-loop disk I/O:
- keep an in-memory SpringBoard decision snapshot,
- refresh it only when cross-process state changes or at a much coarser bounded cadence,
- perform file read/parse off the frame path,
- ensure directory/permissions once, not on every decision,
- publish an atomic/small immutable snapshot to the stream worker.

A cross-process notification plus cached state is preferable to polling full JSON on every 20th frame.

---

### [P1-14] IPC architecture has head-of-line blocking at both daemon and SpringBoard layers

**Status:** CONFIRMED  
**Locations:**  
- SpringBoard: `pccontrol/IPCMessagePort.xm:56-95,142-156`
- daemon: `tlinkauto-binary/SocketServer.mm:153-160,425-503,1327-1355`

SpringBoard uses one dedicated CFMessagePort run loop and executes `processTask` synchronously inside the message callback.

The daemon routes all client reads/request processing through one serial `socketQueue`. A response-waiting request then synchronously enters the serial `ipcQueue` and can wait up to 5 seconds for CFMessagePort completion.

Therefore one slow SpringBoard task can delay:
- subsequent commands from the same client,
- commands from other socket clients,
- cleanup/write work queued on `socketQueue`,
- periodic daemon ping traffic.

Heavy synchronous tasks such as OCR/UI operations or long native gestures are especially relevant.

**Recommended direction**

Keep ordering only where required:
- isolate high-rate touch/fire-and-forget forwarding from heavy request/response work,
- use per-client serialization rather than one global socket execution queue where protocol order requires it,
- route heavyweight SpringBoard work off the CFMessagePort callback with owned request/response completion where safe,
- never make ping/liveness depend on a queue currently occupied by a multi-second task.

Do not parallelize state-mutating tasks blindly; define task ordering classes first.

---

### [P1-15] External automation hot path performs license policy checks in both daemon and SpringBoard processes

**Status:** CONFIRMED  
**Locations:** `tlinkauto-binary/SocketServer.mm:915-930`; `pccontrol/Task.xm:831-840`; shared verifier path from S001

The daemon checks task entitlement before routing to SpringBoard. SpringBoard checks the task again before execution.

The defense-in-depth boundary is useful and should be preserved, but the current checker performs the expensive cached-dictionary/`dispatch_sync` verifier path on each hot command in each process.

**Recommended direction**

Do **not** simply delete one security boundary. Instead make per-command enforcement cheap:
- each process maintains a local immutable/atomic license snapshot keyed by generation,
- hot task gating becomes a constant-time snapshot lookup,
- generation change/heartbeat performs the heavier refresh,
- denial semantics stay unchanged.

Benchmark both process counters to confirm feature-check growth with task-10 rate.

---

### [P1-16] Daemon socket server serializes synchronous response writes and silently abandons partial/zero-progress writes

**Status:** CONFIRMED control-flow issue; blocking magnitude needs measurement  
**Location:** `tlinkauto-binary/SocketServer.mm:660-675,1327-1355`

`zx_writeAll` is called from the global serial socket queue. It loops synchronously while writes make progress, but if `CFWriteStreamWrite` returns 0 or a negative value it simply breaks with no queued remainder, retry event or error propagation.

For large responses, a slow client can monopolize the serial queue. If the stream makes no progress, the response can be truncated silently.

**Recommended direction**

Use per-client output buffering with a strict maximum and `kCFStreamEventCanAcceptBytes`/equivalent event-driven draining, or another bounded nonblocking write architecture. Disconnect clients that exceed the output/backpressure budget.

---

### [P1-17] IPC response path makes avoidable whole-response copies

**Status:** CONFIRMED  
**Locations:** `pccontrol/IPCMessagePort.xm:74-86`; `tlinkauto-binary/SocketServer.mm:1006-1021`

For non-redacted SpringBoard responses, logging creates an NSData copy of the CFData and then an NSString. On the daemon side, every returned CFData is copied again into a new NSData before the CFData is released.

This is minor for small status responses but material for large base64/JSON results.

**Recommended direction**

After hot-path logging is removed, bridge/transfer response ownership without copying where possible. Keep explicit size limits and lifetime ownership clear.

---

### [P1-18] H264 frame pacing is relative rather than absolute and can accumulate scheduler oversleep

**Status:** CONFIRMED design issue; magnitude needs measurement  
**Location:** `pccontrol/H264Stream.xm:717-750,882-900`

The main path measures work time and then relative-`usleep`s the remaining budget. This compensates for capture/encode/send work within the current frame but not for scheduler oversleep from previous frames.

If the frame context pool is unavailable, it sleeps a full frame budget **after capture work has already occurred**, explicitly lengthening that frame interval.

**Recommended direction**

Pace against an absolute monotonic deadline and skip/drop late frames rather than carrying timing debt. Network backpressure fix P1-12 should come first because blocking sends dominate this behavior.

---

## P2 — Idle / Lower Priority Findings

### [P2-05] Six H264 listener blocks can occupy global dispatch workers while idle

**Status:** CONFIRMED architecture; exact thread/memory footprint needs measurement  
**Location:** `pccontrol/H264Stream.xm:925-988`

Current code starts **six** profile listeners (ports 7001-7006), each as a global-queue block containing an infinite blocking `accept()` loop.

CPU is near zero while blocked, so this is not a busy-loop finding. However blocking worker blocks can force libdispatch to maintain additional threads/stacks in SpringBoard.

**Recommended direction**

If idle footprint measurements justify it, use event-driven listening sockets (`dispatch_source_read`, kqueue, or one dedicated listener event loop) rather than six permanently blocking global workers.

Update older S001 wording that mentioned only two listeners; current source starts six.

---

### [P2-06] Fatal accept errors would spin because all accept failures immediately continue

**Status:** CONFIRMED code behavior; trigger is exceptional  
**Location:** `pccontrol/H264Stream.xm:949-951`

All `accept()` failures immediately loop without checking `errno`. EINTR is fine, but a persistent fatal descriptor/socket error would become a busy loop.

**Recommended fix**

Retry only transient errors; break/recreate listener on fatal errors, optionally with bounded backoff.

---

## S003 prioritization by expected gain × frequency × cost

1. **P0-05 IPC hot-path logging/stream allocation** — executes on every external touch/native message.
2. **P0-06 TS packet send batching** — ~600-1330+ send syscalls/s during TS streaming.
3. **P1-12 bounded stream backpressure** — protects latency, liveness and global client slot.
4. **P1-13 remove disk/JSON from frame loop** — 0.6-1.5 synchronous state reads/s while active.
5. **P1-15 cheap license snapshots while preserving both enforcement boundaries.**
6. **P1-14/P1-16 ingress/output queue isolation** — important under concurrent or slow clients.
7. **P2-05 listener consolidation** — idle resource improvement after active hot paths.



---

# S004 Addendum — Screen Capture / Frame Store / Image Lifetime

## P0 — Additional Critical Performance Findings

### [P0-07] Frame-store insertion deep-copies the full BGRA frame twice

**Status:** CONFIRMED  
**Locations:** `pccontrol/Image.xm:34-51,387-461,1029-1039`  
**Hot path:** task 66 frame capture

**Current behavior**

A frame normally contains:
- `std::vector<uint8_t> bgra` = 4 bytes/pixel,
- `cv::Mat gray` = 1 byte/pixel.

`handleFrameCaptureTaskFromRawData` builds the local `ZXFrameObject frame`, then calls:

`zx_storeFrameLocked(const ZXFrameObject &frame)`

Inside the store function:

1. `ZXFrameObject stored = frame;`
2. `gFrameStore[frameId] = stored;`

`cv::Mat` copies are reference-counted/shallow, but `std::vector<uint8_t>` copies are deep. Therefore the BGRA buffer is copied once into `stored` and a second time into the map.

At the peak of one insertion there can be approximately:
- original BGRA: 4N bytes,
- `stored` BGRA copy: 4N,
- map BGRA copy: 4N,
- one shared gray allocation: N,

for roughly **13 bytes/pixel** before temporary/local copies destruct.

With two existing default frames already stored, inserting the third can put frame-data-only peak near **23 bytes/pixel**, excluding IOSurface/CGImage/context backing.

Examples:
- 1170×2532: one persistent BGRA+gray frame ≈ 14.1 MiB; 3 frames ≈ 42.4 MiB; two existing + third insertion peak ≈ 65.0 MiB frame data.
- 1290×2796: one ≈ 17.2 MiB; 3 ≈ 51.6 MiB; insertion peak ≈ 79.1 MiB.
- 2048×2732: one ≈ 26.7 MiB; 3 ≈ 80.0 MiB; insertion peak ≈ 122.7 MiB.

Those figures do **not** include the capture IOSurface/CGImage or OpenCV/context overhead.

**Recommended fix**

Make frame storage move-based:
- `zx_storeFrameLocked(ZXFrameObject &&frame)`,
- `emplace` / move directly into the map,
- capture response metadata before moving or read it from the inserted object.

The target is one owned persistent BGRA allocation, not three transient full-frame vectors.

**Trade-off**

Low if ownership is made explicit. Verify no caller reads moved-from buffers after insertion.

**Benchmark**

At 10k captures and under a 3-frame rolling store measure:
- bytes allocated/copied per capture,
- peak RSS,
- allocator CPU,
- frame-capture p50/p95/p99.

---

### [P0-08] H264 captures full native-resolution display for low-resolution 15–30 FPS streams

**Status:** CONFIRMED architecture  
**Locations:** `pccontrol/H264Stream.xm:53-119,717-740`; `pccontrol/Screen.xm:127-224`

Every H264 frame first calls `Screen createScreenShotCGImageRef`, whose capture surface is native display pixel dimensions. Only later does H264 draw that full-resolution CGImage into a 640×360, 480×270 or 426×240 encoder pixel buffer.

This means display-server capture bandwidth scales with physical screen resolution, not stream resolution.

Approximate raw 4-byte surface-write bandwidth before downscale:

- 1290×2796 @ 30 FPS: ~413 MiB/s
- 1170×2532 @ 30 FPS: ~339 MiB/s
- 2048×2732 @ 30 FPS: ~640 MiB/s

The iPad8+ path can additionally allocate/render a full-resolution rotated bitmap.

These are raw pixel-volume estimates, not measured DRAM bandwidth. They exclude subsequent draw/downscale, encoder reads and copies.

**Why expensive**

For the 30 FPS raw/RTC profiles this full-screen capture is likely one of the dominant CPU/memory-bandwidth/thermal costs, independent of H264 bitrate.

**Recommended direction**

Prototype a capture API specialized for stream output dimensions:
- test whether `CARenderServerRenderDisplay` can render correctly into a target-sized IOSurface,
- otherwise use a GPU/IOSurface scaling path before CPU-visible full-frame copies,
- reuse capture surfaces/pixel buffers by size,
- avoid full-resolution orientation copies when the final stream is low resolution.

Keep the full-resolution capture API for frame-analysis tasks that actually require it.

**Benchmark**

Compare current native capture vs target-resolution capture at 12/15/20/30 FPS:
- capture time,
- SpringBoard CPU,
- memory bandwidth / Energy Log,
- thermal state,
- end-to-end stream latency,
- visual correctness/orientation.

---

### [P0-09] Image-store serialization lock is held during expensive template matching and color scans

**Status:** CONFIRMED  
**Locations:** `pccontrol/Image.xm:528-605,608-786,789-903`

`zx_imageQueue()` is intended to serialize store ownership/lifetime, but several handlers execute their entire workload inside `dispatch_sync(zx_imageQueue(), ^{ ... })`.

While holding the single serial queue they perform:
- `zx_findTemplateSAD`,
- large color-region scans,
- multi-point nested searches,
- batch template matching,
- Objective-C parsing/result formatting.

A long operation therefore blocks:
- new frame insertion,
- frame release,
- other color reads,
- other image searches,
- OCR region acquisition,
- cleanup of expired frames.

**Why expensive**

Lifetime protection has become compute serialization. This creates image-subsystem head-of-line blocking and makes latency of otherwise O(1) frame operations depend on the longest CV search.

**Recommended fix**

Use immutable/ref-counted frame snapshots:

For grayscale, `cv::Mat` can be shallow-copied under the store queue to retain backing data, then processed outside the queue.

For BGRA, replace raw `std::vector<uint8_t>` ownership with a ref-counted immutable buffer/frame object (for example `shared_ptr`-owned storage or a ref-counted `cv::Mat`) so consumers can snapshot ownership cheaply.

The store queue should protect only:
- lookup,
- generation/owner validation,
- retain/snapshot,
- insert/erase.

Do expensive matching/scanning after releasing the queue.

**Benchmark**

Run one worst-case template/multi-point search while concurrently issuing:
- frame release,
- frame capture,
- color pick,
- OCR-region copy.

Measure queue wait and end-to-end latency before/after.

---

## P1 — Additional High Priority Findings

### [P1-19] iPad8+ screen-capture path releases a borrowed CGColorSpace and has unchecked CF/CoreGraphics failure paths

**Status:** CONFIRMED ownership bug + failure-path robustness issue  
**Location:** `pccontrol/Screen.xm:179-224`

On the iPad8+ rotation path:

`CGColorSpaceRef colorSpaceInfo = CGImageGetColorSpace(cgImageRef);`

returns a non-owned Get-rule reference, but the code later calls:

`CGColorSpaceRelease(colorSpaceInfo);`

without a balancing retain/create. This can over-release the color space owned by the image/context and is a correctness/stability bug.

The same function also:
- calls `IOSurfaceLock(screenSurface,...)` before checking whether `IOSurfaceCreate` returned NULL,
- calls `CGImageGetWidth/Height(cgImageRef)` without checking the image creation result,
- uses the bitmap context without checking `CGBitmapContextCreate` succeeded.

**Recommended fix**

Balance only owned CF objects; never release the `CGImageGetColorSpace` result unless explicitly retained. Add failure checks and cleanup at every Create boundary.

The repository already demonstrates the correct rule in `TemplateMatch.xm`, where a comment explicitly notes that `CGImageGetColorSpace()` does not transfer ownership.

---

### [P1-20] Frame TTL is lazy cleanup, so expired full-frame memory can remain indefinitely while idle

**Status:** CONFIRMED  
**Locations:** `pccontrol/Image.xm:77-79,999-1039`; cleanup call sites `553,622,806,925,1032`

Frames have a default 1-second TTL and hard 5-second TTL, but there is no timer or delayed cleanup. `zx_cleanupFramesLocked` runs only when a later frame operation/store occurs.

Therefore if three frames are captured and the subsystem becomes idle, all three can remain resident indefinitely despite being logically expired.

Because the default frame stores BGRA + gray, retained idle memory is approximately `15 × width × height` bytes for three frames:
- 1290×2796 ≈ 51.6 MiB,
- 2048×2732 ≈ 80.0 MiB.

**Recommended direction**

Do not introduce high-frequency polling. Options:
- schedule one coalesced cleanup deadline for the earliest frame expiry,
- or make frame handles own ref-counted data and release storage when the last consumer completes while keeping only lightweight expired metadata.

Explicit release remains useful, but TTL should mean actual bounded memory lifetime.

---

### [P1-21] Image-object store is count-bounded, not byte-bounded, and has no TTL cleanup

**Status:** CONFIRMED  
**Locations:** `pccontrol/Image.xm:21-32,71-73,982-997,1154-1329`

The image store allows up to 64 `cv::Mat` grayscale objects. `ttlMs` exists in `ZXImageObject` but is set to zero and never used for cleanup.

For capture-created objects, each full-screen grayscale image costs roughly 1 byte/pixel:
- 1290×2796: ~3.44 MiB/object; 64 objects ~220 MiB.
- 2048×2732: ~5.34 MiB/object; 64 objects ~342 MiB.

For action-2 disk images there is no source-dimension/byte cap before `imread`, so count alone does not bound memory.

**Recommended fix**

Add:
- per-image maximum decoded pixels/bytes,
- global image-store byte budget,
- LRU/owner-aware eviction or TTL policy,
- diagnostics for current/peak bytes, not only object count.

Do not evict an object currently held by a ref-counted operation snapshot.

---

### [P1-22] Every capture repeats invariant device detection plus short-lived Foundation/IOSurface construction

**Status:** CONFIRMED hot-path overhead  
**Locations:** `pccontrol/Screen.xm:127-181`; `pccontrol/Common.xm:10-16`

Every capture:
- calls `uname`,
- creates an NSString device identifier,
- executes a regular-expression match to decide `isiPad8orUp`,
- creates multiple NSNumbers,
- creates a properties NSDictionary,
- creates a new IOSurface.

At 30 FPS the device-class test alone runs 30 times/s even though it cannot change during process lifetime.

**Recommended fix**

Cache invariant device capability exactly once. Cache/reuse surface configuration and preferably surfaces by dimensions, with a bounded pool if concurrent capture is supported.

Screen dimensions/orientation may change; device generation does not.

---

### [P1-23] Gray-only frame capture still allocates/renders a full BGRA intermediate

**Status:** CONFIRMED  
**Location:** `pccontrol/Image.xm:387-449,1074-1102`

Even when `needGray=true, needBGRA=false`, capture renders the CGImage into `tmpBGRA` (4 bytes/pixel), then converts that into a 1-byte/pixel gray `cv::Mat`, then drops the BGRA temporary.

**Recommended direction**

For gray-only callers, render directly into a grayscale bitmap/mat where CoreGraphics compatibility allows it, or use a capture converter that writes gray without a full 4-channel temporary.

Benchmark direct gray rendering for color correctness and orientation before replacing the current path.

---

### [P1-24] OCR region extraction performs the clone/conversion while holding the global image-store queue

**Status:** CONFIRMED  
**Location:** `pccontrol/Image.xm:906-967`

For an existing gray frame, `frame.gray(roi).clone()` is executed inside the store queue. For BGRA-only frames, `cv::cvtColor` also executes inside that queue.

A large OCR region can therefore block unrelated frame operations even though the OCR itself later runs elsewhere.

**Recommended fix**

Snapshot ref-counted immutable source ownership under the queue, then clone/convert outside.

This is a specific manifestation of P0-09 and should be fixed by the same ownership redesign.

---

### [P1-25] Template caches are entry-bounded but not memory-bounded

**Status:** CONFIRMED  
**Location:** `pccontrol/TemplateMatch.xm:115-147,159-185,383-420`

The base template cache can reach 33 entries before clearing; the scaled-template cache can reach 65 keys. Each scaled key stores a vector of full `cv::Mat` images.

Memory cost depends on template size, scale ratio and `maxTryTimes`, but no byte budget exists.

Additionally, `maxTryTimes` comes from request data and scaled-template generation occurs before the 8-second matching timeout starts. A very large value can create many resized templates and retain them in the cache before the timeout can protect the operation.

**Recommended fix**

- validate/cap scale parameters and max-try count,
- maintain a byte-accounted LRU cache,
- evict on memory pressure,
- set the timeout/budget around preparation as well as matching.

---

### [P1-26] Capture timing/TTL uses wall-clock time instead of a monotonic clock

**Status:** CONFIRMED design issue  
**Locations:** `pccontrol/Image.xm:81-84,417-419,999-1009`

Frame age/expiry uses `CFAbsoluteTimeGetCurrent()`. Wall-clock corrections can make ages jump forward or backward; unsigned age calculations can underflow when time moves backwards.

**Recommended fix**

Use a monotonic/continuous clock for TTL and performance durations. Keep wall-clock timestamps separately only if externally needed.

---

## P2 — Medium / Migration Findings

### [P2-07] Legacy image/template paths recapture full screen per query instead of reusing frame handles

**Status:** CONFIRMED  
**Locations:** `pccontrol/Image.xm:1154-1228,1338+`; `pccontrol/ScreenMatch.xm:26-50`

The newer tasks 66–70 provide a capture-once/use-many model, but legacy image capture/find/template calls still create a fresh full-screen capture for each operation, even when the requested region is small.

**Direction**

For high-frequency automation workflows, prefer frame capture + multiple frame operations. Keep legacy behavior for compatibility rather than forcing a risky protocol rewrite.

---

### [P2-08] Template cache invalidation uses second-resolution mtime + file size

**Status:** CONFIRMED correctness edge case  
**Location:** `pccontrol/TemplateMatch.xm:95-147`

A template rewritten within the same mtime second to the same file size can reuse a stale cache entry.

Use nanosecond-resolution modification metadata where available, inode/generation, or an explicit content/version key.

---

## S004 memory model summary

For a frame with both BGRA and gray:
- persistent payload ≈ `5 × pixels` bytes,
- current insertion peak for the new frame ≈ `13 × pixels` bytes because of two deep vector copies,
- three-frame retained store ≈ `15 × pixels` bytes,
- two existing frames + third insertion transient ≈ `23 × pixels` bytes,
before IOSurface/CGImage/OpenCV allocator overhead.

These are source-derived payload estimates, not measured RSS. Validate with Allocations/VM Tracker.

## S004 optimization ranking

1. **P0-08 target-resolution/reusable capture path for streaming** — highest frequency and pixel volume.
2. **P0-07 move frame buffers into store** — surgical, large memory-bandwidth/peak-RSS win.
3. **P0-09 shrink image-store critical section** — removes CV-induced HOL blocking.
4. **P1-19 fix iPad CF ownership/failure handling** — correctness/stability, low implementation cost.
5. **P1-20 actual expiry cleanup** — meaningful idle memory reduction after frame workflows.
6. **P1-21 image-store byte budget** — prevents long-session/OOM growth.
7. **P1-22 cache device metadata/reuse capture resources.**
8. **P1-23 direct gray path.**
9. **P1-25 byte-bounded template cache.**



---

# S005 Addendum — OCR / Template / Color Compute

Recovered from the S005 fallback checkpoint created while the ptios workspace connector was unavailable.

## P0 — Additional Critical Findings

### [P0-10] Tesseract engine cache is unbounded by configuration cardinality and cached engines retain the last UIImage

**Status:** CONFIRMED  
**Locations:** `pccontrol/TesseractOCRTask.mm:69-76,181-199`; bundled `third_party/TesseractOCR/TesseractOCR/G8Tesseract.h:108-112`

The cache key is `lang|oem|psm|whitelist`, so changing whitelist/PSM can create another long-lived `G8Tesseract` instance even when language/model are identical. There is no LRU, entry/byte limit or memory-pressure eviction. Bundled G8Tesseract declares its `image` property strong, so each cached engine can also retain its most recently assigned OCR UIImage.

**Direction:** cache expensive engine identity by language/OEM where safe, apply PSM/whitelist per request on the serialized OCR queue, bound cache bytes/entries, purge on memory pressure, and clear retained request images after recognition if supported by the wrapper.

### [P0-11] Tesseract scale-up can amplify source-visible request memory to roughly 33× the source gray ROI at scale 4

**Status:** CONFIRMED for source-visible buffers; Tesseract/Leptonica internal bytes are **INSUFFICIENT DATA**  
**Location:** `pccontrol/TesseractOCRTask.mm:157-175`

The source frame ROI is already a gray copy. At scale 4, resize creates ~16N gray bytes and UIImage conversion copies those ~16N bytes into NSData/provider-backed image storage. Together with the original N-byte ROI this is about 33N before unknown OCR-engine working memory.

For a 1290×2796 full-frame gray ROI (~3.44 MiB), source-visible scale-4 data can exceed ~113 MiB before Tesseract/Leptonica internals.

**Direction:** enforce a post-scale pixel/byte budget, avoid clone when scale=1 and preprocessing does not mutate input, and avoid retaining the final request image in long-lived engines.

## P1 — S005 High Priority

### [P1-27] Tesseract recognition timeout does not bound queue wait or preprocessing
The serial OCR queue can accumulate requests. `maximumRecognitionTime=3.0` does not include queue wait, ROI copy, resize/threshold, UIImage conversion or result extraction. Add a full-request monotonic deadline and stale-job cancellation.

### [P1-28] Vision OCR full-captures native screen for every area request
`TextRecognizer.xm` captures the whole display, then creates/crops a CIImage for the requested OCR region. Region-sized OCR still pays S004 native capture cost. Prefer immutable task-66 frame/ROI snapshots.

### [P1-29] Vision OCR is synchronous with no application-level deadline/cancellation
`performRequests:` blocks the calling path. Combined with synchronous SpringBoard ingress, a slow Vision request can cause head-of-line blocking. Isolate heavy OCR from latency-sensitive command classes and add request cancellation/deadline semantics.

### [P1-30] VKOcrManager assumes every observation has a top candidate
`[i topCandidates:1][0]` is indexed without checking count. Empty candidates can raise an array-bounds exception.

### [P1-31] VKOcrManager leaves `inProgress=true` on recognition error
Current callers create a fresh manager so impact is limited, but this must be fixed before manager/request reuse.

### [P1-32] Legacy ColorPicker full-captures and re-renders for tiny queries
Single pixel and small region color operations capture the full screen then create/render a crop buffer. Prefer frame-backed task-66/task-69 paths for high-rate automation.

### [P1-33] Legacy multi-point color search performs NSValue extraction in the innermost candidate loop
Worst-case work is approximately candidate-count × point-count with Objective-C messaging on every point comparison. Parse once into a C/C++ vector as the newer frame path already does.

### [P1-34] Color search has no compute deadline and request-controlled worst-case work
Large region + skip=0 + large point tables can occupy the synchronous SpringBoard request path for a long time. Bound candidate/point budgets and check a monotonic deadline at coarse row/block intervals.

### [P1-35] Legacy ColorPicker leaks captured CGImage on several validation-error returns
Scalar validation occurs after capture in some paths and returns without releasing the screen image. Validate first and use one RAII/cleanup scope.

### [P1-36] TemplateMatch “8 second timeout” is not a true compute deadline
The timeout is checked only between scaled templates. A single nested SAD scan can itself exceed 8 seconds. Pass a deadline/cancel token into the inner matcher and check at bounded intervals.

### [P1-37] Template matching preparation has request-controlled scale count/size before timeout begins
`maxTryTimes` and scale ratio can create many resized templates before the timer starts. Cap tries/scale/pixels/bytes and include preparation in the same deadline.

### [P1-38] TemplateMatch changes process-global OpenCV thread count on every match
`cv::setNumThreads(1)` mutates global state. If required for platform stability, set once at initialization; otherwise benchmark alternatives.

### [P1-39] Legacy template/Vision paths repeat RGBA→gray/full-capture work already represented by frame handles
Expose immutable frame adapters to OCR/template/color consumers while keeping legacy protocol compatibility.

## P2 — S005

- **P2-09:** Tesseract `check_langs` rescans tessdata on every call. Cache with directory generation/mtime invalidation if repeated use matters.
- **P2-10:** Serial Tesseract execution itself is not a performance bug. Keep single-worker semantics until profiling proves bounded parallelism is worthwhile.

---

# S006 Addendum — JavaScript Runtime / Native Bridge

## P0 — Additional Critical Findings

### [P0-12] Helper-mode native RPC uses fixed 200 ms polling and opens fresh Unix sockets for status/response traffic

**Status:** CONFIRMED  
**Locations:** `pccontrol/TLinkautoJSRuntime.mm:981-1100`; `pccontrol/jsruntime/TLinkJSHelperClient.mm:15-79,100-115`; `tlinkauto-jsd/TLinkJSHelperServer.mm:266-325`

**Current behavior**

A helper JS native call stores one `pendingNativeRequest` and blocks on `rpcCondition` waiting up to 5 seconds (7 seconds for zoom). SpringBoard does not receive an event when the request appears; it discovers it by:
1. opening a new AF_UNIX socket,
2. sending a JSON/envelope `status` command,
3. parsing the response,
4. handling any pending RPC,
5. opening another new socket to send the native RPC response,
6. sleeping 200 ms before the next status poll.

Even with no native RPC, an active helper session performs about five status connection/serialization cycles per second.

**Impact**
- Native-call detection latency: approximately 0–200 ms from polling phase alone, before task execution/transport.
- Touch/automation latency: Critical for helper-mode interactive calls.
- CPU/wakeups: avoidable active-session polling and socket churn.
- Battery: avoidable wakeups for long helper scripts.

**Recommended direction**

Replace fixed polling with an event-driven/persistent transport:
- persistent bidirectional Unix-domain connection, or
- long-poll/status request that blocks server-side until state/RPC changes and returns immediately,
- keep bounded timeouts and reconnect logic.

Do not solve this by shortening poll interval; that trades latency for CPU/battery.

**Benchmark**

Compare in-process vs helper for 1k/10k lightweight native calls. Report request-to-native-start and total RPC p50/p95/p99/max, socket connections/RPC, status calls/s, CPU and wakeups.

---

### [P0-13] In-process JS typed native calls are serialized into the legacy text protocol and reparsed on every request/response

**Status:** CONFIRMED  
**Location:** `pccontrol/jsruntime/TLinkInProcessNativeBridge.mm:190-227` and method handlers throughout the file

**Current behavior**

Typed JS values become Objective-C arrays/dictionaries, then most native methods:
- format a protocol NSString,
- UTF-8 encode it to NSData,
- mutable-copy it and append NUL,
- allocate/open an in-memory CFWriteStream,
- call `processTask`,
- copy the stream data property,
- decode NSData to NSString,
- trim/split the response on `;;`,
- build another NSDictionary typed result.

No process/socket boundary is crossed in this path.

**Impact**
- CPU/allocation: scales with every native JS call.
- Latency: especially relevant to frame color/touch/poll helpers.
- Memory bandwidth: whole-payload copies for larger responses.

**Recommended direction**

Create structured in-process task APIs for the hottest typed methods and keep `rawTask`/text parsing only as compatibility boundaries. Preserve license and cancellation enforcement at the structured entry point.

**Trade-off**

Avoid duplicating task semantics. Refactor toward one typed implementation with wire parsers as adapters.

---

### [P0-14] JS cancellation context is dropped when the in-process bridge enters processTask

**Status:** CONFIRMED  
**Locations:** `TLinkInProcessNativeBridge.mm:195-212`; `pccontrol/Task.xm:677-685,823+`; `ScriptPlayer.xm:360-369,592-609`

ScriptPlayer correctly creates a session cancellation token and calls `runtime requestStop`. The bridge checks cancellation once before native execution, but then calls:

`processTask(...)` → `processTaskLegacy(...)` → `processTaskWithContext(..., nil)`.

Therefore cancellation that arrives **during** a long native operation is not propagated through Task.xm. This specifically defeats context-aware cancellation already present in `RunShellCore(command, context,...)` because the JS bridge supplies nil context. Native gesture/OCR/template paths similarly cannot observe the JS token unless they have independent cancellation.

The JavaScriptCore watchdog only runs while JS bytecode is executing; it cannot interrupt an Objective-C/native method currently blocking the JS thread.

**Impact**
- Stop latency/correctness: Critical for long shell/OCR/template/gesture calls.
- License revocation responsiveness: can be delayed by the current native call.
- User-visible control: force-stop may appear ineffective until native work returns.

**Recommended fix**

Call a length-aware `processTaskWithContext(..., context)` or, preferably, structured native handlers that receive the same `TLinkTaskExecutionContext`. Long loops/waits must check the token at bounded intervals.

**Benchmark**

Start 30–60 second shell/gesture and worst-case template/OCR work, request stop 100 ms after start, and measure stop-to-worker-return. Assert no native side effect from the old generation after cancellation completion.

---

## P1 — S006 High Priority

### [P1-40] Helper RPC policy rereads and reparses config.json for every uncached native RPC

**Status:** CONFIRMED  
**Locations:** `TLinkautoJSRuntime.mm:92-121,1061-1067`

`TLinkautoJSHelperConfigSnapshot()` performs `NSData dataWithContentsOfFile` + JSON parsing. The helper RPC loop invokes it for every new RPC policy decision.

**Direction:** maintain an immutable generation/mtime-backed config snapshot, refresh only on change/notification, and use constant-time policy reads per RPC.

---

### [P1-41] Helper dedupe fingerprints whole argument JSON and can retain up to 256 complete RPC results

**Status:** CONFIRMED  
**Locations:** `TLinkautoJSRuntime.mm:129-136,1041-1076`

Every RPC serializes its arguments to JSON/NSString solely to fingerprint duplicate IDs. The cache stores method, fingerprint and full result for up to 256 entries.

For bridge results allowed up to ~1 MiB, the theoretical raw-payload retention alone can approach ~256 MiB if many cached responses are near the limit; exact RSS is **INSUFFICIENT DATA** because result structure/string sharing and real payload mix vary.

**Direction:** fingerprint request bytes/hash incrementally, cache only what replay semantics require, and apply a byte budget in addition to entry count.

---

### [P1-42] JS console logging has synchronous NSLog plus an unbounded async disk queue and two open/write/close cycles per line

**Status:** CONFIRMED  
**Location:** `pccontrol/jsruntime/TLinkJSRuntimeCore.mm:213-259` plus console block in `runScriptAtPath`

Each console call formats JS arguments, synchronously calls `NSLog` on the JS thread, then queues a block. The writer checks file attributes/existence, opens NSFileHandle, seeks, writes and closes separately for both run log and latest log.

The async queue has no byte/entry bound. A log-heavy script can enqueue faster than storage, retaining strings/blocks; script teardown then `dispatch_sync` flushes the backlog.

**Direction:** persistent writer handle(s), bounded byte queue/ring, batched writes, drop/coalesce policy with dropped-count telemetry. Keep synchronous NSLog disabled/sampled outside diagnostic builds.

---

### [P1-43] JS file readLine performs one read syscall per byte

**Status:** CONFIRMED  
**Location:** `shared/TLinkJSFileHandle.mm:190-220`

A line up to the 512 KiB transfer limit can cause up to ~524,288 one-byte `read()` syscalls.

**Direction:** add a per-handle buffered reader (e.g. 8–32 KiB chunks) and scan for newline in memory while preserving file position semantics.

---

### [P1-44] File reads always build both UTF-8 text and base64 representations

**Status:** CONFIRMED  
**Location:** `shared/TLinkJSFileHandle.mm:49-60,142-187`

`TLinkJSFileDataResult` always attempts a text NSString and always produces a base64 string. A 512 KiB text read therefore creates the NSData plus roughly 683 KiB base64 output plus text/JSC conversion even if the script needs only text.

**Direction:** make encoding explicit or lazy; return text for text API and base64 only for binary API.

---

### [P1-45] 1 MiB raw-response limit is enforced only after CFWriteStream has materialized the full response

**Status:** CONFIRMED  
**Location:** `TLinkInProcessNativeBridge.mm:207-223`

The bridge lets `processTask` write into an allocated-buffer CFWriteStream, copies the accumulated CFData, and only then rejects responses above 1 MiB. The limit therefore does not bound peak allocation/write work.

**Direction:** use a bounded response sink or make task writers enforce an output budget while producing data.

---

### [P1-46] Bridge silently truncates input payloads at 8192 NSString characters

**Status:** CONFIRMED correctness issue  
**Location:** `TLinkInProcessNativeBridge.mm:199-206`

Payloads longer than 8192 characters are silently cut before parsing. Valid batch/gesture/shell/raw requests can therefore become malformed or, worse, execute a partial command.

**Recommended fix:** reject oversize payloads explicitly or use a length-aware protocol/structured path. Never silently truncate executable/task input.

---

### [P1-47] Synchronous JS storage helpers perform avoidable whole-buffer conversions

**Status:** CONFIRMED  
**Location:** `TLinkInProcessNativeBridge.mm:456-522`

Examples:
- readJSON: file → NSString → NSData → JSON object.
- writeJSON: object → JSON NSData → NSString → writeText → NSData again for byte counting → atomic file write.
- writeText encodes to NSData for length and then asks NSString to encode/write again.

**Direction:** read/write NSData directly for JSON; avoid double encoding. Storage APIs remain synchronous by contract, so benchmark large 512 KiB calls and document that they block JS execution.

---

## P2 — S006 Medium / Reviewed

### [P2-11] JS helper/runtime deadlines use wall-clock NSDate
Helper session deadlines and interruptible sleeps use `NSDate`. Clock adjustments can move deadlines. Use monotonic/continuous time for execution budgets.

### [P2-12] pressHardwareKey contains a fixed non-interruptible 50 ms sleep
This bounds stop delay by at least that segment. Low priority relative to P0-14; use interruptible timing when native context propagation is fixed.

### [P2-13] A fresh JSVirtualMachine/JSContext and all preludes are built/evaluated per script run
This is startup cost, not steady-state hot-path cost. Benchmark script-start latency before introducing VM/context pooling because pooling increases state-isolation and leak risk.

### Reviewed non-finding: no obvious core JS retain cycle in the inspected path
`TLinkInProcessNativeBridge.host` and `TLinkautoDeviceBridge.runtime` are weak, exception/log blocks capture runtime/facade weakly, and open-file close callbacks use a weak device bridge. File-handle JS blocks retain their handle, but session cleanup closes all open descriptors. Keep Instruments leak testing, but no source-level P0/P1 cycle was confirmed.

## S006 prioritization by expected gain × frequency × cost

1. **P0-12** event-driven helper RPC transport — direct automation latency + wakeup win.
2. **P0-14** preserve cancellation context into native work — stop/revocation correctness.
3. **P0-13** structured in-process native fast paths — allocation/CPU win on every JS native call.
4. **P1-40** cached helper policy/config snapshot — remove per-RPC disk/JSON work.
5. **P1-42** bounded/batched console writer — protects log-heavy scripts.
6. **P1-43/P1-44** buffered/lazy file APIs.
7. **P1-41/P1-45/P1-46/P1-47** memory/correctness/copy bounds.



---

# S007 Addendum — Scheduler / Run History / Persistence

## P0 — Additional Critical Findings

### [P0-15] Scheduler timer registry has cross-thread ownership races and async create/remove reordering

**Status:** CONFIRMED  
**Locations:** `pccontrol/Scheduler.xm:113-224`

**Current behavior**

`timerRegistry` is a global mutable dictionary with no lock/owner queue.

- `setTimerFromRawData` initializes/reads `timerRegistry` on the caller thread, then asynchronously creates and inserts the NSTimer on the main queue.
- `removeTimerFromRawData` reads, invalidates and removes the timer immediately on the caller thread.
- one-shot `timerFired` removes its entry on the main thread.

This creates multiple valid race/reordering sequences.

**Reproducible ordering issue**

1. `setTimer(name)` queues main-thread timer creation and returns success.
2. `removeTimer(name)` runs before that queued block and sees no timer.
3. remove returns success.
4. queued main block later creates/inserts the timer.
5. the supposedly removed timer fires.

Two rapid `setTimer` calls for the same name can also both observe no existing timer before either main-queue insertion. Both NSTimers remain scheduled; the dictionary eventually points to only one, leaving the other untracked and therefore not removable by name.

**Impact**
- Correctness: Critical; removed/replaced schedules can still execute scripts.
- CPU/battery: ghost repeating timers can continue generating wakeups.
- Stability: unsynchronized NSMutableDictionary access across threads is unsafe.
- Operational safety: duplicate scheduled script launches can occur.

**Recommended fix**

Give the scheduler one ownership context for registry + timer lifecycle. Good options:
- main queue for all registry mutation and NSTimer operations, or
- dedicated serial scheduler queue using `dispatch_source_t` timers.

Use a per-name generation/token. A queued create/fire must verify it is still the current generation before launch. Make set/remove completion reflect the serialized state change rather than returning before creation is committed.

**Benchmark / race test**

From 8 concurrent clients, repeatedly:
- set -> remove same name,
- set A -> set B same name,
- set/remove while timer is firing.

Track generations, timer-create count, timer-fire count and active registry count. Acceptance: after remove acknowledgment there are zero future fires for that generation; only the latest set generation may fire.

---

### [P0-16] Scheduler accepts arbitrarily small repeating intervals and executes synchronous launch preparation on the main run loop

**Status:** CONFIRMED  
**Locations:** `pccontrol/Scheduler.xm:121-132,152-200`; `pccontrol/Play.xm:23-61`

**Current behavior**

The only interval validation is `interval > 0`. The timer is an `NSTimer` scheduled on the main run loop. Every fire:
1. performs a scheduler license check,
2. calls `playScript`,
3. `playScript` synchronously logs the path,
4. checks/reads `script_play_settings.plist`,
5. allocates path/config objects,
6. then reaches `ScriptPlayer play`, which may simply report that another script is already running.

Therefore a valid repeating timer with a very small positive interval can repeatedly perform license/config/logging work on the main thread even while no new script can start.

**Impact**
- Main-thread CPU: potentially Critical.
- Wakeups/battery: potentially Critical for small intervals.
- UI/touch responsiveness: high risk because the callback runs on the main run loop.
- Disk/config reads: scale with timer fire frequency.

Exact device impact is **INSUFFICIENT DATA** until interval stress tests are run, but the unbounded frequency and synchronous callback work are source-confirmed.

**Recommended fix**

- Define a documented minimum interval appropriate to the product contract.
- Apply timer leeway/coalescing.
- Before expensive launch preparation, cheaply reject when a script/session cannot be launched.
- Keep scheduler bookkeeping off the main thread if using a serial dispatch-source scheduler; only cross to main for UIKit work that actually requires it.
- Never compensate by busy waiting or high-frequency polling.

**Benchmark**

Test repeat intervals 1 ms / 10 ms / 100 ms / 1 s with:
- no script running,
- a long script already running.

Measure main-thread CPU, wakeups/s, timer fires/s, license checks/s, plist reads/s, `playScript` calls/s and UI frame stalls.

---

## P1 — S007 High Priority

### [P1-48] Run-history index embeds failure evidence and is fully read/parsed/re-written on every begin/finish

**Status:** CONFIRMED  
**Locations:** `shared/TLinkRunHistory.mm:106-131,209-242,255-334`

History retention is capped at 50 runs, but every index record can contain full failure evidence including up to 50 log-tail lines of up to 1000 characters each.

At the configured bounds, 50 failed records can contain about **2.5 million ASCII log characters** in the index before JSON/object metadata. UTF-8/escaping can make encoded bytes larger.

Every script begin:
- reads/parses the entire index,
- inserts one record,
- pretty-serializes/writes the individual record,
- pretty-serializes/atomically rewrites the entire index.

Every finish repeats the full index read/rewrite; failed finishes also write an evidence JSON.

**Impact**
- Write amplification grows with retained history.
- CPU/allocation grows with JSON size.
- Battery/storage cost grows for timer-driven or short repeated scripts.
- Atomic whole-file writes increase temporary I/O beyond logical delta size.

**Recommended direction**

Keep the status index compact:
- metadata only in index,
- log-tail/evidence only in per-run evidence files,
- optionally cache the 50-record metadata index in memory with a cross-process generation/mtime check,
- use compact JSON for machine state unless pretty printing is specifically required.

Preserve the cross-process file lock or replace it with an equally strong transactional owner.

---

### [P1-49] Failed-run evidence preprocessing occurs while holding the cross-process history flock

**Status:** CONFIRMED  
**Locations:** `shared/TLinkRunHistory.mm:134-185,255-334`

`TLinkRunHistoryFinish` acquires the process lock + cross-process `flock` before:
- compiling two regular expressions repeatedly in `TLinkRunHistoryRedactText`,
- redacting up to 50 log lines,
- if no supplied tail, opening/seeking/reading up to 256 KiB from the console log,
- splitting the log,
- probing/chmod/lchown of screenshot evidence,
- JSON-building the evidence object.

The regex objects are created anew for every text redaction. With 50 retained tail lines plus the main error, a failed finish can compile the same regex patterns more than 100 times while the history lock is held.

**Impact**
- Cross-process history begin/snapshot/finish operations block behind work unrelated to index mutation.
- Failure paths become especially expensive under large console logs.
- Lock hold time includes filesystem latency from a separate console file.

**Recommended fix**

Precompute failure evidence outside the history file lock:
- static/dispatch_once compiled regexes,
- bounded log read/redaction outside the lock,
- screenshot metadata preparation outside the lock.

Then acquire the history lock only for read-modify-write/prune of history state.

---

### [P1-50] Per-run JavaScript console logs have no run-count/byte retention and are not pruned with run history

**Status:** CONFIRMED  
**Locations:** `pccontrol/jsruntime/TLinkJSRuntimeCore.mm:194-210`; `pccontrol/TLinkautoJSRuntime.mm:650-659`; `shared/TLinkRunHistory.mm:188-205`

Every in-process JS run creates `<bundle>/_logs/<runId>.log`; helper runs similarly create per-run helper logs. Individual files are approximately size-bounded by the logger rotation behavior, but the **number of per-run files is unbounded**.

Run-history pruning only removes paths under `/var/mobile/Library/TLinkauto/run-history/`. Console logs live under each script bundle's `_logs` directory, so pruning a history record cannot remove them. Successful run logs are not referenced by failure evidence at all.

**Impact**
- Disk usage grows linearly with total JS run count.
- Directory enumeration/backup/storage-management cost grows over long-lived devices.
- Worst-case rough bound is about 0.5 MiB per retained run-log file times unbounded run count, excluding helper/latest files.

**Recommended fix**

Define retention by both:
- maximum run-log files per bundle, and
- maximum total log bytes.

Delete oldest completed run logs only after the active run closes its writer. Keep `latest.log` separately. If history needs a referenced failure log, either copy bounded evidence into the run-history evidence file or coordinate retention by run ID.

---

### [P1-51] Status task synchronously re-reads persistence files on every request

**Status:** CONFIRMED  
**Locations:** `pccontrol/Task.xm:1502-1586`; `shared/TLinkRunHistory.mm:349-416`; `shared/TLinkEventChannel.mm:198+`

`TASK_HELLO_STATUS` builds `run_history` using `TLinkRunHistorySnapshot(20)` and also queries event-channel status. Run-history snapshot:
- ensures directories/ownership,
- opens/acquires the history lock,
- reads/parses `index.json`,
- copies/truncates status records,
- releases the lock.

Event-channel status separately acquires its journal lock and reads/parses `journal.json`.

A UI/dashboard that polls status therefore converts status frequency directly into synchronous filesystem/JSON work on the request path.

**Impact**

Frequency in deployed clients is **INSUFFICIENT DATA**. At multi-Hz polling this can become measurable CPU/storage-cache pressure and add ingress latency.

**Recommended direction**

Maintain an in-memory immutable diagnostics snapshot/generation updated by begin/finish/event mutations. Status should read memory in the common case; reload from disk only on generation/mtime change or process startup.

---

### [P1-52] Auto-launch plist updates are unlocked read-modify-write transactions

**Status:** CONFIRMED  
**Location:** `pccontrol/Scheduler.xm:53-110`

Each set operation:
1. reads the whole plist into a mutable dictionary,
2. changes one key,
3. atomically rewrites the whole file.

Atomic replacement protects file integrity but does **not** protect the read-modify-write transaction. Two concurrent callers can read the same old version, write different updates, and the later rename loses the earlier change.

The same root path is also used by other project components, so cross-process coordination matters if those components coexist; deployment overlap is not assumed here.

**Recommended fix**

Use a scheduler/config owner queue plus a cross-process lock or a single authoritative service for this shared file. Persist a generation/revision to support cache invalidation.

**Benchmark/repro**

Issue concurrent updates to distinct names from 2/8/32 clients for 10k rounds. Verify all acknowledged keys survive.

---

### [P1-53] Run-history persistence failures are largely ignored, allowing in-memory/event state to claim success after disk failure

**Status:** CONFIRMED  
**Locations:** `shared/TLinkRunHistory.mm:115-131,237-250,317-344`

`TLinkRunHistoryWriteJSON` and `TLinkRunHistoryWriteIndex` return BOOL, but begin/finish do not check those results. The code can:
- return a run record/run ID,
- publish `script.run started/finished` to the event journal,
while record/index/evidence persistence failed.

This can also leave orphan per-run/evidence files after partial failure.

**Recommended fix**

Treat history mutation as a small transaction:
- check individual record/evidence/index writes,
- define commit point,
- publish event only after successful commit,
- surface a bounded diagnostics counter/error without failing the actual script unless product semantics require history to be mandatory.

---

## P2 — S007 Medium / Contract Findings

### [P2-14] Rootfull timers are process-lifetime only and are not restored after SpringBoard restart

**Status:** CONFIRMED implementation behavior; whether persistence is required is **INSUFFICIENT DATA**  
**Location:** `pccontrol/Scheduler.xm:11,113-224`

Timer definitions live only in `timerRegistry`; there is no timer persistence or startup restore in the audited rootfull scheduler. SpringBoard/tweak restart therefore removes all timers.

If the intended contract is process-lifetime scheduling, document it. If timers should survive restart, persist normalized timer definitions and define missed-fire/catch-up behavior explicitly.

---

### [P2-15] No rootfull pccontrol consumer of autolaunch.plist was found in the audited scope

**Status:** HIGH-CONFIDENCE within `pccontrol`; deployment-wide behavior is **INSUFFICIENT DATA**

The rootfull scheduler exposes set/list persistence for `/var/mobile/Library/TLinkauto/autolaunch.plist`, but no `pccontrol` startup path referencing `autolaunch.plist` was found. A separate TrollStore/streamd implementation does have startup consumption, but that is outside the rootfull S007 target.

Before changing semantics, verify whether another installed rootfull component is intentionally responsible for consuming this file. If not, the rootfull auto-launch API currently persists configuration without executing it at startup.

---

### [P2-16] Run-history duration uses wall-clock time

**Status:** CONFIRMED  
**Location:** `shared/TLinkRunHistory.mm:31-34,276-283`

`started_at_ms`, `ended_at_ms` and `duration_ms` all derive from `NSDate` wall time. A backward clock adjustment clamps duration to zero; a forward adjustment inflates it.

Keep wall timestamps for human-readable history, but compute duration from monotonic/continuous time captured in-process when possible.

---

### [P2-17] Snapshot does not handle history-lock acquisition failure before reading the index

**Status:** CONFIRMED  
**Location:** `shared/TLinkRunHistory.mm:349-355`

Unlike begin/finish, snapshot does not check `lockFd < 0` before reading. Atomic index replacement reduces corruption risk, but diagnostics can silently read without the intended cross-process synchronization.

Return an explicit degraded/error snapshot or use a cached last-known-good snapshot.

---

### [P2-18] Directory creation/chmod/lchown is repeated for every begin/finish/snapshot

**Status:** CONFIRMED  
**Location:** `shared/TLinkRunHistory.mm:74-83`

Every history operation calls createDirectory + chmod + lchown for root/runs/evidence, including read-only status snapshots. This is unnecessary metadata work in the steady state.

Perform initialization once per process and retry only after an actual missing-path/error condition.

---

## S007 prioritization by expected gain × frequency × cost

1. **P0-15** scheduler ownership/generation fix — correctness and ghost-timer elimination.
2. **P0-16** minimum interval + coalescing + cheap busy rejection — main-thread CPU/wakeup protection.
3. **P1-48/P1-49** compact run-history index and shorten file-lock critical section.
4. **P1-50** bounded per-run log retention.
5. **P1-51** memory-backed status snapshots for polling clients.
6. **P1-52/P1-53** transactional config/history persistence.
7. **P2-14..18** restart semantics, wall-clock duration and metadata cleanup.

### Reviewed non-findings

- Run-history record count itself is bounded at 50 and pruning removes run-history record/evidence/screenshot artifacts.
- The history module uses both an in-process lock and a cross-process `flock`, which is the right basic coordination direction; the problem is critical-section size and write amplification, not absence of cross-process locking.
- Scheduler does not busy-wait when timers are idle; the idle problem is user-configurable wakeup frequency and main-runloop work, not a polling loop.



---

# S008 Addendum — Event Channel / Task 95 Long Poll

## P0 — Additional Critical Findings

### [P0-17] Idle long-poll performs filesystem metadata + lock + full journal read/JSON parse every 100 ms

**Status:** CONFIRMED  
**Locations:** `shared/TLinkEventChannel.mm:21-24,72-130,198-305`  
**Consumer evidence:** `webtango/src/services/tlinkautoSdk.ts:93-153,1011-1039`

**Current behavior**

`TLinkEventChannelPoll` implements long polling as a loop:

1. `TLinkEventReadBatch`
2. if no event, `usleep(100000)`
3. repeat until event/gap/timeout.

Every `TLinkEventReadBatch`:
- calls `TLinkEventEnsureDirectory`,
- `createDirectoryAtPath`,
- `chmod` + `lchown` the directory,
- opens the lock file,
- `chmod` + `lchown` the lock file,
- takes an exclusive `flock`,
- reads all of `journal.json`,
- reparses JSON into Foundation containers,
- scans events,
- unlocks/closes.

This happens even when no event has changed.

Default client timeout is 20 seconds; max is 25 seconds. WebTango's `subscribeEvents` uses the 20-second default and immediately issues the next long poll after each batch/timeout.

**Quantified source-level rate**

One idle poller: about **10 journal polls/second**.

At the configured maximum of 8 concurrent polls: up to about **80 directory/lock/journal polling cycles per second** while there are no events.

A 20-second idle request can execute roughly ~200 journal read/parse cycles; a 25-second request roughly ~250.

**Impact**
- Idle CPU: Critical relative to the near-zero-idle requirement.
- Filesystem metadata activity: Critical for an idle subscription.
- Battery/wakeups: High.
- Event latency: adds roughly 0–100 ms detection latency by design.
- Publisher latency: exclusive read locks contend with publication.

**Recommended direction**

Replace file polling with event-driven notification:
- keep the journal as durable/replay state,
- maintain an in-process immutable journal/generation snapshot,
- signal local waiters with a condition/semaphore,
- use a cross-process notification/generation mechanism when another process publishes,
- reload the file only when generation changes.

A Darwin notification or equivalent cross-process wake can be used only as a wake signal; cursor replay/durability should still come from the journal/generation state.

Initialize directory/permissions once, not every read iteration.

Do **not** lower the 100 ms interval as a latency fix; that would worsen CPU/battery.

---

### [P0-18] Disconnected event subscribers do not cancel their long-poll worker or release capacity until timeout/event

**Status:** CONFIRMED  
**Locations:** `tlinkauto-binary/SocketServer.mm:87-150,163-191`; `shared/TLinkEventChannel.mm:276-306`  
**Consumer stop path:** `webtango/src/services/tlinkautoSdk.ts:150-153`

The deferred Task-95 worker runs `TLinkEventChannelPollBody` on a global queue.

On client disconnect, socket cleanup:
- clears `ctx.eventPollPending`,
- sets streams to NULL,
- closes/releases the normal stream ownership,

but there is no cancellation token passed to `TLinkEventChannelPoll`.

The worker retains its own CFWriteStream reference and continues the 100 ms polling loop until:
- an event/gap arrives, or
- the 20–25 second timeout expires.

`sTLinkEventActivePolls` is decremented only when that loop returns.

**Impact**

Eight clients can start polls and disconnect; those abandoned workers can keep all 8 configured poll slots occupied for up to the request timeout. New subscribers then receive `event_poll_capacity_reached` despite no live subscriber actually waiting.

The abandoned workers also continue the P0-17 filesystem polling load after disconnect.

**Recommended fix**

Give every deferred poll a cancellation token/generation tied to `ZXClientContext`.
- Cleanup cancels the token.
- Poll wait checks cancellation immediately after wake and before any filesystem reload.
- Capacity counter is released on cancellation.
- The retained stream is released promptly.

An event-driven wait primitive should support cancellation directly rather than sleeping in 100 ms chunks.

**Benchmark/repro**

Start 8 max-timeout polls, close all sockets immediately, then open a ninth poll. Measure:
- active poll count after disconnect,
- time until capacity returns,
- journal read cycles after disconnect,
- retained worker/thread count.

Acceptance: capacity and idle I/O return to baseline immediately after disconnect cleanup.

---

## P1 — S008 High Priority

### [P1-54] Every event publication rewrites the complete 256-event journal under an exclusive file lock

**Status:** CONFIRMED  
**Location:** `shared/TLinkEventChannel.mm:122-190`

Each publish:
- takes the process lock,
- acquires exclusive file flock,
- reads/parses the complete journal,
- mutable-copies the event array,
- appends one event / removes oldest entries,
- serializes the entire journal,
- atomically rewrites `journal.json`.

Each event payload may serialize to as much as 4096 bytes before being replaced by the truncation marker. Therefore 256 retained payloads alone can approach roughly **1 MiB** before event metadata/JSON syntax.

A single small new event can therefore cause an O(journal-size) read/parse/write transaction.

**Impact**
- Write amplification: High when publication frequency rises.
- Publisher latency: serialized behind all poll read locks.
- Storage/battery: Medium/High depending event frequency.
- Run-history coupling: run begin/finish calls publish synchronously, so event-journal contention can extend script-history latency.

Current publishers are run-history events plus adaptive stream state changes; normal frequency is not per-frame, so exact deployed cost is **INSUFFICIENT DATA**.

**Recommended direction**

Use an append-oriented journal or a compact fixed/ring representation with bounded recovery.
For the lowest-risk first step:
- keep an in-memory 256-event ring in the owner process,
- persist append/checkpoint in bounded batches,
- retain cross-process sequence/generation semantics,
- compact asynchronously outside latency-sensitive callers.

Do not sacrifice cursor durability without an explicit crash-recovery policy.

---

### [P1-55] Long polls park up to eight global libdispatch worker threads in repeated usleep

**Status:** CONFIRMED  
**Locations:** `tlinkauto-binary/SocketServer.mm:105-114,139-149`; `shared/TLinkEventChannel.mm:295-305`

Each deferred poll is dispatched to the default global queue, and its long-poll implementation repeatedly calls blocking `usleep(100 ms)`.

At the configured capacity, up to 8 long-lived global-queue blocks can remain active for 20–25 seconds and repeatedly sleep/wake.

**Impact**
- thread/stack resource footprint,
- libdispatch worker occupancy,
- wakeups every 100 ms,
- extra scheduling pressure when the daemon is handling IPC/socket/H264-adjacent work.

**Recommended direction**

Use a condition/event-driven wait that parks without periodic wakeups, ideally on a dedicated event subsystem rather than default global worker blocks.

Measure actual worker/thread count before and after; exact stack/RSS cost is **INSUFFICIENT DATA** until Instruments/VM Tracker.

---

### [P1-56] Task-95 response path performs base64/legacy reparse layering and can block the daemon's global socketQueue on a large synchronous write

**Status:** CONFIRMED  
**Locations:** `tlinkauto-binary/SocketServer.mm:74-84,118-149,660-675`

Legacy Task 95 response:
- serializes batch dictionary to JSON NSData,
- base64-encodes the JSON to NSString,
- formats `0;;<base64>\r\n`,
- creates another NSData.

JSON-v1 path then:
- calls that same legacy response builder,
- decodes it into NSString,
- splits the legacy `;;` protocol into a response dictionary,
- serializes that dictionary into another JSON frame.

When the poll completes, response writing is dispatched to the daemon's single serial `socketQueue` and uses synchronous `CFWriteStreamWrite`.

With max 32 events and 4096-byte payload quota, payload bytes alone can total **128 KiB** before event metadata. Base64 expands this by roughly 4/3 before the JSON-v1 wrapper.

This is a Task-95-specific amplifier of existing **P1-16** global synchronous response-write HOL blocking.

**Recommended direction**

Return a typed event batch directly to each wire encoder:
- legacy adapter may base64 only if protocol requires it,
- JSON-v1 should encode the batch object directly rather than wrapping/reparsing legacy text.

Use the bounded per-client output/drain model already recommended in S003 instead of synchronous `zx_writeAll` on `socketQueue`.

---

### [P1-57] Poll readers use exclusive flock, serializing all idle readers with publishers

**Status:** CONFIRMED  
**Location:** `shared/TLinkEventChannel.mm:83-103,198-259`

Read-only polling takes `LOCK_EX`, not a shared lock. At up to 80 polling cycles/s, every idle reader serializes with every other reader and with publishers.

Changing to `LOCK_SH` alone would not solve P0-17 because all readers would still hit disk/JSON repeatedly, but it illustrates that the current file lock is being used as both consistency and notification mechanism.

**Recommended direction**

Fix the architecture with generation-backed cached state + notification. If file-based reads remain, use shared/exclusive semantics correctly and keep write transactions bounded.

---

### [P1-58] Journal corruption/parse failure silently presents an empty new journal and can reset sequence on the next publish

**Status:** CONFIRMED robustness behavior  
**Locations:** `shared/TLinkEventChannel.mm:105-120,159-190`

If `journal.json` is unreadable or invalid JSON, `TLinkEventReadJournal` returns a fresh in-memory journal with `next_sequence=1` and no explicit error.

A later publish can then atomically overwrite the bad journal with sequence 1, permanently discarding the previous replay state.

Existing clients with a higher cursor will eventually observe `gap`, but diagnostics do not distinguish corruption/reset from normal cursor mismatch.

**Recommended fix**

Quarantine malformed journal files, increment a corruption/reset diagnostic, and publish a new generation/epoch. Cursor identity should include generation/epoch so clients can explicitly resynchronize after reset.

Atomic writes already reduce corruption probability; this is robustness rather than a normal hot path.

---

## P2 — S008 Medium Findings

### [P2-19] Long-poll timeout uses wall-clock NSDate with unsigned subtraction

**Status:** CONFIRMED  
**Location:** `shared/TLinkEventChannel.mm:34-37,295-303`

Timeout elapsed time is `TLinkEventNowMs() - startedAt` using unsigned wall-clock milliseconds.

A backward clock adjustment can underflow and appear as a huge elapsed duration, causing immediate timeout; a forward jump can also expire the poll early.

Use a monotonic/continuous clock for timeout budgeting. Event timestamps can remain wall-clock.

---

### [P2-20] Topic validation recompiles the same regular expression for every poll request

**Status:** CONFIRMED  
**Location:** `shared/TLinkEventChannel.mm:309-351`

`NSRegularExpression regularExpressionWithPattern:` is created on every Task-95 request. This is one-time per long-poll request, not every 100 ms iteration, so severity is low.

Compile once with `dispatch_once` or replace with a simple bounded ASCII token validator.

---

### [P2-21] Topic-filtered batches can cause an extra immediate empty round trip after a matched event

**Status:** CONFIRMED protocol inefficiency  
**Location:** `shared/TLinkEventChannel.mm:225-245`

When at least one matching event is selected but fewer than `maxEvents`, `next_cursor` is the last selected sequence even if later journal events are all non-matching. The next filtered poll then scans those later unrelated events, returns an empty batch with `next_cursor=latest`, and only the following poll truly waits.

Correctness is preserved, but filtered subscribers can incur an avoidable immediate request/response after mixed-topic batches.

Because the scan has already examined the full retained journal when `selected.count < maxEvents`, it can safely advance the cursor through later known non-matching events while preserving matching-event delivery.

---

## S008 source-derived load model

Default continuous WebTango subscription:
- timeout: 20 s,
- poll loop interval inside daemon: 100 ms,
- after timeout/batch: client immediately sends the next poll.

Therefore one quiet subscription is not idle from the daemon/filesystem perspective; it is roughly a 10 Hz persistence poller.

Configured maximum:
- 8 concurrent polls/process,
- up to ~80 persistence poll cycles/s while quiet,
- each can perform directory/lock metadata syscalls + exclusive flock + journal read + JSON parse.

These are source-derived operation-rate estimates, not measured CPU percentages.

## S008 prioritization by expected gain × frequency × cost

1. **P0-17** event-driven wait + cached generation — largest idle CPU/wakeup/filesystem win.
2. **P0-18** cancellation tied to client lifecycle — capacity/ghost-worker correctness.
3. **P1-55/P1-57** remove sleeping global workers/exclusive read locking as part of the same redesign.
4. **P1-54** append/checkpoint or bounded ring persistence to remove whole-journal rewrite amplification.
5. **P1-56** direct typed wire encoding + bounded per-client output.
6. **P1-58** explicit journal generation/corruption recovery.
7. **P2-19..21** monotonic timeout and request-path cleanup.

### Reviewed non-findings

- Task 95 is deliberately deferred off the daemon's serial `socketQueue`; the 20-second wait itself does **not** directly block all socket parsing. The problem is the polling worker/I/O and the synchronous response write when it completes.
- Per-client `eventPollPending` prevents two simultaneous Task-95 polls on the same connection.
- Event retention is count-bounded at 256 and individual event payloads are bounded at 4096 serialized bytes.

---

# S009 Addendum — VPN / Accessibility Live Rootfull Paths

## P0 — Additional Critical Findings

### [P0-19] Task 59 has an inverted timeout hierarchy: the daemon gives up after 5 s while SpringBoard can remain blocked in the VPN broker path for 8–30 s

**Status:** CONFIRMED  
**Locations:** `tlinkauto-binary/SocketServer.mm:445-489`, `pccontrol/IPCMessagePort.xm:56-98,142-156`, `pccontrol/Connectivity.xm:75-143,270-341`, `pccontrol/Task.xm:1490-1500`, `vpn-broker/main.mm:23-36,52-100`

The rootfull Task-59 path is synchronous across three nested transports:

1. daemon -> SpringBoard CFMessagePort,
2. SpringBoard -> localhost TCP broker on port 6014,
3. broker -> asynchronous NEVPNManager operation converted back into a synchronous wait.

The daemon waits only **5 seconds** for a response from SpringBoard. The VPN broker intentionally waits:
- 8 s for query,
- 8 s for diagnostics status,
- 24 s for connect/disconnect,

while SpringBoard's broker socket has 30 s send/receive timeouts.

Therefore a legitimate VPN transition can outlive the daemon's synchronous request contract. The caller can receive an IPC timeout after 5 s while the SpringBoard CFMessagePort callback remains occupied by the old Task 59 and the broker operation continues.

This is an amplifier of S003 **P1-14**: the dedicated SpringBoard CFMessagePort thread executes `processTask` synchronously, so the abandoned VPN task can delay unrelated subsequent SpringBoard IPC. It also creates ambiguous retry semantics because the client may retry an operation that is still running.

**Recommended direction**

Do not carry long VPN transitions synchronously through the SpringBoard CFMessagePort:
- route rootfull VPN control directly from the daemon to the broker where possible, or
- use an asynchronous operation ID/deferred-result contract,
- make outer timeout >= inner timeout only as a temporary compatibility fallback,
- propagate cancellation where safe,
- make connect/disconnect retries idempotent and observable.

A 30 s outer timeout alone would hide the mismatch but preserve the IPC head-of-line problem.

**Benchmark/repro**

See `BENCHMARK-S009.md` Probe A.

---

### [P0-20] UI find/tap materializes a full AX snapshot before matching, and `max_elements` bounds returned rows rather than scanned AX work

**Status:** CONFIRMED  
**Locations:** `shared/TLinkAccessibilityTree.mm:524-593,604-702,722-786`, `pccontrol/Task.xm:731-817`

Each serialized AX element can perform six synchronous attribute queries:
- frame,
- label,
- value,
- identifier,
- traits,
- activation point.

Snapshot traversal stops on:

`rows.count >= maxElements`

rather than on `scanned >= maxElements`. Because visibility/clickability filtering occurs only **after** full element serialization, a hidden/offscreen-heavy source tree can scan and query substantially more than the requested element count until the time deadline is reached.

Task 79/81 then add another layer of amplification:
1. build the full snapshot dictionary array,
2. iterate that snapshot again,
3. build a `matches` array containing all matches,
4. only then select the requested index.

Even when the desired element is the first source element, find/tap cannot short-circuit. Task 81 additionally requires a complete/non-truncated snapshot before acting, so early target discovery gives no latency win.

This work runs behind the single AX serial queue and is invoked synchronously from the SpringBoard IPC task path, so expensive trees also amplify IPC/AX queue head-of-line latency.

**Recommended direction**

Split snapshot and selector execution:
- keep Task 78 as a bounded snapshot operation,
- implement Task 79/81 as a single-pass selector scan,
- fetch cheap selector attributes first and fully serialize only the selected candidate,
- add an independent hard `max_scanned_elements` budget,
- stop once the requested match index is satisfied when action semantics permit,
- preserve explicit partial/truncated semantics where completeness is required.

**Benchmark/repro**

See `BENCHMARK-S009.md` Probes D and E.

---

## P1 — S009 High Priority

### [P1-59] One slow or abandoned AX operation serializes all UI-tree work and has no client-cancellation path

**Status:** CONFIRMED  
**Locations:** `shared/TLinkAccessibilityTree.mm:35-44,696-702,766-786,799-863`, `pccontrol/Task.xm:731-817,823-853`

Snapshot, find and hit-test all enter one process-wide serial `TLinkAXQueue` through `dispatch_sync`.

Tasks 77–81 do not receive or consult the `TLinkTaskExecutionContext` cancellation state. If the requesting socket/client disappears after dispatch, current AX work continues until it completes or reaches its own timeout, and later AX callers remain queued behind it.

The per-operation timeout is bounded, so this is not an infinite loop, but a sequence of abandoned 1.5–3 s requests can still create avoidable queue buildup and responsiveness loss.

**Recommended direction**

Carry cancellation/deadline state into AX traversal and check it:
- before entering expensive work,
- between elements,
- before additional attribute groups,
- before response serialization.

Use bounded admission/queue metrics rather than spawning parallel AX traversals blindly; AX ordering/remote-service behavior should remain serialized unless device testing proves safe concurrency.

---

### [P1-60] UI-tree responses have element-count limits but no explicit byte/string limit and are fully copied through JSON + base64 + legacy text

**Status:** CONFIRMED  
**Locations:** `shared/TLinkAccessibilityTree.mm:564-593,619-693`, `pccontrol/Task.xm:706-720`

Task 78 can return up to 1000 serialized elements, but label/value/identifier strings are not length-bounded and there is no response byte ceiling.

The result exists simultaneously through multiple representations:
- Foundation dictionary/array graph,
- JSON `NSData`,
- base64 `NSString`,
- final `0;;...\r\n` response string / CFWriteStream storage.

Element count therefore does not provide a reliable memory or transport bound.

**Recommended direction**

Add:
- per-string byte/character caps with explicit truncation flags,
- raw JSON byte budget,
- final wire byte budget,
- predictable partial/truncated response semantics.

For structured local/in-process callers, avoid base64/legacy text when a typed result can be returned directly.

---

### [P1-61] Every AX operation rebuilds lock-state plumbing; capability probes also repeat Security entitlement discovery

**Status:** CONFIRMED  
**Locations:** `shared/TLinkAccessibilityTree.mm:45-100,153-194,604-617,799-816`

`TLinkAXLockState` is called for snapshot and hit-test and performs, per call:
- two `notify_register_check` / get-state / cancel sequences,
- `dlopen` of SpringBoardServices,
- `dlsym` of lock-state functions.

The framework handle/symbols are not cached in that function.

Task 77 capability additionally calls `TLinkAXEntitlementValue` three times; each call reopens Security, resolves the same two symbols, creates a SecTask and copies one entitlement.

These are stable process capabilities mixed into potentially repeated runtime probes.

**Recommended direction**

Cache framework handles/symbol pointers and stable entitlement capability values once per process. Keep only the mutable lock/screen state live. Prefer persistent notify tokens or a cached notification-backed state if measurements show registration churn is material.

---

### [P1-62] Frequent Task-60 status snapshots redo ten VPN entitlement queries plus mutable compatibility filesystem probing

**Status:** CONFIRMED  
**Locations:** `shared/TLinkVPNDiagnostics.mm:68-202,234-330,333-386`, `pccontrol/Task.xm:1502-1556`

Every `TLinkVPNDiagnosticsSnapshot` calls `TLinkVPNEntitlementProbe`.

That probe creates a new SecTask and performs **10** `SecTaskCopyValueForEntitlement` calls. The private compatibility snapshot also checks the ownership marker path with `fileExistsAtPath`.

Task 60 calls this complete diagnostics snapshot as part of every hello/status response. S007 already established status as a polling-capable client path, so immutable capability discovery is unnecessarily placed on a repeatable status hot path.

**Recommended direction**

Split diagnostics into:
- process-lifetime immutable capabilities: entitlements, framework/class/symbol availability,
- mutable VPN state: connected/configured/broker health/owned marker where relevant.

Publish/cache the immutable half once and refresh only state that can actually change.

**Benchmark/repro**

See `BENCHMARK-S009.md` Probe C.

---

### [P1-63] VPN broker converts async operations into blocking global-queue workers and has no explicit concurrent-client cap

**Status:** CONFIRMED  
**Locations:** `vpn-broker/main.mm:23-36,52-100,164-236`

Each accepted broker client is handled on a global utility queue. Query/diagnostics/connect-disconnect then call `TLinkVPNBrokerWait`, which blocks that worker in `dispatch_semaphore_wait` for up to 8 or 24 seconds.

There is no source-visible active-client/long-operation admission cap.

The broker is localhost-only, which limits exposure, but bursts/retries from local components can still consume multiple libdispatch workers while NetworkExtension work is pending.

**Recommended direction**

Keep one owned VPN state machine/queue and complete client requests asynchronously, or enforce a small explicit admission limit with coalescing for equivalent status requests. Do not solve this by creating dedicated threads per connection.

---

### [P1-64] Successful UI-tree tasks resolve foreground context twice and can synchronously cross onto SpringBoard main thread both times

**Status:** CONFIRMED  
**Locations:** `shared/TLinkAccessibilityTree.mm:385-460`, `pccontrol/Task.xm:723-817`, `pccontrol/IPCMessagePort.xm:142-156`

The SpringBoard IPC server runs on a dedicated NSThread. `TLinkAXSpringBoardProcessContext` therefore uses `dispatch_sync(dispatch_get_main_queue(), query)` to obtain the frontmost application.

`zx_handleUITreeTask` calls foreground-context resolution:
1. before Task 78–81,
2. again after successful AX work through `zx_uiTreeContextChanged`.

A successful request can therefore synchronously wait on SpringBoard main twice. Under main-thread pressure this expands the duration for which the IPC callback remains occupied.

**Recommended direction**

Measure first. If material:
- return a cheap foreground generation/token from the first main-thread query,
- validate that token with the smallest possible second query,
- avoid repeated process-table or object discovery,
- impose/propagate the request deadline around main-thread crossings.

Do not remove the post-operation context-change safety check without an equivalent race guard.

---

## P2 — S009 Medium Findings

### [P2-22] AX operation deadline uses wall-clock `CFAbsoluteTimeGetCurrent` and is checked only between elements

**Status:** CONFIRMED  
**Location:** `shared/TLinkAccessibilityTree.mm:619-669`

The snapshot deadline is computed from `CFAbsoluteTimeGetCurrent` and checked before each element. A wall-clock adjustment can distort the deadline, and a single AX RPC group may run beyond the deadline before the loop regains control.

Use a monotonic/continuous clock for duration budgeting. Treat the per-element AX messaging timeout as an explicit maximum-overshoot component and check cancellation/deadline between attribute groups where practical.

---

### [P2-23] Foreground PID fallback can scan every process and read app Info.plist files on failure paths

**Status:** CONFIRMED fallback-path cost  
**Location:** `shared/TLinkAccessibilityTree.mm:221-281,462-486`

When direct/in-process foreground resolution cannot provide a PID, `TLinkAXPIDForBundleID`:
- fetches `KERN_PROC_ALL`,
- iterates processes,
- calls `proc_pidpath`,
- derives app bundle paths,
- loads each candidate `Info.plist`.

The injected SpringBoard path normally avoids this, so this is not a steady-state P0/P1 hot path. During transitions/private-API failure, however, repeated UI requests can pay a full process scan.

Cache last known bundle->PID with liveness validation or use a cheaper authoritative SpringBoard process identifier before falling back to filesystem-backed enumeration.

---

## S009 rootfull scope exclusions / reviewed non-findings

- The `TLINK_VPN_TROLLSTORE_RUNTIME` private VPNConnectionStore polling paths and `TLinkVPNRunPrivateConfigurationHelper`/`waitpid` behavior are compile-time TrollStore compatibility paths, not the primary rootfull Task-59 broker route. They were inspected only to establish reachability and are deferred to the dedicated TrollStore compatibility pass.
- The rootfull public `NEVPNManager` connect/disconnect implementation is event-driven via `NEVPNStatusDidChangeNotification` plus `dispatch_after` timeout; it does not use the 100 ms private-backend polling loop.
- AXRuntime/libAccessibility symbol discovery in `TLinkAXPrepare` is already protected by `dispatch_once`; the repeated setup issue is specifically lock-state/Security capability plumbing outside that initializer.
- AX CF objects created for root/hit elements are released on normal/error paths reviewed in S009; no new retained AX-element leak was confirmed.
- Task 81's conversion of activation point back into a legacy native-tap string is adjacent to existing internal string/parser findings and is not numbered again here.

## S009 prioritization by expected gain × frequency × cost

1. **P0-19** remove long VPN transitions from synchronous SpringBoard CFMessagePort request lifetime / repair timeout hierarchy.
2. **P0-20** implement bounded single-pass AX selector execution and a hard scanned-work budget.
3. **P1-59/P1-60** cancellation/admission + result-byte bounds for AX work.
4. **P1-62** cache static VPN diagnostics capabilities out of Task-60 polling.
5. **P1-63** remove blocking broker-worker semaphore architecture or explicitly cap/coalesce it.
6. **P1-64/P1-61** minimize measured main-thread/probe setup overhead while preserving correctness.
7. **P2-22/P2-23** monotonic deadline and fallback-path cleanup.

---

# S010 Addendum — AppDelegate / TrollStore Compatibility

## P0 — Additional Critical Findings

### [P0-21] TouchPOC tunnel TCP server polls an idle nonblocking client every 5 ms on the same serial queue that must accept new clients

**Status:** CONFIRMED in the separately built `TouchPOC.tipa` compatibility artifact  
**Locations:** `poc-trollstore/TunnelExtension/ProviderTCPServer.mm:25-110`  
**Artifact reachability:** `.github/workflows/poc-trollstore.yml:64-105,109-145`

The provider TCP server creates one serial queue and attaches its listen-socket dispatch source to that queue.

After accepting a client, `acceptOne` enqueues `readLoop:` back onto the **same serial queue**. The client socket is nonblocking. When the client has no data, `readLoop:` performs:

`recv -> EAGAIN/EWOULDBLOCK -> usleep(5000) -> retry`

until the peer closes or sends a complete line.

Therefore one connected idle client produces a source-visible upper cadence of roughly **200 sleep/wake polling iterations per second**. More importantly, because `readLoop:` owns the serial queue for the entire client lifetime, the listen dispatch source cannot run its next accept handler until that client finishes.

Additional lifecycle amplification:
- the accumulation buffer has no explicit byte ceiling before newline,
- `stop` cancels the accept source and closes only the listen fd,
- the currently active client fd is not tracked by `stop`, so an established idle read loop can outlive server stop until the peer closes/errors.

**Recommended direction**

Use an event-driven per-client read source/stream:
- keep the accept queue free,
- create a bounded client context per fd,
- wake only when bytes/EOF/error are available,
- impose request-size and idle/deadline limits,
- track and close active client fds during stop.

Do not replace the 5 ms loop with a larger sleep; remove polling entirely.

**Benchmark/repro**

See `BENCHMARK-S010.md` Probe A.

---

### [P0-22] TrollStore `vpnconf.create` can block a script indefinitely in `waitpid(..., 0)` after cancellation has already become impossible to observe

**Status:** CONFIRMED live StreamControl TrollStore path  
**Locations:**  
- caller/helper transport: `shared/TLinkVPNPrivateRequest.mm:55-250`  
- JS API edge: `stream-app/streamd/POCSocketServer.mm:2191-2316`  
- helper execution: `stream-app/privhelper/main.mm:199-350,1380-1385`

The script API checks `TLinkScriptStopRequested` before starting VPN profile creation, but after that check it synchronously calls `TLinkVPNRunPrivateConfigurationHelper`.

That function:
1. writes/fsyncs a protected request plist,
2. spawns `privhelper`,
3. calls blocking `waitpid(pid, &status, 0)`,
4. only reads/cleans the result after the child exits.

There is **no parent-side timeout and no cancellation check after spawn**.

Normal helper implementations have bounded loops in several known paths, but `waitpid(..., 0)` makes the parent contract unbounded if the helper or a private/system call fails to return. Script stop requested after helper spawn cannot make progress until the child exits.

This can strand:
- the script execution path,
- the helper process,
- the request/result temporary files,
- higher-level cancellation/state completion.

**Recommended direction**

Give the helper request an owned operation deadline and cancellation lifecycle:
- wait asynchronously or with `WNOHANG`/process-source state,
- use a monotonic deadline,
- observe script/session cancellation,
- terminate the child safely on timeout/cancel with bounded TERM -> KILL escalation,
- always reap the child,
- always clean request/result files in a finally-style cleanup path.

The helper result should distinguish timeout, cancellation and child failure.

**Benchmark/repro**

See `BENCHMARK-S010.md` Probe D.

---

### [P0-23] StreamControl service supervisor performs unbounded helper `waitpid` while holding its only lifecycle serial queue

**Status:** CONFIRMED live StreamControl app path  
**Locations:** `stream-app/app/StreamSupervisor.mm:53-62,99-170,301-427`  
**Lifecycle ingress:** `stream-app/app/AppDelegate.mm:135-146,189-214,236-272`

`SCStreamSupervisor` serializes service lifecycle work on one `_queue`.

Both:
- `runPrivhelperKillStreamdLocked`,
- `runPrivhelperEnsureStreamdLocked:`

spawn `privhelper` and then execute `waitpid(pid, &status, 0)` synchronously on that serial queue with no timeout.

If one helper stalls, later:
- ensure,
- restart,
- stop,
- foreground/background lifecycle recovery

cannot execute on the supervisor queue.

The code already demonstrates the safer pattern for the long-lived `streamd` child: its `waitpid` is moved to a concurrent queue and only completion is returned to `_queue`. The one-shot helper path does not use that pattern.

**Recommended direction**

Move helper waiting off the supervisor serial queue and add a bounded monotonic deadline. Serialize only state transitions/completion back onto `_queue`. On timeout, terminate/reap the helper and return an explicit failure so later lifecycle work can proceed.

**Benchmark/repro**

See `BENCHMARK-S010.md` Probe E.

---

## P1 — S010 High Priority

### [P1-65] TouchPOC intentionally keeps the entire app resident in background with an infinite zero-volume audio loop

**Status:** CONFIRMED POC compatibility design  
**Locations:** `poc-trollstore/AppDelegate.mm:36-73`, `poc-trollstore/Info.plist`

At launch the app:
- activates an `AVAudioSession` in playback mode,
- generates a silent WAV,
- creates an `AVAudioPlayer`,
- sets `numberOfLoops = -1`,
- sets volume to zero,
- starts playback.

`Info.plist` declares the `audio` background mode. The source comment explicitly identifies this as the mechanism used to keep the socket server responsive while backgrounded.

This makes the POC's otherwise avoidable socket/timer/filesystem work persistent instead of allowing normal app suspension.

This is intentionally a **POC artifact finding**, not a claim about the packaged StreamControl app.

**Recommended direction**

For any path promoted beyond diagnostics/POC use, replace silent-audio residency with the actual supported long-lived service boundary required by the feature. If the POC must retain this mechanism for experiments, gate it behind an explicit diagnostic mode and report its energy cost.

---

### [P1-66] TouchPOC tunnel performs 1 Hz filesystem polling, atomic state rewrite and file-backed logging even when no command changes

**Status:** CONFIRMED POC compatibility hot-idle path  
**Location:** `poc-trollstore/TunnelExtension/PacketTunnelProvider.mm:94-126,215-297`

The live tunnel schedules a repeating 1-second timer.

Every quiet tick:
1. `TPLog(@"heartbeat")` creates/ensures the log directory, chmods it, opens the log, seeks, writes, closes and also calls `NSLog`,
2. `pollFileCommand` stats/reads `command.txt`,
3. rebuilds a textual state snapshot,
4. atomically rewrites `poll_state.txt`,
5. when the command is absent/empty, `sPollTick % 1` is always zero, so it performs another full `TPLog` every tick.

Thus an unchanged/empty command channel is not idle.

**Recommended direction**

Use the already available app-message/socket/event mechanism for notification. Persist diagnostics only on state change or a coarse sampled cadence; initialize log directory/permissions once.

**Benchmark/repro**

See `BENCHMARK-S010.md` Probe B.

---

### [P1-67] TrollStore private VPN backend polls private-store state every 100 ms and can repeatedly rebuild the full configuration list

**Status:** CONFIRMED active-operation amplification  
**Locations:** `shared/TLinkVPNManager.mm:536-608,615-758,904-956`

The TrollStore-only private compatibility backend uses fixed 100 ms polling in several operations:

- profile cleanup waits up to 5 s for disconnect,
- profile creation verification performs up to **50 attempts**,
- connect/disconnect polls current connection state until a 5–30 s deadline.

Creation verification calls `TLinkVPNPrivateConfigurationRecords(store)` on each attempt, which rebuilds the visible configuration record list before checking for the newly created profile.

A 20 s private connection transition can therefore execute roughly 200 polling sleeps/status checks; a slow create can perform about 50 full configuration enumerations.

These paths are active-operation costs, not steady-state idle polling, so severity is below S008's event-channel idle loop.

**Recommended direction**

Prefer private/system state-change notification where available. Otherwise:
- use an explicit monotonic operation budget,
- apply bounded/adaptive backoff,
- cache stable configuration identity within the operation,
- avoid full list reconstruction on every 100 ms retry.

**Benchmark/repro**

See `BENCHMARK-S010.md` Probe F.

---

### [P1-68] TrollStore VPN brokers have opposite concurrency failures: foreground broker is single-client HOL, vpnagent has unbounded per-client global workers

**Status:** CONFIRMED  
**Locations:**  
- foreground broker: `stream-app/app/TLinkVPNForegroundBroker.mm:26-45,128-276`  
- background agent: `stream-app/vpnagent/main.mm:28-41,185-265`

The foreground app broker accepts one client and calls `TLinkVPNForegroundHandleClient` synchronously inside its accept loop. A client can hold the broker for:
- up to 30 s waiting for socket input/output,
- up to 8 s status wait,
- up to 24 s connect/disconnect wait.

No next client is processed until the current one completes.

The background `vpnagent` takes the opposite approach: every accepted client is dispatched to the global utility queue, and status/connect operations can block a utility worker in `dispatch_semaphore_wait` for 8/24 s. There is no source-visible active-client cap.

**Recommended direction**

Use one bounded asynchronous VPN state machine:
- small explicit client/admission limits,
- per-client nonblocking I/O,
- coalesce equivalent status requests,
- serialize only VPN mutations,
- do not occupy a global worker for an async NetworkExtension lifetime.

**Benchmark/repro**

See `BENCHMARK-S010.md` Probe G.

---

### [P1-69] AppDelegate keyboard observer cleanup removes a different notification name than the one registered

**Status:** CONFIRMED lifecycle mismatch; duplicate delivery risk requires runtime measurement  
**Locations:** `appdelegate/UIKeyboard.xm:47-79`, `appdelegate/appdelegate.plist`, root `Makefile:33`

Both hooked `UIKeyboardImpl` initializers register `self` for:

`com.tlinkauto.tlinkauto.keyboardcontrol`

and do so **before** calling `%orig`.

The hooked `dealloc` instead removes:

`com.tlinkauto.tlinkauto.textinput`

so the explicit cleanup is not symmetric with registration.

Because two initializer variants are hooked, runtime initializer forwarding can also create duplicate registrations for the same live object; that possibility needs device counting rather than source-only assertion.

The tweak is filtered into UIKit bundles and is included in the root aggregate build, so unnecessary observer work is broader than one app process.

**Recommended direction**

Register once after successful initialization, remove the exact registered notification name, and maintain a per-instance registration guard if both initializer routes can execute.

**Benchmark/repro**

See `BENCHMARK-S010.md` Probe H.

---

### [P1-70] TrollStore VPN query/control repeats the full static diagnostics preflight in both foreground and background brokers

**Status:** CONFIRMED S009 P1-62 amplifier on the TrollStore runtime  
**Locations:** `stream-app/app/TLinkVPNForegroundBroker.mm:47-63,66-166`, `stream-app/vpnagent/main.mm:43-59,62-181`, `shared/TLinkVPNDiagnostics.mm:68-202,333-386`

Before normal query/connect/disconnect, each broker calls its preflight helper, which builds a full `TLinkVPNDiagnosticsSnapshot`. That snapshot creates a SecTask and performs the static entitlement/framework compatibility probes documented in S009.

Diagnostics requests also run the preflight before manager status.

This extends P1-62 beyond Task 60: immutable process capability discovery is also on each TrollStore VPN broker operation.

**Recommended direction**

Cache immutable entitlement/framework/private-selector capability snapshots per process. Refresh only mutable profile/connection/ownership state.

---

## P2 — S010 Medium Findings

### [P2-24] AppDelegate globally hooks `_dyld_get_image_name` and adds string-length/suffix work to every call in injected processes

**Status:** CONFIRMED hook; impact requires measurement  
**Locations:** `appdelegate/Tweak.xm:1-28`, `appdelegate/appdelegate.plist`

The constructor replaces `_dyld_get_image_name` process-wide. Every invocation calls the original function, computes `strlen`, computes the tweak suffix length and compares the suffix so one dylib can masquerade as a private framework path.

The compatibility reason may be valid, but the hook sits beneath all callers of this dyld API in every process receiving the tweak.

Keep only if required and benchmark aggregate call count/CPU. Precompute constant suffix length and avoid unnecessary work if measurements show material traffic.

---

### [P2-25] TouchPOC root view runs a permanent 1 Hz foreground status refresh timer

**Status:** CONFIRMED POC-only diagnostic overhead  
**Location:** `poc-trollstore/ViewController.mm:238-264`

The root view controller schedules a repeating 1-second timer that rebuilds status strings and updates labels. It is invalidated only in `dealloc`; as the root controller it normally lasts for the app lifetime.

This is minor beside the POC's silent-audio and tunnel loops but is an avoidable main-thread wakeup. Update on actual state changes or only while the diagnostic screen needs refresh.

---

### [P2-26] TrollStore private VPN polling deadlines use wall-clock NSDate time

**Status:** CONFIRMED  
**Locations:** `shared/TLinkVPNManager.mm:564-576,942-953`

Private cleanup and connection polling budget their time with `NSDate timeIntervalSinceReferenceDate`. Wall-clock adjustments can shorten or extend an active operation timeout.

Use a monotonic/continuous clock for duration budgets; wall-clock timestamps can remain for diagnostics.

---

## S010 reviewed non-findings / scope boundaries

- `TouchPOC.tipa` is a separately built compatibility/diagnostic artifact, not the packaged StreamControl app. Its P0/P1 findings are labeled accordingly, but they are not dead source: CI explicitly builds and embeds `TouchPOCTunnel.appex`.
- The POC app-side TCP 6000 server in `POCSocketServer.mm` uses CFStream run-loop readiness rather than the tunnel extension's 5 ms polling loop; the high-frequency idle spin is specific to `ProviderTCPServer.mm`.
- `TLinkVPNPrivateRequest` already bounds request data to 16 KiB and result data to 64 KiB and validates file ownership/mode/link count. S010's critical issue is unbounded child lifetime/cancellation, not missing payload bounds.
- The long-lived `streamd` child is waited on a concurrent queue before completion returns to the supervisor serial queue. The P0-23 problem is specifically the one-shot `privhelper` waits performed synchronously on that queue.
- `vpnagent`'s one-hour no-op CFRunLoop keepalive timer is negligible compared with its request workers; the server's blocking `accept` itself does not create periodic idle CPU.
- `SCBackgroundServiceScheduler` uses BGTaskScheduler with 15/30-minute earliest begin dates rather than a tight resident poll loop. Its diagnostics plist rewrites are low-frequency lifecycle work and are not promoted to a new hot-path finding.
- The public NEVPNManager path remains notification-driven; P1-67 concerns only `TLINK_VPN_TROLLSTORE_RUNTIME` private compatibility state polling.
- Per-touch logging in the standalone TouchPOC diagnostic socket path is intentionally verbose and should not be copied into production, but it is not numbered separately from the already known hot-input logging class.

## S010 prioritization by expected gain × frequency × cost

1. **P0-21** replace tunnel 5 ms idle socket polling with event-driven bounded client I/O.
2. **P0-22** add helper deadline/cancellation/reap semantics to `vpnconf.create`.
3. **P0-23** remove unbounded helper waits from the supervisor serial queue.
4. **P1-66/P1-65** eliminate POC idle disk heartbeat and silent-audio residency if the artifact is used beyond diagnostics.
5. **P1-67** replace/coarsen private VPN 100 ms polling and repeated list enumeration.
6. **P1-68/P1-70** bounded asynchronous TrollStore VPN broker + cached static preflight.
7. **P1-69** repair keyboard observer registration lifecycle.
8. **P2-24..26** measure/remove global compatibility hook, diagnostic timer and wall-clock timeout usage.

---

# S011 Addendum — License Lifecycle / Control Plane

## P0 — Additional Critical Findings

### [P0-24] Rootfull license cache misses synchronously perform a signed authority round-trip while holding the process-wide verifier cache queue

**Status:** CONFIRMED live rootfull architecture  
**Locations:**  
- `shared/TLinkLicenseVerifier.mm:76-90,122-169,1327-1410`  
- `shared/TLinkLicenseAuthorityClient.mm:53-112,114-248`  
- `license-authority/main.mm:19-88,90-180`  
- heartbeat callers: `pccontrol/ScriptPlayer.xm:159-226`, `pccontrol/H264Stream.xm:675-692`  
- build reachability: `pccontrol/Makefile:11-13`, `tlinkauto-binary/Makefile:13-18`, `tlinkauto-jsd/Makefile:8-11`, `vpn-broker/Makefile:8-12`

Every rootfull `TLinkLicenseFeatureAllowed` call enters one process-wide serial `TLinkLicenseCacheQueue` with `dispatch_sync`.

When the 5-second status cache expires, the cache miss is resolved **inside that queue** by `TLinkLicenseStatusDictionary`. In the rootfull binaries this is compiled with `TLINK_LICENSE_AUTHORITY_CLIENT=1`, so the refresh synchronously performs:

1. fresh random nonce generation + JSON request,
2. fresh Unix-domain socket connect/send/receive,
3. client-side lease/public-key anchoring,
4. authority-side full local signed-lease verification,
5. authority response signing,
6. client response signature verification.

The authority client socket has 3-second send/receive timeouts.

The long-running revocation checks line up directly with this TTL:
- ScriptPlayer checks every **1 second**, so approximately every fifth heartbeat can become a full authority refresh when no other caller refreshed the snapshot.
- H264 checks every **5 seconds**, the same as the cache TTL, so a session can turn nearly every license heartbeat into a synchronous authority round-trip.

While one refresh is slow, every same-process feature check queues behind the same serial cache queue. A delayed authority therefore injects multi-second latency into protected runtime work rather than into a detached control-plane refresh.

This is distinct from the earlier per-command enforcement finding: S011 establishes the expensive cross-process authority/crypto work performed at cache refresh boundaries and its exact alignment with long-running heartbeats.

**Recommended direction**

Make verified status refresh asynchronous/single-flight:
- runtime checks read an immutable in-memory snapshot,
- one refresh worker updates it when generation/TTL policy requires,
- define an explicit fail-closed stale-snapshot window for authority outage,
- never hold the feature-check queue across socket I/O, Keychain signing or full crypto verification,
- schedule heartbeat refresh ahead of expiry rather than making the heartbeat itself pay refresh latency.

**Benchmark/repro**

See `BENCHMARK-S011.md` Probe A.

---

## P1 — S011 High Priority

### [P1-71] Busy rootfull processes poll the license generation file every 250 ms even though a Darwin notification already invalidates the cache

**Status:** CONFIRMED call-driven persistence polling  
**Locations:** `shared/TLinkLicenseVerifier.mm:39-50,76-90,122-169,1327-1353,1384-1399`

The verifier registers `com.tlinkauto.license.changed` with `notify_register_dispatch` and invalidates its process cache when the notification arrives.

Despite that event channel, feature checks also run a safety generation poll every 250 ms:
- read the generation file through Foundation,
- parse the text,
- update the checked timestamp.

This is not an idle timer; it is **call-driven polling**. Under a busy workload it can produce up to about four generation-file reads per second **per process**, even while the generation never changes.

Examples:
- ScriptPlayer's 1 Hz heartbeat performs one generation read on essentially every tick.
- High-rate task enforcement can reach the 250 ms ceiling.
- The same verifier is compiled into pccontrol, tlinkautod, tlinkauto-jsd and vpn-broker.

**Recommended direction**

Use Darwin notification as the primary invalidation mechanism and retain only a coarse recovery/reconciliation check for process startup or missed-notification defense. Keep generation monotonicity as the correctness contract without polling the file on a 250 ms cadence.

**Benchmark/repro**

See `BENCHMARK-S011.md` Probe B.

---

### [P1-72] License authority has no explicit client-admission bound and maps each slow client to a global utility worker

**Status:** CONFIRMED  
**Locations:** `license-authority/main.mm:90-180`

The authority accept loop dispatches every accepted client to the global utility queue. There is no source-visible active-client semaphore/cap.

Each worker can remain occupied for up to the 5-second socket receive/send timeout before or after the status computation. Status computation itself performs security/file work and uses the shared trust-checkpoint flock.

A burst of rootfull cache misses or clients that connect but delay request data can therefore grow the number of blocked global workers while valid requests contend for the same process resources.

**Recommended direction**

Use bounded admission and event-driven client I/O. Coalesce identical status computation by license generation, and serialize only the trust state mutation that actually needs exclusivity.

**Benchmark/repro**

See `BENCHMARK-S011.md` Probe C.

---

### [P1-73] One signed authority status refresh redundantly re-validates the lease and performs multiple private-key/signature operations across client and server

**Status:** CONFIRMED crypto/I/O amplification  
**Locations:**  
- client anchoring: `shared/TLinkLicenseAuthorityClient.mm:114-248` and `shared/TLinkLicenseVerifier.mm:464-552`  
- authority local verification: `shared/TLinkLicenseVerifier.mm:1133-1323`  
- device proof: `shared/TLinkLicenseVerifier.mm:571-668`  
- authority response sign: `license-authority/main.mm:45-87`

For one rootfull authority status refresh:

**Client side before trusting the authority proof**
- reads the device public key,
- reads/parses the signed lease again,
- verifies the server lease ECDSA signature,
- hashes and compares the device public key.

**Authority side**
- independently reads/parses and verifies the lease,
- performs a Keychain private-key lookup,
- signs a local possession challenge,
- verifies that challenge,
- reads/verifies the signed anti-rollback checkpoint,
- periodically signs/rewrites the checkpoint.

Then the authority signs the whole status response with the device private key, and the client verifies that response signature.

Much of this is generation-stable but is repeated every short status refresh.

**Recommended direction**

Cache immutable verified artifacts by generation:
- verified lease payload,
- server-key verification result,
- device-public-key anchor,
- release-integrity metadata.

Keep freshness-sensitive time/rollback decisions separate. The signed authority response can attest to the cached verified generation without redoing every immutable proof on every heartbeat boundary.

**Benchmark/repro**

See `BENCHMARK-S011.md` Probe D/E.

---

### [P1-74] Successful lease save validates the full license repeatedly and resets/recreates the signed anti-rollback checkpoint

**Status:** CONFIRMED refresh/activation amplification  
**Locations:** `stream-app/app/LicenseManager.mm:321-408,500-565`, `shared/TLinkLicenseVerifier.mm:857-1010`

`saveLease:` performs a transactional safety sequence, but the implementation is expensive:

1. reads the previous lease,
2. calls full `TLinkLicenseStatusDictionary` for the previous state,
3. reads the previous trust checkpoint,
4. atomically writes the candidate lease,
5. removes the current trust checkpoint under exclusive lock,
6. invalidates verifier cache,
7. calls full `TLinkLicenseStatusDictionary` again to validate the candidate and recreate/advance the checkpoint,
8. advances generation.

The caller then commonly asks for status again:
- activation calls `localStatus`,
- lifecycle refresh completion calls `localStatus` again.

Thus one successful server refresh can perform several complete crypto/disk validation passes around one lease change.

**Recommended direction**

Validate the candidate lease once in memory against the previous anti-rollback floor, then atomically commit the lease + checkpoint state and publish one generation change. Preserve rollback recovery without reset-then-recreate and repeated full status queries.

**Benchmark/repro**

See `BENCHMARK-S011.md` Probe F.

---

### [P1-75] License lifecycle single-flight begins after expensive local status evaluation, so launch/foreground triggers can duplicate full verification work before coalescing

**Status:** CONFIRMED lifecycle ordering issue  
**Locations:** `stream-app/app/LicenseLifecycleCoordinator.mm:182-234,279-332,368-499,501-526`

The coordinator has useful single-flight state in `beginOperation:`, but `refreshForTrigger:` first executes:

`NSDictionary *status = [self.manager localStatus];`

Only after full local verification, refresh-window decision and backoff checks does it call `beginOperation:@"refresh"`.

At app lifecycle boundaries:
- `handleApplicationLaunch` starts one full UI snapshot refresh **and** asynchronously calls `refreshForTrigger`,
- `handleApplicationDidBecomeActive` repeats the same pair.

A normal cold launch is followed by becoming active, so several full status evaluations can overlap/queue before the network refresh single-flight gate has any effect.

UI snapshot refreshes are coalesced on their own queue, but the automatic-refresh decision path is not coalesced before `localStatus`.

**Recommended direction**

Acquire/coalesce a lifecycle refresh-decision token before expensive status evaluation. Reuse a generation-keyed verified snapshot between UI and refresh policy decisions.

**Benchmark/repro**

See `BENCHMARK-S011.md` Probe G.

---

### [P1-76] BGTask expiration and the 22-second watchdog mark the task complete but do not cancel license HTTP or suppress late stream-service recovery

**Status:** CONFIRMED abandoned-work path  
**Locations:** `stream-app/app/BackgroundServiceScheduler.mm:145-204`, `stream-app/app/LicenseManager.mm:280-319,515-567`

The background scheduler has:
- an iOS expiration handler,
- a 22-second local watchdog,
- a one-shot `finish` guard around `setTaskCompletedWithSuccess:`.

However, `finish` only marks the BGTask complete. It does **not**:
- cancel the current `NSURLSessionDataTask`,
- invalidate the lifecycle refresh operation,
- suppress a late refresh callback,
- prevent that callback from calling `supervisor ensureServiceWithCompletion:`.

License HTTP requests have their own 20-second timeout and the data task handle is not exposed to the coordinator. If iOS expires the task early, or the 22-second watchdog wins, the underlying request can still complete later and launch stream-service recovery after the BGTask has already been closed.

The outer 22-second budget also barely exceeds the 20-second HTTP timeout and leaves no reliable budget for service ensure; S010 already established that supervisor helper waits can themselves be long/unbounded.

**Recommended direction**

Thread a cancellation/operation-generation token through BGTask -> license request -> completion -> supervisor ensure. Cancel the URLSession task on expiry and ignore stale completions. Split or reorder budgets so the outer deadline strictly contains all intended inner work.

**Benchmark/repro**

See `BENCHMARK-S011.md` Probe H.

---

### [P1-77] License lifecycle diagnostics repeatedly read and atomically rewrite the whole plist during one logical refresh

**Status:** CONFIRMED persistence amplification  
**Locations:** `stream-app/app/LicenseLifecycleCoordinator.mm:128-145,216-268,279-365,402-499`

`updateDiagnostics:` executes under `@synchronized(self)` and on every update:
- ensures the directory,
- reads the whole diagnostics plist,
- merges values,
- atomically rewrites the whole plist.

`appendRefreshHistoryEvent:` calls `diagnostics` first, which reads the plist, then calls `updateDiagnostics`, which reads it again before writing.

A successful refresh can generate writes for:
- operation begin,
- attempt/decision state,
- success state,
- refresh history,
- license change,
- UI snapshot metrics,
- daemon invalidation result,
- operation finish,
- and possibly daemon invalidation retry.

This is event-driven rather than continuous idle churn, but one control-plane state change is amplified into many filesystem transactions.

**Recommended direction**

Keep diagnostics state in memory on one queue and flush a coalesced snapshot once per logical operation or coarse interval. Append history in memory without rereading the persisted plist.

**Benchmark/repro**

See `BENCHMARK-S011.md` Probe I.

---

### [P1-78] Rootfull tasks 75/76/97 bypass the feature cache and force a fresh signed authority status proof on every diagnostic request

**Status:** CONFIRMED request-path cost  
**Location:** `tlinkauto-binary/SocketServer.mm:825-891`

Rootfull diagnostic/status paths call `TLinkLicenseStatusDictionary()` directly instead of reading the verifier's cached snapshot.

With `TLINK_LICENSE_AUTHORITY_CLIENT=1`, every Task 75/76/97 request therefore performs a fresh authority exchange and proof verification regardless of the 5-second feature cache.

Task 97 additionally reads generation separately for its response.

These tasks are exempt from normal task enforcement, so a health/status probe can be more expensive than an ordinary cached protected-task check.

The source does not establish a universal rootfull polling cadence, so this is P1 rather than P0. It becomes especially relevant for supervisors/health monitors that probe capability repeatedly.

**Recommended direction**

Expose a snapshot/status API with explicit freshness semantics. Let diagnostics reuse the most recent verified generation unless the request explicitly asks for a forced proof/reload.

**Benchmark/repro**

See `BENCHMARK-S011.md` Probe J.

---

## P2 — S011 Medium Findings

### [P2-27] Process-stable license configuration and release-integrity metadata are repeatedly reloaded from disk during full status evaluation

**Status:** CONFIRMED supporting overhead  
**Locations:** `shared/TLinkLicenseVerifier.mm:172-344,669-739,1133-1323`

Full status evaluation repeatedly reconstructs configuration and rootfull release-integrity state from filesystem-backed plist metadata. The authority-client anchoring path also reloads configuration/lease metadata before response verification.

These values are effectively stable for the lifetime of a process/build except for the lease/generation itself.

**Recommended direction**

Cache immutable build/config metadata once per process, keyed by an explicit configuration generation only if runtime replacement must be supported.

---

### [P2-28] Lifecycle refresh/backoff deadlines are wall-clock based

**Status:** CONFIRMED  
**Locations:** `stream-app/app/LicenseLifecycleCoordinator.mm:123-126,368-419`

Refresh-window and retry eligibility compare persisted epoch timestamps using `NSDate`. Wall-clock jumps can make backoff appear prematurely expired or unexpectedly extended.

Wall time is appropriate for license expiry semantics, but elapsed retry delays should use a monotonic clock while the process is alive; persisted wall timestamps can remain as restart diagnostics/fallback.

---

## S011 reviewed non-findings / scope boundaries

- The automatic refresh policy has exponential backoff with jitter: base 60 seconds, capped at 6 hours. No source-visible tight network retry storm was found.
- The authority launch daemon is resident by design but its idle server blocks in `accept`; there is no periodic idle polling timer in `tlinkauto-licensed`.
- Authority requests are size-bounded to 4 KiB. The client has a 1 MiB response ceiling; current server-produced status is structurally bounded enough that response-size growth was not promoted independently.
- Trust-checkpoint writes are already rate-limited by state: under stable boot/lease they occur at most when about 60 seconds of wall time has advanced. S011's concern is repeated read/verify/lock work, not an unconditional checkpoint write per status.
- The UI snapshot queue already coalesces concurrent snapshot refresh requests. P1-75 concerns the separate automatic-refresh decision path, which performs `localStatus` before entering its single-flight gate.
- The lifecycle coordinator's automatic network refresh respects persisted backoff. Repeated foreground events can still redo local verification/diagnostics, but they do not bypass the network backoff unless the user explicitly forces a manual refresh.
- No recurring license heartbeat was found in `tlinkauto-jsd`; the confirmed recurring component checks reviewed in S011 are ScriptPlayer's 1 Hz timer and H264's 5-second active-session check.
- `TLinkRootfullLicensePolicy.mm` itself contains no additional recurring timer/control loop beyond calling the shared verifier; its task-policy table was not rescanned as a new finding.

## S011 prioritization by expected gain × frequency × cost

1. **P0-24** remove authority socket/crypto refresh from synchronous feature-check critical path.
2. **P1-71/P1-73** stop generation-file polling and cache generation-stable authority proof material.
3. **P1-72** bound authority clients and coalesce status computation.
4. **P1-76** propagate BGTask cancellation and repair timeout hierarchy.
5. **P1-74/P1-75** collapse repeated lease/status verification around refresh and lifecycle transitions.
6. **P1-78** cache diagnostic status/proof with explicit freshness.
7. **P1-77** batch lifecycle diagnostics persistence.
8. **P2-27/P2-28** cache static metadata and separate monotonic retry duration from wall-clock expiry semantics.



