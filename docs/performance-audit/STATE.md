# Audit State

Status: **SOURCE AUDIT FIRST PASS COMPLETE — runtime benchmark validation pending**
Checkpoint: **S011**
Last completed scope: license verifier generation/cache control plane + signed rootfull authority + StreamControl license refresh/background lifecycle.
All intentionally in-scope rows in `COVERAGE.md` are now first-pass DONE; vendor/decompiled/reference trees remain explicitly excluded unless a measured live path requires them.

## Implementation checkpoint — 2026-10-17

- User scope: exclude prototype TouchPOC / `poc-trollstore` findings P0-21, P1-65, P1-66, P2-25 from implementation. Do not optimize that artifact.
- Production `stream-app/streamd` remains in scope even where its files/functions retain POC names.
- A01 / P0-04 + P1-06: source changes implemented in rootfull/roothide and production TrollStore touch injection, including bounded ingress callers.
- A01 native regression harness passes for both production injection implementations with a retain-counted HID test double and guarded input pages, including 100k-frame runs. User reported the build passed before A02; device qualification is still pending.
- Details and remaining device validation: `IMPLEMENTATION-A01.md`.
- A02 / P1-07 + P1-09 + P1-10: source implemented for the rootfull/roothide global touch indicator. Main-loop ownership, zero-based 0..19 slots, synchronous error delivery, balanced HID teardown and generation-filtered callbacks.
- A02 native ownership/slot/generation harness passes, including 10k client lifecycles, and all 29 existing source-contract checks pass. User reported the build passed before A03; actual UIKit/main-run-loop behavior is not yet device-validated. Details: `IMPLEMENTATION-A02.md`.
- P1-08 is only partially improved (no per-move GCD backlog; cached font). Display-cadence coalescing remains separate performance work.
- A03 / P1-19: rootfull/roothide capture source implemented. Guard failed surface/lock/image/context creation; balance owned references without releasing borrowed color space; calculate rotation stride from destination width and validate geometry/size arithmetic.
- A03 native harness passes 22 success/fault paths and 20k frames with zero live test resources; A01/A02 native suites and all 29 existing source-contract checks also pass. User reported the A03 build passed before A04; device checks remain pending. Details: `IMPLEMENTATION-A03.md`.
- A04 / P0-15 + P0-16 + P1-52: source implemented. Rootfull/roothide timers use a serial background owner, non-reused generation tokens, committed set/remove acknowledgments, a 1-second repeat floor, leeway and cheap busy rejection before license/config work. All three production auto-launch writers share a file-lock transaction helper.
- A04 portable registry/policy tests pass (8 clients x 10k cycles); A01-A03 native regressions and all 36 source-contract checks across both workflows pass. User reported the A04 build passed before A05. macOS test logs were not independently inspected; device qualification remains pending. Details: `IMPLEMENTATION-A04.md`.
- A05 / P0-03 + P1-02: source implemented for rootfull/roothide. RAW/JS share session admission and completion ownership; stopping stays busy through task/file/touch/history cleanup. Repeat waits use cancellable dispatch sources, with no NSTimer or nested run loop. RAW delays are interruptible and speed-adjusted without per-delay NSString construction.
- A05 portable tests pass 100k RAW records, 8 x 10k lifecycle cycles, stale-generation and blocked-task/cleanup checks, plus successful-touch tracking/release. All 36 source-contract checks and A01-A04 native suites pass. A macOS dispatch/ARC player harness is added to CI but not run on this Windows host. User reported the A05 build passed before A06 (`4cc10e5`); device checks remain pending. Details: `IMPLEMENTATION-A05.md`.
- P1-03 receives a source-level mitigation (bounded per-record pools and no speed-adjust NSString), without a measured RAM claim.
- A06 / P0-14 + P1-45 + P1-46: source implemented for rootfull/roothide. Bridge preserves context/length, rejects oversized/NUL input before dispatch, uses an on-demand bounded raw-response sink, and propagates a monotonic cooperative budget into gesture/image/OCR/AX work. Cleanup UP/releases remain allowed after cancellation; a successful frame/image creation is rolled back when its call expires before return. RAW reuses a session cancellation-only budget.
- A06 portable tests pass bounded 1 MiB output, 200 cancellation races, deadline/cleanup, cross-TU/worker scope and both production SAD loops. All 36 existing source-contract checks and A01-A05 native regressions pass. macOS actual bridge/context/sink/gesture integration is added to both production workflows but not run on Windows. User reported the corrected A06 build passed before B01 (`93d2b8b`); device checks remain pending. Details, published limits and opaque vendor/IPC/queue latency exceptions: `IMPLEMENTATION-A06.md`.
- The response sink bounds wire accumulation; it does not bound every producer's transient object or process RSS. Cancellation is cooperative; no hard native-call completion deadline is claimed.
- B01 / P0-01 + P1-01 + P2-04: pccontrol recorder source implemented. One dedicated CF owner, generation-bound HID/stop/UI lifecycle, fixed 4096-record ring, writer batching/active-only flush, monotonic callback-arrival timing, fail-stop on overflow/I/O error and drain/fsync/close before idle. Same-second packages are exclusive. Existing daemon 14/15 ACK remains queued, distinct from direct completion-aware task replies.
- B01 portable harness passes 100k RAW round-trip records (385 batched fixture writes), 1000 coordinate comparisons, timing/overflow/write faults and 8 x 1k lifecycle cycles. All 36 existing source contracts and A01-A06 native regressions pass. Actual macOS owner/run-loop/HID/file harness is added to rootfull/roothide CI but not run on Windows; new build/device checks pending. Details and durability/stop-latency limits: `IMPLEMENTATION-B01.md`.
- User reported the corrected B01 build at `07c1b84` passed before B02. Device qualification remains pending.
- B02 / P0-07 + P0-09 + P1-20 + P1-21 + P1-24 + P1-26: pccontrol frame/image source implemented. Noncopyable shared immutable payloads, compute outside store queue, active-reader/pending-inclusive 96/64/128 MiB frame/image/combined limits, bounded disk preflight, two compute admissions, monotonic ages and active one-shot frame expiry. Explicit image lifetime and legacy response fields preserved; new admission/format limits documented.
- B02 portable extracted-core tests pass 20k lifecycles and 8 x 10k concurrent reservations, all 36 existing source contracts and seven previous native suites pass. macOS actual adapter/release/ImageIO wrapper tests added to root CI; final build/device checks pending. Details: `IMPLEMENTATION-B02.md`.
- User reported the corrected B02 build passed at `e304763` before B03; its device checks remain pending.
- B03 / P0-05 + P1-14 (daemon portion) + P1-16 + P1-17 (IPC portion): root no-reply touch fast path, 1 MiB IPC sink, no response payload logs, separate serial ordinary-work queue, per-client FIFO, explicit daemon transport ping and bounded nonblocking output (2 MiB/client, 16 MiB/global, progress/residence deadlines). Limits and remaining C04/B05/B06 behavior: `IMPLEMENTATION-B03.md`. User reported the corrected B03 build passed at `a54251b` before B04; device qualification remains pending.
- B04 / P1-12 + P0-06 + P1-13 + P1-18 (+ P2-06): both production H264 streams now use nonblocking 2s no-progress/5s access-unit sends, 64-packet TS batches, numeric adaptive snapshots outside the frame loop, generation-guarded persistence, bounded coalesced recovery telemetry and monotonic absolute pacing. User reported the corrected build passed at `303b5be` before B05a; device qualification remains pending. Details and limits: `IMPLEMENTATION-B04.md`.
- All 36 existing source contracts and 10 native regression runners pass on Windows. B04 portable tests pass 3,000 byte-identical TS cases against the old generator, raw framing, deadlines and 10k pacing turns. Both workflows include real macOS socket/adaptive integration; this branch was not run on Windows.
- B05a: shared verifier uses a short memory snapshot lock, single-flight background verification, independent active-only generation polling, epoch/generation-safe publication, per-call signed expiry checks, bounded cold waits and nonblocking root denial diagnostics. Root authority admits at most eight clients before dispatch. All 36 existing source contracts and 11 native runners pass on Windows; new Foundation integration is added to both workflows, pending macOS/iOS build/device checks. Details: `IMPLEMENTATION-B05.md`.
- User reported the corrected B05a build passed at `992a43a` before B05b; device qualification remains pending.
- B05b / P1-73 + P2-27 + P0-02 + P1-78: exact-content configuration parsing and successful server-signature artifact caches, generation/epoch/key/build guards, owner/cancellation-bound RAW numeric automation checks for task 10/18, and opt-in cached license diagnostics for task 60/75/97. Default/fresh diagnostics, task 76 mutation, nonce proofs, device possession, expiry and signed checkpoint checks retain their contracts. New real Security/diagnostic/playback macOS tests are added; B05b artifact/device verification is pending. Details: `IMPLEMENTATION-B05.md`.
- User reported the B05b build passed at `b3383d9` before B06; device qualification remains pending.
- B06 / P0-17 + P0-18 + P1-55 + P1-57 + P2-19 + P2-20 + P2-21: shared asynchronous notify-backed waits, active-only metadata reconciliation, shared/nonblocking reader flock, cancellation-bound TCP/JSON/remote adapters, separate bounded authorization providers, monotonic deadlines and filtered-tail pagination. 36 source runners, 12 native runners and 528 workflow grep assertions pass on Windows; new actual Foundation/notify/socket integration and final iOS build/device checks are pending. Details: `IMPLEMENTATION-B06.md`.
- User reported B06 build pass before C01a; device qualification remains pending.
- C01a / P0-10 + P0-11 + P1-27: two-entry full-identity Tesseract LRU, actual nil-image/native-results cleanup in the live G8 wrapper, pressure purge, pre-copy/post-scale 4M-pixel admission, scale-1 copy avoidance and a root three-second cooperative request budget with two admitted jobs. Production TrollStore also checks pixel geometry before capture and after crop. 36 source runners and 13 native runners pass on Windows; new Foundation/provider/G8-cleanup fixture and new iOS builds/device accuracy/RSS checks are pending. Engine entries and source-visible gray estimates do not bound opaque model/process RSS. Details: `IMPLEMENTATION-C01.md`.
- User reported the C01a build at `1b4b382` passed before C01b; device qualification remains pending.
- C01b / legacy TemplateMatch portion of P1-25 + P1-36 + P1-37 + P1-38 + P2-08: immutable byte-charged LRU snapshots, file identity/metadata preflight, full pyramid/tries admission, two compute slots, eight-second cooperative preparation/search budget and 256M comparison cap. Root daemon and SpringBoard validate parameters before screenshot capture. Production TrollStore task 21 uses a different matcher and is unchanged.
- C01b validation: 36 source runners, 14 native runners and 528 TrollStore workflow grep assertions pass on Windows. The new real Foundation/ImageIO orchestration fixture uses controlled OpenCV operations and awaits macOS CI. New iOS builds, real OpenCV accuracy/interpolation, device RSS/CPU/latency and pressure qualification remain pending. Private memory accounting is not an RSS guarantee. Details: `IMPLEMENTATION-C01B.md`.
- C01b CI correction: user reported both macOS workflows crashing at objc_retain. The loader now holds NSError strongly across its internal pool and forwards it after drainage, retaining encoded-data accounting through that pool. Added 1,000 malformed-image/error-lifetime cases plus missing-file cleanup and debug symbols with sanitizers enabled. Template/native-budget portable regressions pass again; corrected Foundation/iOS CI remains pending.
- User reported the corrected C01b build at `4e6ef06` passed before C01c1; device qualification remains pending.
- C01c1 / root Vision lifecycle portion of P1-29 + P1-30 + P1-31: task-entry eight-second cooperative budget, two context admissions, bounded source/ROI/output, synchronized instance lifecycle, drained active cancellation timer, no request-completion retain cycle, guarded debug candidates and finally-balanced graphics contexts. Source/pre-capture validation is bounded; full fresh capture and synchronous Vision execution remain. Production TrollStore OCR is unchanged.
- C01c1 validation: 36 source-contract runners, 15 native runners and 528 TrollStore source grep assertions pass on Windows. New macOS Foundation/CoreImage/Vision setup plus controlled execution/capture fixture is wired to both workflows; actual UIKit drawing, real recognition accuracy, new iOS builds and device performance remain pending. Details: `IMPLEMENTATION-C01C1.md`.
- User reported the C01c1 build at `528655c` passed before C01c2; device qualification remains pending.
- C01c2 / root legacy color portion of P1-32 + P1-33 + P1-34 + P1-35: scope-owned images/contexts/RGBA buffers, bounded wire/table parsing, numeric vectors in scan loops, checked 64-bit anchor/stride geometry, two admissions, three-second cooperative local/parent budget, 16M point comparisons, 16 MiB per ROI and 32 MiB private RGBA accounting. Native JS table encoding now matches both root parsers. Full fresh display capture and production TrollStore color implementations are unchanged.
- C01c2 validation: 36 source-contract runners, 16 native runners and 528 TrollStore source grep assertions pass on Windows. New real Foundation/CoreGraphics plus controlled capture/fault/encoder fixture is wired to both workflows; macOS/iOS build, physical coordinate accuracy and device performance checks remain pending. Details: `IMPLEMENTATION-C01C2.md`.
- Vision CI correction (2026-10-23): both workflows reported nonnull-options compilation failure; newer Clang also reported rounded int-to-float bound comparisons. Production now passes an empty VNImageRequestHandler options dictionary and uses a shared finite/double coordinate guard, with portable and manager-fixture boundary regressions. Strict warnings/sanitizers stay enabled; corrected macOS/iOS CI remains pending.
- User reported the C01c2 build and Vision SDK warning corrections at `5ae231b` passed before C01c3a; device qualification remains pending.
- C01c3a / opt-in root Vision part of P1-28 + P1-39: task 27 subtask 6 selects a task-66 BGRA frame, applies stored-scale ROI planning, enforces TTL/max-age and wraps immutable charged bytes in a CGDataProvider without application pixel copying. Missing/stale frames fail without recapture; admitted readers survive store removal until image cleanup. Added Python `ocr_from_frame` using existing v0/v1 transport. Existing task 27.1 and production TrollStore paths retain their behavior; TrollStore's existing subtask-5 probe is untouched.
- C01c3a validation: 36 source-contract runners, 17 native runners and 528 TrollStore source grep assertions pass on Windows, plus exact Python v0/v1/fragmented-response tests. Expanded actual provider/store and provider/Vision Foundation fixtures await macOS/iOS CI and device coordinate/accuracy/performance checks. Details: `IMPLEMENTATION-C01C3A.md`.
- User reported the C01c3a build at `71de52b` passed before C01c3b; device qualification remains pending.
- C01c3b / remaining frame-color and modern matcher portion of P1-25 + P1-32..39: task 69 strict bounded numeric/point/RGB/stride admission, signed/scaled offsets, three-second/16M-work scan budget; tasks 49/68/70 bounded scale preflight, eight-second/256M-work shared request, 32 MiB per-request/64 MiB aggregate scratch admission and bounded batches. Legacy successful reply fields remain. Production TrollStore matching/color and TouchPOC are unchanged.
- C01c3b validation: 36 source-contract runners, 18 native runners and 528 TrollStore source grep assertions pass on Windows, including 3000 frozen full matcher oracle cases and >600k-pixel rounding cases. New actual Foundation/CoreGraphics handler/parser/batch fixture is added to both workflows; macOS/iOS CI and real OpenCV/device qualification remain pending. Details: `IMPLEMENTATION-C01C3B.md`.

