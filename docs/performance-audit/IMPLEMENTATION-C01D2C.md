# C01d2c — isolated synchronous C01 IPC channel

Date: 2026-10-23 (Asia/Bangkok). Baseline: `c0ed279`; the user reported the C01d2b build passed before this slice.
Status: **source implemented; new macOS/iOS CI and device qualification pending**.

## Problem and scope

C01d2b separated the daemon's image executor, but its requests still joined the ordinary sender queue and SpringBoard's ordinary CFMessagePort callback. A blocked ordinary receiver could still delay image IPC, and a slow image callback could still occupy the ordinary IPC receiver.

C01d2c gives deadline-bearing root C01 requests a dedicated serial sender queue and a dedicated SpringBoard CF port/run-loop thread. Existing CF send/receive calls remain synchronous inside their owning worker. There are no detached request jobs, copied stack response targets or per-request worker threads. The ordinary IPC endpoint, no-reply touch path and production TrollStore implementation retain their behavior. TouchPOC is excluded.

## Routing and private contract

The private endpoint is `com.tlinkauto.tlinkautod.springboard.c01.v1`. Both root IPC constant headers declare the same name, and the runner verifies equality.

Sender queue selection and remote-port selection use one shared predicate: reply-bearing requests with an inherited nonzero native deadline and a C01/helper payload. All daemon IPC call sites select their owner through that predicate. Each endpoint has a separate cached CFMessagePort reference; the cache slot is touched only on its matching serial sender owner. Invalid cached references are released and rediscovered on the same endpoint. The ordinary ping-success timestamp remains confined to its ordinary owner.

Private calls send the existing message-ID-3 `TC01` deadline envelope directly. They do not consult the ordinary ready marker or send an ordinary-port health ping. Remote discovery and the bounded request itself determine availability, so a busy or missing ordinary callback/marker does not gate the private channel. Existing remaining-budget send/receive limits and post-call expiry checks remain in force.

The private receiver requires:

- CF message ID 3;
- a valid bounded TC01 envelope, UTF-8/task framing, no embedded NUL, a live same-boot deadline no more than eight seconds in the future;
- a C01 image family (21/23/27.1/27.6/28/49/68/69/70/91), exact orientation helper 35, or owned screenshot helper 29 action 4.

Ordinary screenshot actions 1/2/3, album mutations, touch/no-reply traffic, arbitrary helper suffixes and legacy envelopes are rejected before dispatch on this port. Owned capture still validates its UUID path and marker in the common receiver. The private wrapper then enters the same task/license/parser/budget/response code as ordinary IPC. This is transport isolation, not a feature-authorization bypass.

Absent/private-send failure returns `1;;c01_ipc_unavailable`; a known elapsed request returns `c01_request_expired`. Invalid/unsupported envelope, task or reentrant work receives an explicit private error. **No fallback or replay occurs on the ordinary endpoint.** The ordinary port continues to accept legacy IDs 1/2 and the previous ID-3 envelope for older senders. An old receiver without the private port cannot serve a new daemon's C01 request: deploy the daemon and tweak coherently. Startup failure of the private source is fail-closed; there is no periodic startup retry.

## Receiver and response ownership

The private run-loop thread starts once through `dispatch_once` when the existing background IPC bootstrap runs. It owns one CF port/source for its lifetime and blocks on CF run-loop events while idle. A source-install failure invalidates/releases its port. If the run loop exits, its source is removed/released and the port invalidated/released. One additional process-lifetime receiver thread and a lazily created sender queue add resource overhead; no idle polling or periodic timer is introduced.

A scope-owned atomic admission guard permits only one executing private handler, including accidental reentry from a framework's nested run loop. The guard stays held through the actual callback and releases during stack unwinding. Objective-C and C++ handler exceptions become `request_failed` inside the CF callback boundary; they do not escape into CoreFoundation or discard the admission guard. Each private callback also has an autorelease pool.

The sender's `CFDataRef` response variable is still used only by the synchronous send on its owner queue, then returned to/released by its caller. There is no asynchronous completion writing into a returned stack frame. SpringBoard retains its native response budget, placeholder stream, capture receiver and admission scope until its callback finishes; its returned CFData follows the CFMessagePort callback ownership contract. Existing 1 MiB response accumulation and expired-final-response checks remain active. C01d2a's marker protocol continues to prevent/discard late screenshot publication after daemon cleanup.