- C01c3b CI correction: root macOS compilation reported three unused wire validators in `ImageErrorUnderTest.inc`. The storage runner now extracts only `zx_frameError`, ending before the typed wire-admission section. A cross-platform fixture-boundary assertion prevents accidental validator inclusion; full validators remain exercised by the modern-image handler fixture. Production behavior, `-Werror` and sanitizers are unchanged. Storage and modern-image portable runners pass again on Windows, including 3000 matcher oracle cases. Corrected macOS/iOS CI remains pending.
- User reported the C01c3b build and storage-fixture correction at `74e656f` passed before C01d1; device qualification remains pending.
- C01d1: root C01 request deadlines now begin before daemon FIFO admission and survive IPC-owner transfers and a bounded/versioned CF envelope. Direct daemon/root task entries cap before license; task-local scopes preserve parent output/cancel without mutating parent deadlines. Disconnect cancels local C01 work, and expired queued work is skipped. Existing FIFO and cleanup contracts stay in place.
- C01d1 validation: 36 source-contract runners, 19 native runners and 528 TrollStore source grep assertions pass on Windows, including sink/deadline/token/envelope regressions. New actual task-entry/IPC-sender Foundation fixture and expanded socket/CF callback queue/expiry/disconnect tests await macOS/iOS CI and device qualification. Details: `IMPLEMENTATION-C01D1.md`.
- C01d1 CI correction: both root and TrollStore macOS jobs reported `TLinkIPCNoReplyMessage` undeclared in the extracted sender fixture. Added its production `shared/TLinkIPCPolicy.h` import to the runtime fixture. The ingress runner now compiles sender message IDs against that fixture's own portable imports on every host, catching missing shared dependencies on Windows as well. Ingress, socket and native-budget portable runners pass on Windows; a negative probe confirms the compiler rejects the omitted policy import. Production behavior, strict warnings and sanitizers are unchanged; corrected macOS/iOS CI remains pending.
- Next: C01d2 isolation and late-work cleanup at remaining synchronous queue/IPC/capture/engine/file boundaries. C01 is not marked complete; build reports do not replace device qualification.

## Primary target

Performance-critical runtime remains `pccontrol` in SpringBoard, `tlinkauto-binary` ingress, `tlinkauto-jsd` helper where it is on a live JS call path, and selected `shared` dependencies.

Vendor/decompiled/reference trees remain excluded unless a live path requires them.

## Critical P0 findings through S011

1. **P0-01** recorder does Foundation formatting + synchronous file write per touch event and contaminates event timing.
2. **P0-02** RAW playback performs license verifier synchronization per script line.
3. **P0-03** RAW force-stop publishes idle before worker fully exits.
4. **P0-04** injected IOHID child Create-rule ownership is not balanced.
5. **P0-05** SpringBoard external touch IPC performs hot-path logs + response machinery.
6. **P0-06** MPEG-TS writes one 188-byte packet per TCP send.
7. **P0-07** frame-store insertion deep-copies full BGRA twice.
8. **P0-08** low-resolution H264 profiles capture the full physical display every frame.
9. **P0-09** image-store serial queue is held during expensive CV/color compute.
10. **P0-10** Tesseract cache is unbounded by whitelist/PSM cardinality and cached engines retain last UIImage.
11. **P0-11** Tesseract scale-up can create roughly 33x source-gray source-visible buffer footprint at scale=4 before OCR internals.
12. **P0-12** helper native RPC is discovered by 200 ms polling and uses fresh Unix sockets/status envelopes.
13. **P0-13** in-process JS typed native calls round-trip through NSString wire protocol + NSData + allocated CFWriteStream + response text split.
14. **P0-14** JS bridge drops `TLinkTaskExecutionContext` when entering `processTask`, so cancellation during long native work is not propagated.
15. **P0-15** Scheduler timer registry has cross-thread ownership races; set/remove and repeated set can create ghost/untracked timers.
16. **P0-16** Scheduler accepts arbitrarily small positive repeating intervals and executes launch preparation on the main run loop.
17. **P0-17** Event-channel long poll rechecks the filesystem every 100 ms: directory/permission metadata + lock open/flock + full journal read/JSON parse even with no events.
18. **P0-18** Client disconnect does not cancel deferred event-poll worker or release one of 8 poll slots until event/timeout.
19. **P0-19** Task 59 timeout hierarchy lets the 5 s daemon request fail while SpringBoard remains blocked in an 8–30 s VPN broker operation.
20. **P0-20** UI find/tap materializes a full AX snapshot before matching, while `max_elements` bounds returned rows rather than scanned AX work.
21. **P0-21** TouchPOC TunnelExtension polls an idle TCP client every 5 ms on its serial accept/read queue, producing ~200 wake cycles/s and client head-of-line blocking.
22. **P0-22** live TrollStore `vpnconf.create` can block indefinitely in helper `waitpid(..., 0)` after cancellation is no longer observed.
23. **P0-23** StreamControl supervisor can block its sole lifecycle serial queue indefinitely waiting for one-shot `privhelper`.
24. **P0-24** rootfull verifier cache misses perform a synchronous signed authority round-trip under the process-wide cache queue; 1 s script and 5 s H264 heartbeats repeatedly reach the 5 s refresh boundary.