## Ordering, admission and timeout limits

Daemon admission remains 2 image / 14 ordinary / 16 combined per process, including queued/running/completion-pending daemon jobs. Per-client daemon admission and reply FIFO remain across lane/endpoint changes; successful dependent commands on one client retain their sequence. Different clients across lanes can overlap, as explicitly introduced by C01d2b.

A transport timeout or disconnect does **not** acknowledge physical completion of an opaque remote callback. The daemon's worker can finish when CF send returns while SpringBoard is still in capture/encoding/recognition. Its daemon admission charge then follows the existing worker-completion rule; the receiver's independent one-handler charge remains held until the real callback exits. These are process-local limits, not a shared distributed 16-request accounting system, and no numerical application cap is claimed for CoreFoundation/Mach's internal transit queue.

After a timeout, even the same client's next ordinary request can now execute on the other endpoint while an older private read/query callback is still unwinding. Its expired result is not a success acknowledgment. Cross-connection dependencies still require an acknowledgment or one ordered connection; callers must not treat a failed/timed-out query as proof that every remote resource is already released. The strict private allowlist excludes ordinary mutation helpers, and an owned screenshot's marker controls late publication. Neither lane releases another callback's native resources on its behalf.

This channel serializes its own private callbacks. Legacy/direct/native callers can still reach existing engine owners and admissions; their memory/context concurrency limits are unchanged, and no additional OCR worker pool is created. Shared UIKit main-thread work, image stores, license services, engine queues, model initialization, CV/Vision internals and filesystems can still cause dependency waits or opaque overrun. No hard response SLA or measured CPU/energy/RSS improvement is claimed.

C01 remains open. Next: crash-retention cleanup/qualification for private screenshot leases, then remaining engine/device benchmark acceptance. No forced callback termination or process-crash scavenger is added in this slice.

## Validation

- Windows: 36 source-contract runners, 20 native runners and 528 TrollStore workflow source assertions pass. Portable C01 tests cover private channel selection, allowed versus mutating/helper payloads, admission rejection/reentry/exception cleanup, existing 2/14 limits, parent cancellation/deadlines and malformed envelopes. Existing 100k screenshot ownership/fault lifecycles also pass.
- Expanded sender fixture checks the actual selected private port, bypass of ordinary marker/ping, independent cache failure, deadline preservation and no fallback with controlled CF calls.
- New macOS fixture extracts the actual sender owner queues, sender, common callback, private callback and source installer. Two real CFMessagePorts on joined run-loop threads check progress in both directions under a blocked peer, sender timeout while a callback is held, busy/reentry protection, late callback recovery, malformed/expired/mutating traffic rejection, Objective-C/C++ exception recovery, source-creation failure cleanup and ordinary behavior after private-port shutdown. It uses real CF transport with controlled task handlers.
- Both workflows run that fixture via `check-c01-ingress-safety.mjs`; the TrollStore workflow includes its new test path. Existing owned-capture tests now compile the actual queue selector. Strict warnings, ASan and UBSan remain enabled.
- **The new macOS CF fixture and final iOS builds were not run on this Windows host.** Actual Mach service registration/lookup under both root runtimes, UI/engine thread behavior, cold launch/restart, accuracy, resource use and device latency require qualification.

Device acceptance: deploy matching daemon/tweak versions; test both binaries/root runtimes, private-port absence/startup, legacy compatibility and separate-port recovery. Block ordinary callback work and run C01 queries, then reverse the direction; distinguish receiver isolation from shared main-thread/engine contention. Timeout/cancel during capture/encoding/recognition and verify late-result rejection, held-reader/lease cleanup and subsequent recovery. Check one private callback at a time, no idle polling, unchanged same-client successful request ordering, no-reply touch and licensing behavior. Record latency, queue residence, RSS/thread overhead and energy against C01d2b.

## C01d3 checkpoint — 2026-10-23

The user reported the C01d2c build at `9396ef2` passed before C01d3. Device qualification remains pending. `IMPLEMENTATION-C01D3.md` adds shared descriptor ownership, output identity proof and bounded recovery of proven abandoned screenshots; it preserves unproven/legacy evidence and does not add a hard deletion deadline.