## S008 supporting findings

- **P1-54** every event publication reads/parses and atomically rewrites the complete 256-event journal under exclusive lock.
- **P1-55** up to eight default-global-queue workers remain active for 20–25 s and repeatedly `usleep(100 ms)`.
- **P1-56** Task-95 legacy response JSON->base64->legacy text; JSON-v1 reparses that legacy response and frames JSON again; large response write returns to global serial `socketQueue`.
- **P1-57** read-only pollers use exclusive `flock`, serializing all readers with publishers.
- **P1-58** malformed journal silently becomes an empty generation and can be overwritten with sequence 1 on the next publish.
- **P2-19** long-poll timeout uses wall-clock NSDate + unsigned subtraction.
- **P2-20** topic regex is recompiled for every Task-95 request.
- **P2-21** filtered batches can require an avoidable immediate empty poll to advance through trailing unrelated events.

## S009 supporting findings

- **P0-19** Task 59 nests a 5 s daemon CFMessagePort wait around broker operations that can wait 8–24 s and a SpringBoard broker socket that can wait 30 s; caller timeout can leave SpringBoard IPC occupied by an abandoned VPN request.
- **P0-20** Task 79/81 build a full AX snapshot before matching; `max_elements` limits returned rows rather than scanned AX elements, so filtered trees can exceed the requested work count until the deadline.
- **P1-59** all AX snapshot/find/hit-test work is serialized on one queue and has no client-cancellation path.
- **P1-60** UI-tree output has no explicit byte/string ceiling and is copied through object graph -> JSON -> base64 -> legacy response text.
- **P1-61** AX lock/capability paths repeat notify/framework/symbol/Security capability setup that is mostly process-stable.
- **P1-62** every Task-60 status snapshot repeats 10 VPN entitlement lookups plus mutable compatibility marker probing.
- **P1-63** VPN broker blocks global utility workers in semaphore waits up to 8/24 s without an explicit active-client cap.
- **P1-64** successful Tasks 78–81 can synchronously cross to SpringBoard main twice for foreground context validation.
- **P2-22** AX deadlines use wall-clock `CFAbsoluteTimeGetCurrent` and are checked only between elements.
- **P2-23** foreground PID fallback can enumerate all processes and read candidate app Info.plists.

## S010 supporting findings

- **P0-21** TouchPOC TunnelExtension TCP server polls an idle nonblocking client every 5 ms on the same serial queue used by accept, yielding roughly 200 sleep/wake iterations/s and accept head-of-line blocking.
- **P0-22** live TrollStore `vpnconf.create` waits on `privhelper` with unbounded `waitpid(..., 0)`; cancellation after spawn cannot be observed until the child exits.
- **P0-23** StreamControl's supervisor performs unbounded one-shot helper waits while holding its only service-lifecycle serial queue.
- **P1-65** standalone TouchPOC deliberately keeps the app resident in background with an infinite zero-volume audio loop.
- **P1-66** TouchPOC tunnel performs 1 Hz command-file read + atomic state rewrite + one/two file-backed log writes while quiet.
- **P1-67** TrollStore private VPN transitions/config publication use fixed 100 ms polling; create verification can rebuild the full private configuration list up to 50 times.
- **P1-68** TrollStore foreground VPN broker is single-client HOL while background vpnagent can consume unbounded global utility workers for long waits.
- **P1-69** appdelegate keyboard observer removal targets a different notification name than registration; duplicate delivery risk requires device counting.
- **P1-70** TrollStore VPN foreground/background brokers repeat the full static diagnostics preflight per operation, extending S009 P1-62.
- **P2-24** appdelegate globally hooks `_dyld_get_image_name` and adds suffix-check work to all such calls in injected processes.
- **P2-25** TouchPOC root UI runs a permanent 1 Hz diagnostic refresh timer.
- **P2-26** TrollStore private VPN polling deadlines use wall-clock NSDate time.

## S011 supporting findings

- **P0-24** rootfull verifier cache misses synchronously perform a signed authority IPC/crypto refresh while holding the process-wide cache queue; ScriptPlayer 1 Hz and H264 5 s heartbeats repeatedly hit the 5 s TTL boundary.
- **P1-71** active rootfull processes still read the generation file every 250 ms of feature-check activity despite Darwin-notify cache invalidation.
- **P1-72** license authority dispatches every accepted client to the global utility queue with no explicit active-client cap.
- **P1-73** each authority status proof redundantly validates the signed lease on both sides and performs repeated device-key/signature operations.
- **P1-74** lease save executes repeated full status validation and reset/recreate work around the signed trust checkpoint.
- **P1-75** lifecycle refresh single-flight begins after expensive `localStatus`, allowing launch/foreground triggers to duplicate crypto/disk work before coalescing.
- **P1-76** BGTask expiration/22 s watchdog does not cancel the 20 s HTTP request or suppress late supervisor ensure work.
- **P1-77** license lifecycle diagnostics repeatedly read and atomically rewrite the complete plist during one logical refresh.
- **P1-78** rootfull tasks 75/76/97 bypass the feature cache and force a fresh authority proof on every diagnostic request.
- **P2-27** process-stable license configuration/release-integrity metadata is repeatedly reloaded during full status evaluation.
- **P2-28** lifecycle retry/backoff elapsed timing is persisted/compared with wall-clock timestamps.

## Important S008 load model

The source-visible continuous subscription path in WebTango:
- default timeout = 20 s,
- Task 95 request waits in daemon,
- daemon checks journal every 100 ms,
- client immediately issues another poll after batch/timeout.

Therefore:

**one quiet subscriber ~= 10 persistence poll cycles/s**

At configured max 8 active polls:

**up to ~=80 persistence poll cycles/s while no events arrive**

Every cycle can include:
- createDirectory,
- chmod/lchown event directory,
- open/chmod/lchown lock file,
- exclusive flock,
- read full journal,
- JSON parse,
- scan event array,
- unlock/close.

These are source-derived operation-rate estimates, not measured CPU percentages.

## Important lifecycle conclusion

Task 95 is correctly deferred off the daemon's serial socket queue, so the 20-second wait itself does not block all socket reads.

The actual issues are:
1. periodic file polling + worker wakeups,
2. disconnected polls continuing to consume work/capacity,
3. publisher/read lock contention,
4. synchronous response write on `socketQueue` when the poll finally completes.

The intended redesign should preserve durable cursor replay while moving **notification/waiting** out of the filesystem polling loop.

## Benchmark documents

- `BENCHMARK-S002.md`: recording / RAW / touch ownership / timing.
- `BENCHMARK-S003.md`: IPC/socket/H264/backpressure/adaptive streaming.
- `BENCHMARK-S004.md`: capture/frame/image memory and queue contention.
- `BENCHMARK-S005.md`: OCR/template/color compute.
- `BENCHMARK-S006.md`: JS helper/in-process bridge/cancellation/log/file paths.
- `BENCHMARK-S007.md`: scheduler races/wakeups + history/config/log persistence.
- `BENCHMARK-S008.md`: event-channel idle polling/cancellation/journal/Task-95 output.
- `BENCHMARK-S009.md`: Task-59 timeout hierarchy/broker concurrency + AX traversal/cancellation/result bounds/status diagnostics.
- `BENCHMARK-S010.md`: TouchPOC idle residency/tunnel polling + TrollStore helper deadlines/private VPN polling/broker concurrency/appdelegate compatibility.
- `BENCHMARK-S011.md`: license authority/cache/generation/crypto + lease/lifecycle/background cancellation and diagnostics.

Use aggregate counters and profiling-build sampled signposts. Do not add per-poll-iteration production logs.

## Original S011 ranking (historical)

Implementation order is now maintained in `REVIEW-IMPLEMENTATION-PLAN.md`. Prototype TouchPOC work is excluded by the 2026-10-16 user scope; A01 is implemented pending target validation. The source-audit record below is retained for traceability.

Low-risk correctness first, then highest-frequency hot paths:

1. **P0-04** balance IOHID child ownership.
2. **P1-19** iPad capture CF ownership/null handling.
3. **P0-15** serialize scheduler timer lifecycle + generations.
4. **P0-14** preserve JS task cancellation context through native execution.
5. **P0-07** move/emplace frame buffers into store.
6. **P0-24** move signed license-authority refresh off synchronous feature checks and make refresh single-flight/snapshot-based.
7. **P0-22** add bounded helper deadline/cancellation/reap semantics to TrollStore `vpnconf.create`.
8. **P0-23** remove unbounded `privhelper` waits from the StreamControl supervisor serial queue.
9. **P0-19** remove long VPN transitions from synchronous SpringBoard CFMessagePort lifetime / repair timeout hierarchy.
10. **P0-20** single-pass AX find/tap + hard scanned-work budget.
11. **P0-17/P0-18** event-driven event-channel wait + disconnect cancellation.
12. **P0-05** external hot IPC no-log/no-response fast path.
13. **P0-16** minimum scheduler interval/coalescing + cheap busy rejection.
14. **P0-01** recorder timing/I/O decoupling.
15. **P0-03** RAW lifecycle state fix.
16. **P0-02** trusted RAW license fast path.
17. **P0-12** event-driven helper RPC transport.
18. **P0-13** structured in-process JS native fast path.
19. **P0-06** batch MPEG-TS network writes.
20. **P1-12** bounded H264 backpressure.
21. **P0-08** target-resolution/reusable streaming capture.
22. **P0-09** immutable image/frame snapshots with short store critical sections.
23. **P0-10/P0-11** Tesseract cache/pixel budgets.
24. **P0-21 — EXCLUDED** prototype TouchPOC is not part of the implementation backlog.
25. **P1-71/P1-72/P1-73** generation invalidation + authority admission/proof caching.
26. **P1-74/P1-75/P1-76** lease commit/lifecycle coalescing/BGTask cancellation.
27. **P1-59/P1-60/P1-62/P1-63** AX cancellation/output + rootfull VPN status/broker cleanup.
28. **P1-67/P1-68/P1-70** TrollStore private VPN polling/broker/preflight cleanup.
29. **P1-48/P1-49/P1-50/P1-51** persistence/index/log/status cleanup.
30. **P1-54/P1-56/P1-57** event journal/output amplification cleanup.
31. Remaining P1/P2 based on benchmark results.

## Next phase — benchmark validation / patch planning

The intentionally in-scope **source audit first pass is complete at S011**. There is no automatic S012 source-scan scope.

Remaining work should now be evidence/implementation driven:
1. run the benchmark probes in `BENCHMARK-S002.md` through `BENCHMARK-S011.md` on representative devices,
2. validate source-derived frequency/cost estimates and reprioritize by measured CPU, wakeups, memory, latency and energy,
3. patch the highest-ranked correctness/performance findings in small groups,
4. rerun the matching benchmark probe after each group,
5. only reopen source audit for vendor/reference code if a measured live call path requires it.

If continuing without device benchmark data, start patch planning from the updated implementation priority rather than scanning additional directories.

## Resume instruction

At the next session read:
1. this file,
2. `FINDINGS.md`,
3. `COVERAGE.md`,
4. the benchmark document matching the finding being validated or fixed.

Do not create S012 merely to rescan already covered source.


